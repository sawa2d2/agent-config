#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" CODEX_HOME="$tmp/config" PATH="$tmp/bin:$PATH" STATE="$tmp/state"
mkdir -p "$HOME" "$CODEX_HOME" "$tmp/bin" "$STATE"
printf 'Implement the task\n' > "$tmp/prompt"
cat > "$tmp/bin/codex" <<'PY'
#!/usr/bin/env python3
import os, pathlib, sys, time
s = pathlib.Path(os.environ['STATE'])
assert sys.argv[1:] == ['exec', '-'], sys.argv
assert 'Implement the task' in sys.stdin.read()
n = int((s / 'calls').read_text()) + 1 if (s / 'calls').exists() else 1
(s / 'calls').write_text(str(n))
if (s / 'block').exists():
    (s / 'pid').write_text(str(os.getpid()))
    time.sleep(30)
if (s / 'error').exists():
    sys.exit(7)
PY
cat > "$tmp/check" <<'SH'
#!/usr/bin/env bash
[[ $(cat "$STATE/calls") -ge 2 ]]
SH
chmod +x "$tmp/bin/codex" "$tmp/check"
run() { python3 "$root/bin/codex-ralph" --prompt-file "$tmp/prompt" --max-iterations "$1" --check "$tmp/check"; }
run 3
[[ $(cat "$STATE/calls") == 2 ]]
rm "$STATE/calls"
status=0
run 1 || status=$?
[[ $status == 1 && $(cat "$STATE/calls") == 1 ]]
rm "$STATE/calls"
touch "$STATE/error"
status=0
run 3 || status=$?
[[ $status == 7 && $(cat "$STATE/calls") == 1 ]]
rm "$STATE/error" "$STATE/calls"
for limit in 0 -1 bogus; do
  if run "$limit"; then exit 1; fi
  [[ ! -e "$STATE/calls" ]]
done
# Unexpected checker errors stop immediately.
printf '#!/bin/sh\nexit 9\n' > "$tmp/check"
status=0
run 3 || status=$?
[[ $status == 9 && $(cat "$STATE/calls") == 1 ]]
rm "$STATE/calls"
# Both signals cancel the active CLI and prevent subsequent iterations.
for sig in TERM INT; do
  rm -f "$STATE/calls" "$STATE/pid"
  touch "$STATE/block"
  python3 "$root/bin/codex-ralph" --prompt-file "$tmp/prompt" --max-iterations 3 --check "$tmp/check" &
  runner=$!
  for ((i=0; i<100; i++)); do
    [[ -e "$STATE/pid" ]] && break
    sleep 0.02
  done
  [[ -e "$STATE/pid" ]]
  child=$(cat "$STATE/pid")
  kill -"$sig" "$runner"
  status=0
  wait "$runner" || status=$?
  expected=143
  [[ $sig == INT ]] && expected=130
  [[ $status == "$expected" && $(cat "$STATE/calls") == 1 ]]
  ! kill -0 "$child" 2>/dev/null
done
# Run the actual installer in an isolated fixture; external installers are stubs.
fixture="$tmp/repo"
mkdir -p "$fixture/deploy/skills" "$fixture/scripts" "$fixture/bin"
cp "$root/install" "$fixture/install"
cp -R "$root/deploy/operations" "$fixture/deploy/"
cp -R "$root/deploy/codex" "$fixture/deploy/"
printf 'fixture instructions\n' > "$fixture/deploy/AGENTS.md"
cp "$root/bin/codex-ralph" "$fixture/bin/"
for name in install-rtk install-claude-settings install-bob-theme install-codex-theme install-codex-compaction install-codex-subagent-model install-bob-settings install-agent-hooks install-tools install-nix-tools install-claude-plugins; do
  printf '#!/bin/sh\nexit 0\n' > "$fixture/scripts/$name"
done
bash "$fixture/install" >/dev/null
[[ $(readlink "$HOME/.local/bin/codex-ralph") == "$fixture/bin/codex-ralph" ]]
bash "$fixture/install" >/dev/null
rm "$HOME/.local/bin/codex-ralph"
printf 'user file\n' > "$HOME/.local/bin/codex-ralph"
if bash "$fixture/install" >/dev/null 2>&1; then exit 1; fi
[[ $(cat "$HOME/.local/bin/codex-ralph") == 'user file' ]]
