#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$XDG_CONFIG_HOME/dotfiles"
theme_file="$HOME/.bob/theme.json"
background() { python3 -c 'import json, pathlib; print(json.loads((pathlib.Path.home()/".bob/theme.json").read_text())["backgroundColor"])'; }

# Creates ~/.bob when missing and keeps Bob's dark palette apart from the user message.
printf '%s\n' violet > "$XDG_CONFIG_HOME/dotfiles/theme"
bash "$root/scripts/install-bob-theme"
python3 - <<'PY'
import json
from pathlib import Path
theme = json.loads((Path.home() / ".bob/theme.json").read_text())
assert theme["name"] == "Agent Config (Selected)"
assert theme["backgroundColor"] == "#5d5487"
assert theme["foregroundColor"] == "#f4f4f4"
assert theme["primaryColor"] == "cyan"
assert theme["successColor"] == "green"
PY

# Same hue-specific backgrounds as the Claude theme.
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
  bash "$root/scripts/install-bob-theme" > /dev/null
  actual=$(background)
  [[ "$actual" == "${expected[$variant]}" ]] || {
    echo "FAIL: $variant background was $actual, expected ${expected[$variant]}" >&2
    exit 1
  }
done
[[ $(AGENT_CONFIG_THEME_VARIANT=red bash "$root/scripts/install-bob-theme" > /dev/null; background) == '#875457' ]]

# Unknown palette must not change the file.
before=$(cat "$theme_file")
printf '%s\n' invalid > "$XDG_CONFIG_HOME/dotfiles/theme"
if bash "$root/scripts/install-bob-theme" > /dev/null 2>&1; then
  echo 'FAIL: invalid palette accepted' >&2
  exit 1
fi
[[ $(cat "$theme_file") == "$before" ]]

# Refuse to overwrite a user-managed Bob theme.
printf '%s\n' teal > "$XDG_CONFIG_HOME/dotfiles/theme"
printf '%s\n' '{"primaryColor":"#ffffff"}' > "$theme_file"
if bash "$root/scripts/install-bob-theme" > /dev/null 2>&1; then
  echo 'FAIL: unmanaged theme overwritten' >&2
  exit 1
fi
grep -q '#ffffff' "$theme_file"

echo 'PASS: Bob theme palette, dark defaults, and safety'
