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
  BOB="$bob" CLAUDE="$claude" STATUS="$root/scripts/agent-tmux-status" python3 -c "
import json, os
bob, claude = (json.load(open(os.environ[k])) for k in ('BOB', 'CLAUDE'))
status = os.environ['STATUS']
def states(settings, event):
    return [(g.get('matcher'), h['command']) for g in settings['hooks'].get(event, []) for h in g['hooks']]
assert $1, (bob, claude)
" || fail "$1"
}

# New machine: both settings files are created with every hook; Codex hooks.json only with rtk.
install_hooks > /dev/null
[[ ! -e $codex ]] || fail 'Codex hooks.json created without rtk'
check "states(bob, 'Stop') == [(None, status + ' done')] and states(bob, 'SessionStart') == [(None, status + ' clear')]"
check "sorted(bob['hooks']) == ['PostToolUse', 'PreToolUse', 'SessionStart', 'Stop', 'UserPromptSubmit']"
check "states(claude, 'Notification') == [('permission_prompt', status + ' waiting')]"
check "sorted(claude['hooks']) == ['Notification', 'PostToolUse', 'PreToolUse', 'SessionEnd', 'Stop', 'UserPromptSubmit']"
check "states(bob, 'UserPromptSubmit') == [(None, status + ' prompt')] and states(claude, 'UserPromptSubmit') == [(None, status + ' prompt')]"
check "all(cmd.endswith((' prompt', ' working', ' done', ' waiting', ' clear')) for s in (bob, claude) for e in s['hooks'] for _, cmd in states(s, e))"

# Re-running leaves the files untouched.
before=$(cat "$bob" "$claude")
out=$(install_hooks)
[[ -z $out && $(cat "$bob" "$claude") == "$before" ]] || fail "second run changed files: $out"

# With rtk installed, its hook rewrites Claude's Bash and Bob's execute_command calls.
install_hooks_rtk > /dev/null
check "states(claude, 'PreToolUse') == [(None, status + ' working'), ('Bash', 'rtk hook claude')]"
check "states(bob, 'PreToolUse') == [(None, status + ' working'), ('^execute_command$', 'rtk hook claude')]"
CODEX="$codex" HOOK="$root/scripts/codex-rtk-hook" python3 -c "
import json, os
d = json.load(open(os.environ['CODEX']))
assert d == {'hooks': {'PreToolUse': [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': os.environ['HOOK']}]}]}}, d
" || fail "Codex hooks.json: $(cat "$codex")"
rtk_before=$(cat "$bob" "$claude" "$codex")
out=$(install_hooks_rtk)
[[ -z $out && $(cat "$bob" "$claude" "$codex") == "$rtk_before" ]] || fail "second rtk run changed files: $out"

# Once rtk is gone, its entries are removed.
install_hooks > /dev/null
[[ $(cat "$bob" "$claude") == "$before" ]] || fail 'rtk entries not removed'
CODEX="$codex" python3 -c "import json, os; assert json.load(open(os.environ['CODEX'])) == {'hooks': {}}" \
  || fail "Codex rtk entry not removed: $(cat "$codex")"

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

# Commands survive paths with spaces.
mkdir -p "$tmp/with space"
cp -R "$root/scripts" "$tmp/with space/"
PATH="$tmp/bin:/usr/bin:/bin" bash "$tmp/with space/scripts/install-agent-hooks" > /dev/null
check "states(bob, 'Stop') == [(None, \"'$tmp/with space/scripts/agent-tmux-status' done\")]"

# Invalid settings are refused without changes.
printf '%s\n' '{"hooks": {"Stop": {}}}' > "$bob"
install_hooks > /dev/null 2>&1 && fail 'invalid hooks accepted'
[[ $(cat "$bob") == '{"hooks": {"Stop": {}}}' ]] || fail 'invalid hooks changed'
rm "$bob" && ln -s "$tmp/target.json" "$bob"
install_hooks > /dev/null 2>&1 && fail 'symlink accepted'

echo 'PASS: install-agent-hooks'
