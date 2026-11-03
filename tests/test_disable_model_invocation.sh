#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
run() { bash "$root/scripts/disable-model-invocation" "$@"; }

# Adds the flag at the end of the frontmatter, once.
printf -- '---\nname: demo\ndescription: d\n---\n# Demo\n---\n' > "$tmp/SKILL.md"
run "$tmp/SKILL.md"
run "$tmp/SKILL.md"
[[ $(cat "$tmp/SKILL.md") == $'---\nname: demo\ndescription: d\ndisable-model-invocation: true\n---\n# Demo\n---' ]] ||
  fail "flag not added once: $(cat "$tmp/SKILL.md")"

# Keeps an explicit choice either way.
printf -- '---\nname: demo\ndisable-model-invocation: false\n---\n' > "$tmp/SKILL.md"
run "$tmp/SKILL.md"
[[ $(grep -c '^disable-model-invocation:' "$tmp/SKILL.md") == 1 ]] && grep -q 'invocation: false' "$tmp/SKILL.md" ||
  fail 'explicit choice changed'

# A missing file fails without creating one.
run "$tmp/missing.md" 2> /dev/null && fail 'missing file accepted'
[[ ! -e "$tmp/missing.md" && ! -e "$tmp/missing.md.new" ]] || fail 'missing file created'
echo 'PASS: disable-model-invocation'
