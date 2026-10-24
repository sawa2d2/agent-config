#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/real"
# Wrappers refresh themes under HOME; keep the real home untouched.
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"

# Fake CLIs record their argv and the PATH they were launched with.
for cli in bob claude codex; do
  cat > "$tmp/real/$cli" <<'CLI'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_ROOT/args"
printf '%s\n' "$PATH" > "$TEST_ROOT/path"
CLI
  chmod +x "$tmp/real/$cli"
done
export TEST_ROOT="$tmp"
export PATH="$root/bin:$tmp/real:/usr/bin:/bin"

fail() { echo "FAIL: $*" >&2; exit 1; }

expect() {
  local expected=$1
  shift
  "$@"
  [[ "$(cat "$tmp/args")" == "$expected" ]] || fail "$* passed: $(tr '\n' ' ' < "$tmp/args")"
  case ":$(cat "$tmp/path"):" in
    *":$root/bin:"*) fail "$*: wrapper was visible to the original CLI" ;;
  esac
}

# Without arguments, resume the latest session in the current directory.
expect $'chat\n--resume\nlatest\n--auto-approve' bob
# Claude continues only when this directory has a session; otherwise it starts a new one.
mkdir -p "$tmp/work.dir"
cd "$tmp/work.dir"
expect '' claude
project="$HOME/.claude/projects/$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$project"
expect '' claude
touch "$project/session.jsonl"
expect '--continue' claude
cd "$root"
[[ -f "$HOME/.bob/theme.json" ]] || fail 'bob: theme was not refreshed'
[[ -f "$HOME/.bob/settings/settings.json" ]] || fail 'bob: settings were not added'
expect $'resume\n--last' codex

# Explicit arguments are passed through unchanged.
expect $'chat\n--auto-approve' bob chat --auto-approve
expect $'--resume\ntwo words\n-p' claude --resume 'two words' -p
expect $'exec\ntwo words' codex exec 'two words'

# Pickers use the native resume commands.
expect '--resume' claudel
expect $'resume' codexl
expect $'resume\n--all' codexla

# Without the original CLI, fail instead of recursing.
export PATH="$root/bin:/usr/bin:/bin"
for cli in bob claude codex; do
  status=0
  "$cli" 2> /dev/null || status=$?
  [[ $status -eq 127 ]] || fail "$cli: expected exit 127, got $status"
done

echo 'PASS: Bob, Claude and Codex wrappers resume by default and pass arguments through'
