#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/real"

cat > "$tmp/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
out=
while (($#)); do
  if [[ $1 == -o ]]; then out=$2; shift 2; else shift; fi
done
[[ -n $out ]]
cat > "$out" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$PATH" > "$TEST_ROOT/installer-path"
command -v bob > "$TEST_ROOT/installer-bob" || true
touch "$TEST_ROOT/installed"
INSTALLER
CURL
chmod +x "$tmp/bin/curl"

# The only Bob is agent-config's wrapper; installation must not be skipped.
export TEST_ROOT="$tmp"
export PATH="$root/bin:$tmp/bin:/usr/bin:/bin"
bash "$root/scripts/install-bob-shell"
[[ -f "$tmp/installed" ]]
[[ ! -s "$tmp/installer-bob" ]]
case ":$(cat "$tmp/installer-path"):" in
  *":$root/bin:"*) echo 'FAIL: wrapper was visible to installer' >&2; exit 1 ;;
esac

# With a real Bob executable, installation must be skipped.
cat > "$tmp/real/bob" <<'BOB'
#!/usr/bin/env bash
exit 0
BOB
chmod +x "$tmp/real/bob"
rm -f "$tmp/installed"
export PATH="$root/bin:$tmp/real:$tmp/bin:/usr/bin:/bin"
bash "$root/scripts/install-bob-shell"
[[ ! -f "$tmp/installed" ]]

echo 'PASS: wrapper ignored, installer called, real Bob detected'
