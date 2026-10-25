#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$tmp/bin" "$tmp/state"

# Fake claude keeps marketplaces and plugins in files and logs changing calls.
cat > "$tmp/bin/claude" <<'CLAUDE'
#!/usr/bin/env bash
state=$TEST_STATE
case "$1 $2 ${3:-}" in
  'plugin marketplace list') touch "$state/marketplaces"; cat "$state/marketplaces" ;;
  'plugin marketplace add') echo "$4" >> "$state/marketplaces"; echo "marketplace add $4" >> "$state/log" ;;
  'plugin list '*) touch "$state/plugins"; sed 's/^/  ❯ /' "$state/plugins" ;;
  'plugin install '*) echo "$3" >> "$state/plugins"; echo "install $3 $4 $5" >> "$state/log" ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
CLAUDE
printf '#!/bin/sh\n' > "$tmp/bin/pyright-langserver"
chmod +x "$tmp/bin/claude" "$tmp/bin/pyright-langserver"
export TEST_STATE="$tmp/state"
run() { PATH="$tmp/bin:/usr/bin:/bin" bash "$root/scripts/install-claude-plugins"; }

# New machine: adds the marketplace and every plugin at user scope.
run > /dev/null
[[ $(cat "$tmp/state/log") == "marketplace add anthropics/claude-plugins-official
install superpowers@claude-plugins-official --scope user
install ralph-loop@claude-plugins-official --scope user
install pyright-lsp@claude-plugins-official --scope user" ]] || fail "first run: $(cat "$tmp/state/log")"

# Re-running changes nothing.
: > "$tmp/state/log"
out=$(run 2>&1)
[[ ! -s "$tmp/state/log" ]] || fail "second run changed state: $(cat "$tmp/state/log")"
[[ $out == *'Already installed: pyright-lsp'* && $out != *WARNING* ]] || fail "second run output: $out"

# A manually installed plugin (as for pyright-lsp) is kept; only missing ones are added.
printf '%s\n' 'pyright-lsp@claude-plugins-official' > "$tmp/state/plugins"
run > /dev/null
[[ $(grep -c pyright-lsp "$tmp/state/plugins") -eq 1 ]] || fail 'pyright-lsp installed twice'
[[ $(tail -1 "$tmp/state/log") == 'install ralph-loop@claude-plugins-official --scope user' ]] || fail "partial run: $(cat "$tmp/state/log")"

# Missing language server: still installs, with a warning.
rm "$tmp/bin/pyright-langserver"
out=$(run 2>&1)
[[ $out == *'WARNING: pyright-langserver not found'* ]] || fail "no language server warning: $out"

# Without the claude CLI: warn and succeed without changes.
rm "$tmp/bin/claude"
out=$(run 2>&1) || fail 'missing claude failed'
[[ $out == *'WARNING: Claude CLI not found'* ]] || fail "missing claude output: $out"

echo 'PASS: install-claude-plugins'
