#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME/.claude" "$XDG_CONFIG_HOME/dotfiles"
printf '%s\n' violet > "$XDG_CONFIG_HOME/dotfiles/theme"
printf '%s\n' '{"permissions":{"allow":["Read"]},"theme":"dark"}' > "$HOME/.claude/settings.json"

bash "$root/scripts/install-claude-theme"
python3 - <<'PY'
import json
from pathlib import Path
home = Path.home()
theme = json.loads((home / ".claude/themes/agent-config-selected.json").read_text())
settings = json.loads((home / ".claude/settings.json").read_text())
assert theme["overrides"]["userMessageBackground"].startswith("#")
assert theme["overrides"]["userMessageBackground"] != "#b1a5e5"
assert "text" not in theme["overrides"]
assert settings["theme"] == "custom:agent-config-selected"
assert settings["permissions"]["allow"] == ["Read"]
PY

# Idempotence and theme change.
bash "$root/scripts/install-claude-theme" > /dev/null
old=$(python3 -c 'import json, pathlib; print(json.loads((pathlib.Path.home()/".claude/themes/agent-config-selected.json").read_text())["overrides"]["userMessageBackground"])')
printf '%s\n' orange > "$XDG_CONFIG_HOME/dotfiles/theme"
bash "$root/scripts/install-claude-theme" > /dev/null
new=$(python3 -c 'import json, pathlib; print(json.loads((pathlib.Path.home()/".claude/themes/agent-config-selected.json").read_text())["overrides"]["userMessageBackground"])')
[[ $old != "$new" ]]

# Every palette must result in a distinct, hue-specific dark background.
declare -A expected=(
  [teal]='#548687'
  [violet]='#5d5487'
  [orange]='#876d54'
  [blue]='#547087'
  [red]='#875457'
  [green]='#54876e'
)
for variant in teal violet orange blue red green; do
  printf '%s\n' "$variant" > "$XDG_CONFIG_HOME/dotfiles/theme"
  bash "$root/scripts/install-claude-theme" > /dev/null
  actual=$(python3 -c 'import json, pathlib; print(json.loads((pathlib.Path.home()/".claude/themes/agent-config-selected.json").read_text())["overrides"]["userMessageBackground"])')
  [[ "$actual" == "${expected[$variant]}" ]] || {
    echo "FAIL: $variant background was $actual, expected ${expected[$variant]}" >&2
    exit 1
  }
done

# Unknown palette must not change either file.
printf '%s\n' invalid > "$XDG_CONFIG_HOME/dotfiles/theme"
if bash "$root/scripts/install-claude-theme" > /dev/null 2>&1; then
  echo 'FAIL: invalid palette accepted' >&2
  exit 1
fi

# Refuse to overwrite unrelated theme with the reserved name.
printf '%s\n' teal > "$XDG_CONFIG_HOME/dotfiles/theme"
printf '%s\n' '{"name":"Personal"}' > "$HOME/.claude/themes/agent-config-selected.json"
if bash "$root/scripts/install-claude-theme" > /dev/null 2>&1; then
  echo 'FAIL: unmanaged theme overwritten' >&2
  exit 1
fi
grep -q Personal "$HOME/.claude/themes/agent-config-selected.json"

echo 'PASS: Claude theme palette, contrast, settings preservation, and safety'
