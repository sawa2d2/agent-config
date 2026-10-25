#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$tmp/bin" "$tmp/other"

# Fake nix lists the packages in $TEST_PROFILE (bold, as real nix does) and logs additions.
cat > "$tmp/bin/nix" <<'NIX'
#!/usr/bin/env bash
case "$1 $2" in
  'profile list') while read -r pkg; do printf 'Name:               \e[1m%s\e[0m\n' "$pkg"; done < "$TEST_PROFILE" ;;
  'profile add') echo "${*: -1}" >> "$TEST_LOG"; echo "${*: -1}" | sed 's/^nixpkgs#//' >> "$TEST_PROFILE" ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
NIX
chmod +x "$tmp/bin/nix"
export TEST_PROFILE="$tmp/profile" TEST_LOG="$tmp/log"
run() { PATH="$tmp/bin:$1:/usr/bin:/bin" bash "$root/scripts/install-nix-tools"; }

# New machine: adds the CLIs and pyright.
: > "$TEST_PROFILE"
run "$tmp/other" > /dev/null
[[ $(paste -sd, "$TEST_LOG") == 'nixpkgs#claude-code,nixpkgs#claude-agent-acp,nixpkgs#codex,nixpkgs#pyright' ]] || fail "first run: $(cat "$TEST_LOG")"

# Re-running with pyright-langserver on PATH adds nothing, despite the escape codes.
: > "$TEST_LOG"
printf '#!/bin/sh\n' > "$tmp/other/pyright-langserver" && chmod +x "$tmp/other/pyright-langserver"
out=$(run "$tmp/other")
[[ ! -s "$TEST_LOG" ]] || fail "second run added: $(cat "$TEST_LOG")"
[[ $out == *"Already installed: pyright-langserver ($tmp/other/pyright-langserver)"* ]] || fail "second run output: $out"

# pyright from elsewhere (e.g. home-manager) is reused instead of a conflicting profile entry.
printf '%s\n' claude-code claude-agent-acp codex > "$TEST_PROFILE"
run "$tmp/other" > /dev/null
[[ ! -s "$TEST_LOG" ]] || fail "existing pyright duplicated: $(cat "$TEST_LOG")"

echo 'PASS: install-nix-tools'
