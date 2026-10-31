#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake rtk answers "rtk hook codex" with a marker holding the command it was given.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/rtk" <<'RTK'
#!/usr/bin/env bash
[[ "$*" == 'hook codex' ]] || exit 1
python3 -c 'import json, sys; print("REWRITE " + json.load(sys.stdin)["tool_input"]["command"])'
RTK
chmod +x "$tmp/bin/rtk"
hook() {
  python3 -c 'import json, sys; print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))' "$1" \
    | PATH="$tmp/bin:$PATH" "$root/scripts/codex-rtk-hook"
}

# Single read-only commands go to rtk.
for command in 'git status' 'git diff HEAD~1' 'git log -5' 'git show HEAD' 'ls -la' 'grep -rn "a b" .' 'rg foo' \
  'cat README.md' 'head -5 x' 'tail x' 'wc -l x' 'find . -name "*.sh"'; do
  [[ $(hook "$command") == "REWRITE $command" ]] || fail "not rewritten: $command"
done

# Anything that could change state, chain commands or run programs keeps Codex's approval.
for command in 'git push' 'git branch -D x' 'git -c core.pager=x log' 'rm -rf x' 'bash tests/x.sh' \
  'git status && rm -rf x' 'git status; rm x' 'cat x | sh' 'cat a > b' 'cat $(x)' 'cat `x`' $'ls\nrm x' \
  'find . -delete' 'find . -exec rm {} +' 'git diff --output=x' 'git diff --ext-diff' 'rg --pre=x foo' \
  'grep "unterminated' ''; do
  [[ -z $(hook "$command") ]] || fail "rewritten: $command"
done

# Malformed input is ignored.
[[ -z $(echo '{' | PATH="$tmp/bin:$PATH" "$root/scripts/codex-rtk-hook") ]] || fail 'malformed input rewritten'
[[ -z $(echo '{"tool_input": {"command": 1}}' | PATH="$tmp/bin:$PATH" "$root/scripts/codex-rtk-hook") ]] \
  || fail 'non-string command rewritten'

echo 'PASS: codex-rtk-hook'
