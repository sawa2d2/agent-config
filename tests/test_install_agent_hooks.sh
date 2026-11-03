#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
unset CODEX_HOME
codex="$HOME/.codex/hooks.json"
bob="$HOME/.bob/settings/settings.json"
claude="$HOME/.claude/settings.json"
fail() { echo "FAIL: $*" >&2; exit 1; }
# PATH holds python3 and, in $tmp/rtk-bin only, a fake rtk.
mkdir -p "$tmp/bin" "$tmp/rtk-bin"
ln -s "$(command -v python3)" "$tmp/bin/python3"
printf '#!/bin/sh\n' > "$tmp/rtk-bin/rtk" && chmod +x "$tmp/rtk-bin/rtk"
install_hooks() { PATH="$tmp/bin:/usr/bin:/bin" bash "$root/scripts/install-agent-hooks"; }
install_hooks_rtk() { PATH="$tmp/rtk-bin:$tmp/bin:/usr/bin:/bin" bash "$root/scripts/install-agent-hooks"; }
check() {
  CODEX="$codex" BOB="$bob" CLAUDE="$claude" STATUS="$root/scripts/agent-tmux-status" SUGGEST="$root/scripts/bob-handoff-suggest" \
    APPROVAL="$root/scripts/agent-approval-marker" python3 -c "
import json, os
bob, claude, codex = (json.load(open(os.environ[k])) for k in ('BOB', 'CLAUDE', 'CODEX'))
status, suggest, approval = os.environ['STATUS'], os.environ['SUGGEST'], os.environ['APPROVAL']
def states(settings, event):
    return [(g.get('matcher'), h['command']) for g in settings['hooks'].get(event, []) for h in g['hooks']]
assert $1, (bob, claude, codex)
" || fail "$1"
}

# New machine: all agents get status hooks, including Codex without rtk.
install_hooks > /dev/null
check "sorted(codex['hooks']) == ['Interrupt', 'PermissionRequest', 'PostToolUse', 'PreCompact', 'PreToolUse', 'SessionEnd', 'Stop', 'UserPromptSubmit']"
check "all(states(codex, e) == [(None, status + ' ' + state)] for e, state in [('PreToolUse', 'working'), ('PostToolUse', 'working'), ('PermissionRequest', 'waiting'), ('Stop', 'done'), ('Interrupt', 'clear'), ('SessionEnd', 'clear')])"
check "states(bob, 'Stop') == [(None, status + ' done')] and states(bob, 'SessionStart') == [(None, status + ' clear')]"
check "sorted(bob['hooks']) == ['PostToolUse', 'PreToolUse', 'SessionStart', 'Stop', 'UserPromptSubmit']"
check "states(claude, 'Notification') == [('permission_prompt', status + ' waiting')]"
check "sorted(claude['hooks']) == ['Notification', 'PostToolUse', 'PreToolUse', 'SessionEnd', 'Stop', 'UserPromptSubmit']"
check "states(bob, 'UserPromptSubmit') == [(None, status + ' prompt'), (None, suggest), (None, approval)]"
check "states(bob, 'PostToolUse') == [(None, status + ' working'), (None, suggest)]"
check "states(claude, 'UserPromptSubmit') == [(None, status + ' prompt'), (None, approval)]"
check "all(cmd.endswith((' prompt', ' working', ' done', ' waiting', ' clear')) for s in (bob, claude) for e in s['hooks'] for _, cmd in states(s, e) if cmd not in (suggest, approval))"

check "states(codex, 'UserPromptSubmit') == [(None, status + ' prompt'), (None, approval)]"

# The approval-wait command observes only: success with no decision output.
CODEX="$codex" python3 - <<'PYTEST'
import json, os, subprocess
settings = json.load(open(os.environ['CODEX']))
command = settings['hooks']['PermissionRequest'][0]['hooks'][0]['command']
env = {k: v for k, v in os.environ.items() if k not in ('TMUX', 'TMUX_PANE')}
result = subprocess.run(command, shell=True, input='{"tool_name":"Bash"}',
                        text=True, capture_output=True, env=env)
assert (result.returncode, result.stdout, result.stderr) == (0, '', ''), result
PYTEST

check "states(codex, 'PreCompact') == [('auto', '$root/scripts/codex-handoff-suggest')]"

# Re-running leaves the files untouched.
before=$(cat "$bob" "$claude" "$codex")
out=$(install_hooks)
[[ -z $out && $(cat "$bob" "$claude" "$codex") == "$before" ]] || fail "second run changed files: $out"

# With rtk installed, its hook rewrites Claude's Bash and Bob's execute_command calls.
install_hooks_rtk > /dev/null
check "states(claude, 'PreToolUse') == [(None, status + ' working'), ('Bash', 'rtk hook claude')]"
check "states(bob, 'PreToolUse') == [(None, status + ' working'), ('^execute_command$', 'rtk hook claude')]"
check "states(codex, 'PreToolUse') == [(None, status + ' working'), ('Bash', '$root/scripts/codex-rtk-hook')]"
rtk_before=$(cat "$bob" "$claude" "$codex")
out=$(install_hooks_rtk)
[[ -z $out && $(cat "$bob" "$claude" "$codex") == "$rtk_before" ]] || fail "second rtk run changed files: $out"

# Once rtk is gone, its entries are removed.
install_hooks > /dev/null
[[ $(cat "$bob" "$claude" "$codex") == "$before" ]] || fail 'rtk entries not removed'

codex_before=$(cat "$codex")
# A custom Codex home preserves unmanaged entries and replaces old managed paths.
export CODEX_HOME="$tmp/custom-codex"
mkdir -p "$CODEX_HOME"
cat > "$CODEX_HOME/hooks.json" <<'JSON'
{"description": "mine", "hooks": {"UserPromptSubmit": [
  {"hooks": [{"type": "command", "command": "echo custom"}]},
  {"hooks": [{"type": "command", "command": "/old/scripts/agent-approval-marker"}]}]}}
JSON
install_hooks >/dev/null
HANDOFF="$root/scripts/codex-handoff-suggest" STATUS="$root/scripts/agent-tmux-status" CUSTOM="$CODEX_HOME/hooks.json" APPROVAL="$root/scripts/agent-approval-marker" python3 - <<'CHECK'
import json, os
settings = json.load(open(os.environ['CUSTOM']))
assert settings['hooks'].pop('PreCompact') == [{'matcher': 'auto', 'hooks': [{'type': 'command', 'command': os.environ['HANDOFF']}]}]
assert settings['description'] == 'mine'
assert settings['hooks']['UserPromptSubmit'] == [
    {'hooks': [{'type': 'command', 'command': 'echo custom'}]},
    {'hooks': [{'type': 'command', 'command': os.environ['STATUS'] + ' prompt'}]},
    {'hooks': [{'type': 'command', 'command': os.environ['APPROVAL']}]}]
CHECK
[[ $(cat "$codex") == "$codex_before" ]] || fail 'default Codex home changed'
unset CODEX_HOME

# Other hooks and settings are kept; entries from another checkout path are replaced.
cat > "$claude" <<'JSON'
{"theme": "dark", "hooks": {
  "Stop": [{"hooks": [{"type": "command", "command": "say done"}]},
           {"hooks": [{"type": "command", "command": "/old/agent-config/scripts/agent-tmux-status done"}]}],
  "PreCompact": [{"hooks": [{"type": "command", "command": "/old/agent-config/scripts/agent-tmux-status working"}]}]}}
JSON
chmod 600 "$claude"
install_hooks > /dev/null
check "claude['theme'] == 'dark'"
check "states(claude, 'Stop') == [(None, 'say done'), (None, status + ' done')]"
check "'PreCompact' not in claude['hooks']"
[[ $(stat -c %a "$claude" 2>/dev/null || stat -f %Lp "$claude") == 600 ]] || fail 'mode not kept'

# Codex preserves unmanaged hooks, including siblings of an old managed hook,
# and respects CODEX_HOME without changing the default file.
cp "$codex" "$tmp/default-codex.json"
export CODEX_HOME="$tmp/custom-codex"
mkdir -p "$CODEX_HOME"
codex="$CODEX_HOME/hooks.json"
cat > "$codex" <<'JSON'
{"custom": true, "hooks": {"PermissionRequest": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": "custom-permission-policy"},
  {"type": "command", "command": "/old/scripts/agent-tmux-status waiting"}]}]}}
JSON
chmod 600 "$codex"
install_hooks > /dev/null
check "codex['custom'] and states(codex, 'PermissionRequest') == [('Bash', 'custom-permission-policy'), (None, status + ' waiting')]"
[[ $(stat -c %a "$codex" 2>/dev/null || stat -f %Lp "$codex") == 600 ]] || fail 'Codex mode not kept'
cmp "$HOME/.codex/hooks.json" "$tmp/default-codex.json" || fail 'default CODEX_HOME changed'
custom_before=$(cat "$codex")
[[ -z $(install_hooks) && $(cat "$codex") == "$custom_before" ]] || fail 'custom CODEX_HOME not idempotent'

# Commands survive paths with spaces.
mkdir -p "$tmp/with space"
cp -R "$root/scripts" "$tmp/with space/"
PATH="$tmp/bin:/usr/bin:/bin" bash "$tmp/with space/scripts/install-agent-hooks" > /dev/null
check "states(bob, 'Stop') == [(None, \"'$tmp/with space/scripts/agent-tmux-status' done\")]"

# Invalid settings are refused without changes.
printf '%s\n' '{"hooks": {"Stop": {}}}' > "$bob"
install_hooks > /dev/null 2>&1 && fail 'invalid hooks accepted'
[[ $(cat "$bob") == '{"hooks": {"Stop": {}}}' ]] || fail 'invalid hooks changed'
# A symlinked settings file is updated through the link; a dangling link gets a new target.
rm "$bob" && ln -s "$tmp/links/target.json" "$bob"
install_hooks > /dev/null || fail 'symlink refused'
[[ -L $bob ]] || fail 'symlink replaced'
grep -q agent-tmux-status "$tmp/links/target.json" || fail 'symlink target not updated'

echo 'PASS: install-agent-hooks'
