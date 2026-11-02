#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake curl serves a local archive and logs the URL; fake uname reports $TEST_UNAME.
mkdir -p "$tmp/bin" "$tmp/pkg" "$tmp/other" "$tmp/brew-bin"
printf '#!/bin/sh\necho fake rtk\n' > "$tmp/pkg/rtk" && chmod +x "$tmp/pkg/rtk"
tar -czf "$tmp/rtk.tar.gz" -C "$tmp/pkg" rtk
cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
echo "${*: -1}" >> "$TEST_LOG"
while [[ $1 != -o ]]; do shift; done
cp "$TEST_ARCHIVE" "$2"
CURL
cat > "$tmp/bin/uname" <<'UNAME'
#!/usr/bin/env bash
case $1 in -s) echo "${TEST_UNAME% *}" ;; -m) echo "${TEST_UNAME#* }" ;; esac
UNAME
chmod +x "$tmp/bin/curl" "$tmp/bin/uname"
export TEST_LOG="$tmp/log" TEST_ARCHIVE="$tmp/rtk.tar.gz"
run() { PATH="$tmp/bin:$1:/usr/bin:/bin" bash "$root/scripts/install-rtk"; }

# An rtk already on PATH is kept and nothing is downloaded.
cp "$tmp/pkg/rtk" "$tmp/other/rtk"
out=$(TEST_UNAME='Linux x86_64' run "$tmp/other")
[[ $out == "Already installed: $tmp/other/rtk" && ! -e $TEST_LOG ]] || fail "existing rtk: $out"

# The pinned release of the platform's rtk-oss build is downloaded; a checksum
# mismatch installs nothing.
TEST_UNAME='Linux x86_64' run "$tmp/empty" > /dev/null 2> "$tmp/err" && fail 'checksum mismatch accepted'
[[ $(cat "$TEST_LOG") == https://github.com/rtk-ai/rtk/releases/download/v*/rtk-oss-x86_64-unknown-linux-musl.tar.gz ]] \
  || fail "download URL: $(cat "$TEST_LOG")"
grep -q 'checksum mismatch' "$tmp/err" || fail "mismatch message: $(cat "$tmp/err")"
[[ ! -e $HOME/.local/bin/rtk ]] || fail 'rtk installed despite checksum mismatch'
: > "$TEST_LOG"
TEST_UNAME='Darwin arm64' run "$tmp/empty" > /dev/null 2>&1 && fail 'checksum mismatch accepted'
[[ $(cat "$TEST_LOG") == */rtk-oss-aarch64-apple-darwin.tar.gz ]] || fail "macOS download URL: $(cat "$TEST_LOG")"

# On macOS, Homebrew installs the tap's rtk-oss formula instead of the release.
: > "$TEST_LOG"
cat > "$tmp/brew-bin/brew" <<'BREW'
#!/usr/bin/env bash
echo "brew $*" >> "$TEST_LOG"
BREW
chmod +x "$tmp/brew-bin/brew"
TEST_UNAME='Darwin arm64' run "$tmp/brew-bin" > /dev/null || fail 'brew install failed'
[[ $(cat "$TEST_LOG") == 'brew install rtk-ai/tap/rtk-oss' ]] || fail "brew: $(cat "$TEST_LOG")"
# Linux ignores Homebrew and keeps the release download.
: > "$TEST_LOG"
TEST_UNAME='Linux x86_64' run "$tmp/brew-bin" > /dev/null 2>&1 && fail 'checksum mismatch accepted'
[[ $(cat "$TEST_LOG") == https://github.com/* ]] || fail "Linux with brew: $(cat "$TEST_LOG")"

# Platforms without a build are skipped with a warning.
: > "$TEST_LOG"
out=$(TEST_UNAME='Linux riscv64' run "$tmp/empty" 2>&1) || fail 'unsupported platform failed'
[[ $out == *'no rtk build for Linux riscv64'* && ! -s $TEST_LOG ]] || fail "unsupported platform: $out"

echo 'PASS: install-rtk'
