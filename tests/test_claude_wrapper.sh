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
printf '%s\n' "${SSH_CONNECTION-unset}|${SSH_TTY-unset}|${SSH_CLIENT-unset}" > "$HOME/claude-ssh"
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

# Over ssh -X, hide SSH markers so Claude uses xclip instead of OSC 52.
ssh_vars=(SSH_CONNECTION='1 2 3 4' SSH_TTY=/dev/pts/9 SSH_CLIENT='1 2 3')
mkdir -p "$tmp/xclip"
printf '#!/bin/sh\n' > "$tmp/xclip/xclip"
chmod +x "$tmp/xclip/xclip"
# PATH without any real xclip, so the "missing xclip" case is deterministic.
no_xclip_path="$root/bin:$tmp/real"
IFS=: read -r -a entries <<< "$PATH"
for entry in "${entries[@]}"; do
  [[ -n $entry && ! -e $entry/xclip ]] && no_xclip_path+=":$entry"
done

env "${ssh_vars[@]}" DISPLAY=localhost:10.0 PATH="$tmp/xclip:$no_xclip_path" bash "$root/bin/claude" --version
if [[ $(uname -s) == Linux ]]; then
  [[ $(cat "$HOME/claude-ssh") == 'unset|unset|unset' ]] || { echo "FAIL: SSH markers kept with X11: $(cat "$HOME/claude-ssh")" >&2; exit 1; }
else
  [[ $(cat "$HOME/claude-ssh") == '1 2 3 4|/dev/pts/9|1 2 3' ]]
fi

env -u DISPLAY "${ssh_vars[@]}" PATH="$tmp/xclip:$no_xclip_path" bash "$root/bin/claude" --version
[[ $(cat "$HOME/claude-ssh") == '1 2 3 4|/dev/pts/9|1 2 3' ]] || { echo 'FAIL: SSH markers removed without DISPLAY' >&2; exit 1; }

env "${ssh_vars[@]}" DISPLAY=localhost:10.0 PATH="$no_xclip_path" bash "$root/bin/claude" --version
[[ $(cat "$HOME/claude-ssh") == '1 2 3 4|/dev/pts/9|1 2 3' ]] || { echo 'FAIL: SSH markers removed without xclip' >&2; exit 1; }

echo 'PASS: Claude wrapper refreshes theme and selects the clipboard path on each launch'
