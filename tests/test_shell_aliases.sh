#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
# Launchers refresh managed settings; keep the real ones intact.
export HOME="$tmp/home"
export CODEX_HOME="$HOME/.codex"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$tmp/real" "$tmp/cwd" "$HOME"

# Fake CLI placed before agent-config on PATH, as nvm or Nix would.
cat > "$tmp/real/bob" <<'BOB'
#!/usr/bin/env bash
printf '%s\n' "$*"
BOB
chmod +x "$tmp/real/bob"
cat > "$tmp/real/codex" <<'CODEX'
#!/usr/bin/env bash
printf 'underlying-codex: %s\n' "$*"
CODEX
chmod +x "$tmp/real/codex"
# Model the standalone installer's public symlink, ahead of the wrapper.
mkdir -p "$tmp/local/bin"
ln -s "$tmp/real/codex" "$tmp/local/bin/codex"

fail() { echo "FAIL: $*" >&2; exit 1; }

check() {
  local shell=$1 setup=$2 output
  # Use a script file: zsh -c parses the whole string before aliases exist.
  cat > "$tmp/run.$shell" <<SCRIPT
$setup
source '$root/shell/aliases.sh'
PATH='$tmp/local/bin:$tmp/real:$root/bin':\$PATH
alias claude
alias codexla
bob
codex
codex new
codex exec 'two words'
# An installer update can replace its own link without replacing the alias.
rm '$tmp/local/bin/codex'
ln -s '$tmp/real/codex' '$tmp/local/bin/codex'
codex
SCRIPT
  # Source from another directory, then let PATH change afterwards.
  output=$(cd "$tmp/cwd" && PATH="/usr/bin:/bin" "$shell" "$tmp/run.$shell")
  [[ "$output" == *"$root/bin/claude"* ]] || fail "$shell: claude alias missing: $output"
  [[ "$output" == *"$root/bin/codexla"* ]] || fail "$shell: codexla alias missing: $output"
  [[ "$output" == *'chat --auto-approve --resume latest'* ]] || fail "$shell: bob did not use the launcher: $output"
  local resume='underlying-codex: --no-alt-screen --approve-for-me -c features.worktrees=false resume --last'
  [[ $(printf '%s\n' "$output" | grep -Fxc -- "$resume") == 2 ]] || fail "$shell: Codex resume routing failed: $output"
  [[ "$output" == *$'underlying-codex: --no-alt-screen --approve-for-me\n'* ]] || fail "$shell: Codex new routing failed: $output"
  [[ "$output" == *'underlying-codex: --no-alt-screen --approve-for-me exec two words'* ]] || fail "$shell: Codex arguments lost: $output"
}

check bash 'shopt -s expand_aliases'
if command -v zsh > /dev/null 2>&1; then
  check zsh ''
else
  echo 'SKIP: zsh not installed'
fi

echo 'PASS: shell aliases bind launchers regardless of later PATH changes'
