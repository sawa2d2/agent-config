#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CODEX_HOME="$tmp/codex-config" XDG_CONFIG_HOME="$tmp/config"
mkdir -p "$tmp/bin" "$CODEX_HOME"
export PATH="$tmp/bin:/usr/bin:/bin"
fail() { echo "FAIL: $*" >&2; exit 1; }
cat > "$tmp/bin/codex" <<'CLI'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CODEX_HOME/argv"
# Hooks must already be refreshed when the underlying CLI starts.
python3 - "$CODEX_HOME/hooks.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if p.exists():
    assert '/old/scripts/codex-rtk-hook' not in p.read_text()
PY
CLI
chmod +x "$tmp/bin/codex"
launch() { bash "$root/bin/codex" "$@"; }

# No installed RTK and no previous hooks: do not create hooks.json.
launch new
[[ ! -e $CODEX_HOME/hooks.json ]] || fail 'created hooks without rtk'
printf '#!/bin/sh\n' > "$tmp/bin/rtk"
chmod +x "$tmp/bin/rtk"
cat > "$CODEX_HOME/hooks.json" <<'JSON'
{"description":"user metadata","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/old/scripts/codex-rtk-hook"},{"type":"command","command":"echo user","timeout":7}]}],"Stop":[{"hooks":[{"type":"command","command":"echo done"}]}]}}
JSON
launch new --sandbox read-only
python3 - "$CODEX_HOME/hooks.json" "$root" <<'PY'
import json, sys
p, root = sys.argv[1:]
d = json.load(open(p))
assert d['description'] == 'user metadata'
assert d['hooks']['Stop'] == [{'hooks': [{'type': 'command', 'command': 'echo done'}]}]
assert d['hooks']['PreToolUse'] == [
    {'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': 'echo user', 'timeout': 7}]},
    {'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': root + '/scripts/codex-rtk-hook'}]}]
PY
[[ $(cat "$CODEX_HOME/argv") == $'--sandbox\nread-only' ]] || fail 'explicit sandbox changed'
# Atomic rewrites replace the inode: verify both bytes and file identity stay stable.
cp "$CODEX_HOME/hooks.json" "$tmp/before.json"
file_identity() { python3 -c 'import os, sys; s = os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns)' "$CODEX_HOME/hooks.json"; }
identity=$(file_identity)
launch new -a on-request
cmp -s "$CODEX_HOME/hooks.json" "$tmp/before.json" || fail 'unchanged definitions rewritten'
[[ $(file_identity) == "$identity" ]] || fail 'unchanged file replaced'
[[ $(cat "$CODEX_HOME/argv") == $'-a\non-request' ]] || fail 'explicit approval changed'
rm "$tmp/bin/rtk"
launch
python3 - "$CODEX_HOME/hooks.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d['hooks']['PreToolUse'] == [{'matcher': 'Bash', 'hooks': [{'type': 'command', 'command': 'echo user', 'timeout': 7}]}]
assert d['description'] == 'user metadata'
PY
[[ $(cat "$CODEX_HOME/argv") == $'--approve-for-me\nresume\n--last' ]] || fail 'default launch changed'

# Malformed configuration must fail visibly before starting the CLI.
printf '{invalid\n' > "$CODEX_HOME/hooks.json"
rm "$CODEX_HOME/argv"
if launch new > "$tmp/out" 2> "$tmp/error"; then fail 'invalid hooks accepted'; fi
[[ -s $tmp/error && ! -e $CODEX_HOME/argv ]] || fail 'refresh error hidden'
[[ $(cat "$CODEX_HOME/hooks.json") == '{invalid' ]] || fail 'invalid hooks overwritten'
echo 'PASS: Codex startup refreshes hooks safely'
