#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
unset CODEX_HOME
fail() { echo "FAIL: $*" >&2; exit 1; }
install_skill() { bash "$root/scripts/install-skill" "$@"; }

# Repository skills have frontmatter whose name matches the directory and fits Bob's name rules.
for skill in "$root"/deploy/skills/*/; do
  skill=${skill%/}
  python3 - "$skill" <<'PY' || fail "frontmatter: $skill"
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = (path / "SKILL.md").read_text()
match = re.match(r"---\n(.*?)\n---\n", text, re.S)
assert match, "missing frontmatter"
fields = dict(line.split(": ", 1) for line in match.group(1).splitlines())
assert fields["name"] == path.name and re.fullmatch(r"[a-z0-9-]{1,64}", fields["name"]), fields
assert fields.get("description"), fields
PY
done

# Defaults to the Bob, Claude Code and Codex skill directories and marks copies as managed.
mkdir -p "$tmp/src/demo/ref"
printf -- '---\nname: demo\ndescription: d\n---\nv1\n' > "$tmp/src/demo/SKILL.md"
echo r > "$tmp/src/demo/ref/a.md"
install_skill "$tmp/src/demo" demo > /dev/null
[[ ! -e "$HOME/.codex/skills/demo/agents/openai.yaml" ]] || fail 'implicit skill restricted'
for target in .bob .claude .codex; do
  dest="$HOME/$target/skills/demo"
  [[ -f "$dest/.agent-config-managed" && -f "$dest/ref/a.md" ]] || fail "not installed: $dest"
done

# Replaces managed copies, dropping removed files; explicit targets limit the destinations.
printf -- '---\nname: demo\ndescription: d\n---\nv2\n' > "$tmp/src/demo/SKILL.md"
rm "$tmp/src/demo/ref/a.md"
install_skill "$tmp/src/demo" demo "$tmp/only" > /dev/null
[[ $(tail -1 "$tmp/only/demo/SKILL.md") == v2 ]] || fail 'explicit target not installed'
[[ $(tail -1 "$HOME/.bob/skills/demo/SKILL.md") == v1 ]] || fail 'default target changed by explicit target'
install_skill "$tmp/src/demo" demo > /dev/null
[[ $(tail -1 "$HOME/.claude/skills/demo/SKILL.md") == v2 && ! -e "$HOME/.claude/skills/demo/ref/a.md" ]] || fail 'managed copy not replaced'

# Refuses unmanaged skills and sources without SKILL.md, leaving them unchanged.
mkdir -p "$tmp/user/demo" && echo mine > "$tmp/user/demo/SKILL.md"
install_skill "$tmp/src/demo" demo "$tmp/user" > /dev/null 2>&1 && fail 'unmanaged skill overwritten'
[[ $(cat "$tmp/user/demo/SKILL.md") == mine ]] || fail 'unmanaged skill changed'
mkdir -p "$tmp/src/empty"
install_skill "$tmp/src/empty" empty "$tmp/only" > /dev/null 2>&1 && fail 'source without SKILL.md accepted'
[[ ! -e "$tmp/only/empty" ]] || fail 'source without SKILL.md installed'

# Translate explicit-only policy for Codex without changing Claude/Bob or source metadata.
printf -- '---\nname: demo\ndescription: d\ndisable-model-invocation: true\n---\nbody\n' > "$tmp/src/demo/SKILL.md"
install_skill "$tmp/src/demo" demo > /dev/null
[[ -f "$HOME/.codex/skills/demo/agents/openai.yaml" ]] || fail 'Codex policy missing'
[[ $(cat "$HOME/.codex/skills/demo/agents/openai.yaml") == $'policy:\n  allow_implicit_invocation: false' ]] || fail 'Codex policy incorrect'
[[ ! -e "$HOME/.claude/skills/demo/agents/openai.yaml" && ! -e "$tmp/src/demo/agents/openai.yaml" ]] || fail 'policy leaked'
mkdir -p "$tmp/src/demo/agents"
printf 'policy:\n  allow_implicit_invocation: true\n' > "$tmp/src/demo/agents/openai.yaml"
install_skill "$tmp/src/demo" demo > /dev/null
cmp "$tmp/src/demo/agents/openai.yaml" "$HOME/.codex/skills/demo/agents/openai.yaml" || fail 'explicit metadata changed'

# Custom Codex homes receive the same policy; body examples are not frontmatter.
export CODEX_HOME="$tmp/custom-codex"
install_skill "$tmp/src/demo" demo > /dev/null
cmp "$tmp/src/demo/agents/openai.yaml" "$CODEX_HOME/skills/demo/agents/openai.yaml" || fail 'custom home ignored'
mkdir -p "$tmp/src/explicit"
printf -- '---\nname: explicit\ndescription: d\ndisable-model-invocation: true\n---\nbody\n' > "$tmp/src/explicit/SKILL.md"
install_skill "$tmp/src/explicit" explicit > /dev/null
[[ $(cat "$CODEX_HOME/skills/explicit/agents/openai.yaml") == $'policy:\n  allow_implicit_invocation: false' ]] || fail 'custom home policy missing'
mkdir -p "$tmp/src/body"
printf -- '---\nname: body\ndescription: d\n---\ndisable-model-invocation: true\n' > "$tmp/src/body/SKILL.md"
install_skill "$tmp/src/body" body > /dev/null
[[ ! -e "$CODEX_HOME/skills/body/agents/openai.yaml" ]] || fail 'body treated as frontmatter'
echo 'PASS: install-skill'
