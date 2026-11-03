#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
# An existing checkout skips the clone, so no network is needed.
upstream="$HOME/.local/share/agent-config/ralph"
for name in prd ralph; do
  mkdir -p "$upstream/skills/$name"
  printf -- '---\nname: %s\ndescription: d\nuser-invocable: true\n---\n\n# Body\n---\n' "$name" \
    > "$upstream/skills/$name/SKILL.md"
done
# An explicit upstream choice is kept.
sed -i 's/^user-invocable: true$/&\ndisable-model-invocation: false/' "$upstream/skills/prd/SKILL.md"

bash "$root/scripts/install-bob-ralph" > /dev/null
ralph="$HOME/.bob/skills/ralph/SKILL.md"
[[ $(sed -n 5p "$ralph") == 'disable-model-invocation: true' ]]
[[ $(grep -c '^disable-model-invocation:' "$ralph") == 1 ]]
[[ $(grep -c '^disable-model-invocation:' "$HOME/.bob/skills/prd/SKILL.md") == 1 ]]
grep -q '^disable-model-invocation: false$' "$HOME/.bob/skills/prd/SKILL.md"
[[ -f "$HOME/.bob/skills/ralph/.agent-config-managed" ]]
# The upstream checkout is unchanged.
if grep -q '^disable-model-invocation:' "$upstream/skills/ralph/SKILL.md"; then
  echo 'FAIL: upstream skill modified' >&2
  exit 1
fi

# Re-running keeps a single flag.
bash "$root/scripts/install-bob-ralph" > /dev/null
[[ $(grep -c '^disable-model-invocation:' "$ralph") == 1 ]]

echo 'PASS: Bob Ralph skills hidden from the model, explicit choice and upstream kept'
