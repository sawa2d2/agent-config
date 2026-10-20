#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/real" "$tmp/cwd"

# Fake CLI placed before agent-config on PATH, as nvm or Nix would.
cat > "$tmp/real/bob" <<'BOB'
#!/usr/bin/env bash
printf '%s\n' "$*"
BOB
chmod +x "$tmp/real/bob"

fail() { echo "FAIL: $*" >&2; exit 1; }

check() {
  local shell=$1 setup=$2 output
  # Use a script file: zsh -c parses the whole string before aliases exist.
  cat > "$tmp/run.$shell" <<SCRIPT
$setup
source '$root/shell/aliases.sh'
PATH='$tmp/real':\$PATH
alias claude
alias codexla
bob
SCRIPT
  # Source from another directory, then let PATH change afterwards.
  output=$(cd "$tmp/cwd" && PATH="/usr/bin:/bin" "$shell" "$tmp/run.$shell")
  [[ "$output" == *"$root/bin/claude"* ]] || fail "$shell: claude alias missing: $output"
  [[ "$output" == *"$root/bin/codexla"* ]] || fail "$shell: codexla alias missing: $output"
  [[ "$output" == *'chat --resume latest'* ]] || fail "$shell: bob did not use the launcher: $output"
}

check bash 'shopt -s expand_aliases'
if command -v zsh > /dev/null 2>&1; then
  check zsh ''
else
  echo 'SKIP: zsh not installed'
fi

echo 'PASS: shell aliases bind launchers regardless of later PATH changes'
