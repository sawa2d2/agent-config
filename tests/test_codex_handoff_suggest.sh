#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CODEX_HOME="$tmp/config"
mkdir -p "$HOME" "$CODEX_HOME"

# The hook only warns about actual automatic compaction. It must never stop
# compaction, inject unsupported model context, or interpret cost/token fields.
python3 - "$root/scripts/codex-handoff-suggest" <<'PY'
import json
import subprocess
import sys

def run(payload):
    return subprocess.run([sys.executable, sys.argv[1]], input=payload,
                          text=True, capture_output=True, check=True).stdout

payload = {"session_id": "fixture", "cwd": "/fixture", "transcript_path": "",
           "hook_event_name": "PreCompact", "turn_id": "turn", "trigger": "auto"}
result = json.loads(run(json.dumps(payload)))
assert set(result) == {"systemMessage"}, result
assert "handoff" in result["systemMessage"] and ".agent-handoff.md" in result["systemMessage"] and "$takeover" in result["systemMessage"]
for change in ({"trigger": "manual"}, {"trigger": None},
               {"hook_event_name": "Stop"}, {"hook_event_name": "UserPromptSubmit"}):
    assert run(json.dumps(payload | change)) == "", change
for invalid in ("{", "null", "[]", "1", "{}"):
    assert run(invalid) == "", invalid
PY
