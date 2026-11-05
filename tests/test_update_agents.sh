#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/repo/bin" "$tmp/repo/scripts" "$tmp/mock" "$tmp/home" "$tmp/downloads"
cp "$root"/bin/update-* "$tmp/repo/bin/"
ln -s "$tmp/repo/bin" "$tmp/alias"
export TEST_ROOT="$tmp" HOME="$tmp/home" TMPDIR="$tmp/downloads"
# An isolated PATH prevents any installed agent or network command from running.
for cmd in bash sh dirname mktemp rm env; do
  ln -s "$(command -v "$cmd")" "$tmp/mock/$cmd"
done
for tool in bob claude codex; do
  cat > "$tmp/repo/bin/$tool" <<'WRAPPER'
#!/usr/bin/env bash
printf 'wrapper invoked\n' >> "$TEST_ROOT/forbidden"
exit 99
WRAPPER
  chmod +x "$tmp/repo/bin/$tool"
done
cat > "$tmp/mock/claude" <<'CLAUDE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_ROOT/claude-args"
printf '%s\n' "$PATH" > "$TEST_ROOT/path"
exit "${MOCK_STATUS:-0}"
CLAUDE
cat > "$tmp/mock/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 4 && $1 == -fsSL && $3 == -o ]]
printf '%s\n' "$2" > "$TEST_ROOT/url"
printf '%s\n' "$4" > "$TEST_ROOT/temp-file"
# Even a failed download leaves an executable fragment: it must not run.
printf '%s\n' 'printf "ran\n" > "$TEST_ROOT/installer"' 'printf "%s\n" "$PATH" > "$TEST_ROOT/path"' 'exit "${INSTALLER_STATUS:-0}"' > "$4"
exit "${MOCK_STATUS:-0}"
CURL
chmod +x "$tmp/mock/claude" "$tmp/mock/curl"
export PATH="$tmp/repo/bin:$tmp/alias:$tmp/mock"

expect_status() {
  local expected=$1 actual=0
  shift
  "$@" > "$tmp/output" 2>&1 || actual=$?
  [[ $actual == "$expected" ]] || {
    printf 'Expected status %s, got %s: %s\n' "$expected" "$actual" "$*" >&2
    /bin/cat "$tmp/output" >&2
    exit 1
  }
}
assert_clean_path() {
  local actual
  actual=$(/bin/cat "$tmp/path")
  [[ $actual == "$tmp/mock" ]]
  [[ ! -e "$tmp/forbidden" ]]
}
for tool in bob claude codex; do
  script="$tmp/repo/bin/update-$tool"
  [[ -x $script ]]
  expect_status 0 "$script" --help
  expect_status 2 "$script" unexpected
  expect_status 2 "$script" --help extra
  [[ ! -e "$tmp/url" && ! -e "$tmp/claude-args" ]]
done

for tool in bob codex; do
  script="$tmp/repo/bin/update-$tool"
  expect_status 0 "$script"
  [[ -f "$tmp/installer" ]]
  url=$(/bin/cat "$tmp/url")
  if [[ $tool == bob ]]; then
    [[ $url == https://bob.ibm.com/download/bobshell.sh ]]
  else
    [[ $url == https://chatgpt.com/codex/install.sh ]]
  fi
  assert_clean_path
  [[ ! -e $(/bin/cat "$tmp/temp-file") ]]
  rm "$tmp/installer"
  expect_status 23 env MOCK_STATUS=23 "$script"
  [[ ! -e "$tmp/installer" && ! -e $(/bin/cat "$tmp/temp-file") ]]
  expect_status 42 env INSTALLER_STATUS=42 "$script"
  [[ ! -e $(/bin/cat "$tmp/temp-file") ]]
  rm "$tmp/installer"
done
expect_status 0 "$tmp/repo/bin/update-claude"
[[ $(/bin/cat "$tmp/claude-args") == $'install\nlatest' ]]
assert_clean_path
expect_status 37 env MOCK_STATUS=37 "$tmp/repo/bin/update-claude"
rm "$tmp/mock/claude" "$tmp/mock/curl"
for tool in bob claude codex; do
  expect_status 127 "$tmp/repo/bin/update-$tool"
done
[[ ! -e "$tmp/forbidden" ]]
[[ -z $(/bin/ls -A "$tmp/home") ]]
printf 'PASS: update commands, wrapper exclusion, usage, missing dependencies, failures and cleanup\n'
