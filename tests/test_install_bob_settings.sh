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
check 'd == {"session": {"limitWarnings": True, "respectGitIgnore": True, "compactionThresholdPercent": 37, "maxCost": 20}, "approval": {"outsideWorkspaceAllowed": True, "permissionOptions": [{"groupId": "read", "enableOutsideWorkspace": True}]}}'

# Keeps unrelated settings and values the user set; adds only missing keys.
printf '%s\n' '{"approval": {"forbiddenApprovalGroups": []}, "session": {"maxTurns": 50, "respectGitIgnore": false, "compactionThresholdPercent": 90}}' > "$settings"
chmod 600 "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null
check 'd == {"approval": {"forbiddenApprovalGroups": [], "outsideWorkspaceAllowed": True, "permissionOptions": [{"groupId": "read", "enableOutsideWorkspace": True}]}, "session": {"maxTurns": 50, "respectGitIgnore": False, "compactionThresholdPercent": 90, "limitWarnings": True, "maxCost": 20}}'
[[ $(stat -c %a "$settings" 2>/dev/null || stat -f %Lp "$settings") == 600 ]] || fail 'mode not kept'

# The 300-turn limit of earlier installs goes back to Bob's default.
printf '%s\n' '{"session": {"maxTurns": 300}}' > "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null
check '"maxTurns" not in d["session"] and d["session"]["maxCost"] == 20'
# The earlier compaction default moves to the new one.
printf '%s\n' '{"session": {"compactionThresholdPercent": 80}}' > "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null
check 'd["session"]["compactionThresholdPercent"] == 37'
printf '%s\n' '{"approval": {"forbiddenApprovalGroups": []}, "session": {"maxTurns": 50, "respectGitIgnore": false, "compactionThresholdPercent": 90}}' > "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null

# A user's outside-workspace choices, including a read group entry, are kept.
printf '%s\n' '{"approval": {"outsideWorkspaceAllowed": false, "permissionOptions": [{"groupId": "read", "enableOutsideWorkspace": false}]}}' > "$tmp/own.json"
cp "$settings" "$tmp/kept.json"; cp "$tmp/own.json" "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null
check 'd["approval"] == {"outsideWorkspaceAllowed": False, "permissionOptions": [{"groupId": "read", "enableOutsideWorkspace": False}]}'
cp "$tmp/kept.json" "$settings"

# Leaves a complete file untouched.
before=$(cat "$settings")
touch -d '2000-01-01' "$settings" 2>/dev/null || touch -t 200001010000 "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null
[[ $(cat "$settings") == "$before" ]] || fail 'complete file rewritten'
[[ $(find "$settings" -newermt '2001-01-01' 2>/dev/null) == '' ]] || fail 'complete file touched'

# Refuses invalid JSON and non-object sections without changing them.
printf '%s\n' '{"session": 1}' > "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null 2>&1 && fail 'non-object session accepted'
[[ $(cat "$settings") == '{"session": 1}' ]] || fail 'non-object session changed'
printf '%s\n' '{' > "$settings"
bash "$root/scripts/install-bob-settings" > /dev/null 2>&1 && fail 'invalid JSON accepted'
[[ $(cat "$settings") == '{' ]] || fail 'invalid JSON changed'
printf '%s\n' '{}' > "$tmp/target.json"
rm "$settings" && ln -s "$tmp/target.json" "$settings"
# A symlinked settings file (kept in a dotfiles checkout, say) is updated through the link.
bash "$root/scripts/install-bob-settings" > /dev/null || fail 'symlink refused'
[[ -L $settings ]] || fail 'symlink replaced'
grep -q '"maxCost": 20' "$tmp/target.json" || fail "symlink target not updated: $(cat "$tmp/target.json")"

echo 'PASS: install-bob-settings'
