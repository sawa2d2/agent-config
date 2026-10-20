#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME/.claude" "$XDG_CONFIG_HOME/dotfiles" "$tmp/real" 
printf '%s\n' violet > "$XDG_CONFIG_HOME/dotfiles/theme"
printf '%s\n' '{"permissions":{"allow":["Read"]}}' > "$HOME/.claude/settings.json"

cat > "$tmp/real/claude" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$HOME/claude-args"
printf '%s\n' "${CLAUDE_CODE_TMUX_TRUECOLOR:-}" > "$HOME/claude-truecolor"
MOCK
chmod +x "$tmp/real/claude"

export PATH="$root/bin:$tmp/real:$PATH"
bash "$root/bin/claude" --version
[[ $(cat "$HOME/claude-args") == --version ]]
[[ $(cat "$HOME/claude-truecolor") == 1 ]]
old=$(python3 -c 'import json, pathlib; print(json.loads((pathlib.Path.home()/".claude/themes/agent-config-selected.json").read_text())["overrides"]["userMessageBackground"])')

printf '%s\n' orange > "$XDG_CONFIG_HOME/dotfiles/theme"
bash "$root/bin/claude" -p hello
[[ $(cat "$HOME/claude-args") == $'-p\nhello' ]]
new=$(python3 -c 'import json, pathlib; print(json.loads((pathlib.Path.home()/".claude/themes/agent-config-selected.json").read_text())["overrides"]["userMessageBackground"])')
[[ $old != "$new" ]]
python3 - <<'PY'
import json
from pathlib import Path
settings=json.loads((Path.home()/".claude/settings.json").read_text())
assert settings["permissions"]["allow"] == ["Read"]
assert settings["theme"] == "custom:agent-config-selected"
PY

echo 'PASS: Claude wrapper refreshes theme on each launch'
