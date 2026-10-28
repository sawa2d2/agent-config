#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
unset CODEX_HOME
mkdir -p "$XDG_CONFIG_HOME/dotfiles"
theme_file="$HOME/.codex/themes/agent-config-selected.tmTheme"
config="$HOME/.codex/config.toml"
fail() { echo "FAIL: $*" >&2; exit 1; }
install_theme() { bash "$root/scripts/install-codex-theme"; }
accent() {
  python3 -c '
import plistlib, sys
theme = plistlib.load(open(sys.argv[1], "rb"))
print(*[s["settings"]["foreground"] for s in theme["settings"] if "agent-config" in s.get("name", "")])
' "$theme_file"
}

# New machine: the Mocha theme gets the selected color for inline code, types and accent
# and becomes the Codex theme.
printf '%s\n' violet > "$XDG_CONFIG_HOME/dotfiles/theme"
install_theme > /dev/null
[[ $(accent) == "$(printf '#b1a5e5 %.0s' {1..9} | sed 's/ $//')" ]] || fail "accent: $(accent)"
python3 - "$theme_file" "$root/deploy/codex/themes/catppuccin-mocha.tmTheme" <<'PY' || fail 'base theme not kept'
import plistlib, sys
theme, base = (plistlib.load(open(path, "rb")) for path in sys.argv[1:])
assert theme["name"] == "Agent Config (Selected)"
managed = [rule for rule in theme["settings"] if "agent-config" in rule.get("name", "")]
assert len(theme["settings"]) == len(base["settings"]) + 2
# Only colors of type rules change; their fontStyle and position stay.
for rule, original in zip(theme["settings"], base["settings"]):
    if rule in managed:
        assert rule["scope"] == original["scope"] and rule["settings"].get("fontStyle") == original["settings"].get("fontStyle")
    else:
        assert rule == original
PY
[[ $(cat "$config") == $'[tui]\ntheme = "agent-config-selected"' ]] || fail "config: $(cat "$config")"

# A variant change updates the accent; re-running changes nothing else.
before=$(cat "$config")
AGENT_CONFIG_THEME_VARIANT=red install_theme > /dev/null
[[ $(accent) == "$(printf '#ed9298 %.0s' {1..9} | sed 's/ $//')" && $(cat "$config") == "$before" ]] || fail 'variant update'
snapshot=$(cat "$theme_file" "$config")
AGENT_CONFIG_THEME_VARIANT=red install_theme > /dev/null
[[ $(cat "$theme_file" "$config") == "$snapshot" ]] || fail 'second run changed files'

# An existing [tui] table gets the key; other settings stay.
cat > "$config" <<'TOML'
model = "gpt"

[tui]
screen_reader_detection_done = true

[projects."/work"]
trust_level = "trusted"
TOML
install_theme > /dev/null
python3 - "$config" <<'PY' || fail "tui insert: $(cat "$config")"
import sys
text = open(sys.argv[1]).read()
assert text == '''model = "gpt"

[tui]
theme = "agent-config-selected"
screen_reader_detection_done = true

[projects."/work"]
trust_level = "trusted"
''', text
PY

# A theme chosen by the user is kept, in a table or as a dotted key.
printf '%s\n' '[tui]' 'theme = "dracula"' > "$config"
out=$(install_theme)
[[ $(cat "$config") == $'[tui]\ntheme = "dracula"' && $out == *'Kept Codex theme "dracula"'* ]] || fail 'user theme replaced'
printf '%s\n' 'tui.theme = "dracula"' > "$config"
install_theme > /dev/null
[[ $(cat "$config") == 'tui.theme = "dracula"' ]] || fail 'dotted user theme replaced'
# A theme key of another table does not count.
printf '%s\n' '[other]' 'theme = "x"' > "$config"
install_theme > /dev/null
grep -q '^theme = "agent-config-selected"$' "$config" || fail "other table: $(cat "$config")"

# CODEX_HOME is honored.
CODEX_HOME="$tmp/codex-home" install_theme > /dev/null
[[ -f "$tmp/codex-home/themes/agent-config-selected.tmTheme" && -f "$tmp/codex-home/config.toml" ]] || fail 'CODEX_HOME'

# Unknown variants and unmanaged theme files change nothing.
snapshot=$(cat "$theme_file" "$config")
AGENT_CONFIG_THEME_VARIANT=invalid install_theme > /dev/null 2>&1 && fail 'invalid palette accepted'
[[ $(cat "$theme_file" "$config") == "$snapshot" ]] || fail 'invalid palette changed files'
python3 -c 'import plistlib, sys; plistlib.dump({"name": "Mine", "settings": []}, open(sys.argv[1], "wb"))' "$theme_file"
install_theme > /dev/null 2>&1 && fail 'unmanaged theme overwritten'
grep -q '<string>Mine</string>' "$theme_file" || fail 'unmanaged theme changed'

echo 'PASS: Codex theme colors, selection, and safety'
