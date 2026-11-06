#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 "$root/tests/codex_auto_handoff_test.py"
# Explicit mode dispatch must fail safely without a terminal; normal wrapper
# behavior is covered separately by test_codex_hook_refresh.sh.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CODEX_HOME="$tmp/codex"
mkdir -p "$HOME" "$CODEX_HOME" "$tmp/bin"
printf '#!/bin/sh\nexit 99\n' > "$tmp/bin/codex"
chmod +x "$tmp/bin/codex"
if PATH="$tmp/bin:/usr/bin:/bin" bash "$root/bin/codex" auto-handoff new -s read-only > "$tmp/out" 2> "$tmp/error"; then
  echo 'FAIL: noninteractive automatic mode was accepted' >&2
  exit 1
fi
rg -q 'auto-handoff requires an interactive terminal' "$tmp/error"
