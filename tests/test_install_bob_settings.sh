#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
settings="$HOME/.bob/settings/settings.json"
fail() { echo "FAIL: $*" >&2; exit 1; }
check() { python3 -c "import json, sys; d = json.load(open(sys.argv[1])); assert $1, d" "$settings" || fail "$1"; }

# Creates the file with the defaults when missing.
bash "$root/scripts/install-bob-settings" > /dev/null
check 'd == {"session": {"maxTurns": 300, "limitWarnings": True}}'

# Keeps unrelated settings and values the user set; adds only missing keys.
printf '%s\n' '{"approval": {"forbiddenApprovalGroups": []}, "session": {"maxTurns": 50}}' > "$settings"
chmod 600 "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null
check 'd == {"approval": {"forbiddenApprovalGroups": []}, "session": {"maxTurns": 50, "limitWarnings": True}}'
[[ $(stat -c %a "$settings" 2>/dev/null || stat -f %Lp "$settings") == 600 ]] || fail 'mode not kept'

# Leaves a complete file untouched.
before=$(cat "$settings")
touch -d '2000-01-01' "$settings" 2>/dev/null || touch -t 200001010000 "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null
[[ $(cat "$settings") == "$before" ]] || fail 'complete file rewritten'
[[ $(find "$settings" -newermt '2001-01-01' 2>/dev/null) == '' ]] || fail 'complete file touched'

# Refuses invalid JSON, non-object sections and symlinks without changing them.
printf '%s\n' '{"session": 1}' > "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null 2>&1 && fail 'non-object session accepted'
[[ $(cat "$settings") == '{"session": 1}' ]] || fail 'non-object session changed'
printf '%s\n' '{' > "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null 2>&1 && fail 'invalid JSON accepted'
[[ $(cat "$settings") == '{' ]] || fail 'invalid JSON changed'
printf '%s\n' '{}' > "$tmp/target.json"
rm "$settings" && ln -s "$tmp/target.json" "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null 2>&1 && fail 'symlink accepted'
[[ $(cat "$tmp/target.json") == '{}' ]] || fail 'symlink target changed'

echo 'PASS: install-bob-settings'
