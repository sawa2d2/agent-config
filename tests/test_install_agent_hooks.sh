#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
bob="$HOME/.bob/settings/settings.json"
claude="$HOME/.claude/settings.json"
fail() { echo "FAIL: $*" >&2; exit 1; }
install_hooks() { bash "$root/scripts/install-agent-hooks"; }
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

# New machine: both settings files are created with every hook.
install_hooks > /dev/null
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
bash "$tmp/with space/scripts/install-agent-hooks" > /dev/null
check "states(bob, 'Stop') == [(None, \"'$tmp/with space/scripts/agent-tmux-status' done\")]"

# Invalid settings are refused without changes.
printf '%s\n' '{"hooks": {"Stop": {}}}' > "$bob"
install_hooks > /dev/null 2>&1 && fail 'invalid hooks accepted'
[[ $(cat "$bob") == '{"hooks": {"Stop": {}}}' ]] || fail 'invalid hooks changed'
rm "$bob" && ln -s "$tmp/target.json" "$bob"
install_hooks > /dev/null 2>&1 && fail 'symlink accepted'

echo 'PASS: install-agent-hooks'
