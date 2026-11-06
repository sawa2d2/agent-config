#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

# All settings writes are isolated, including symlink targets and launch hooks.
env HOME="$tmp/home" CODEX_HOME="$tmp/codex" XDG_CONFIG_HOME="$tmp/config" python3 - "$root" "$tmp" <<'PY'
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

root, tmp = map(Path, sys.argv[1:])
config = Path(os.environ['CODEX_HOME']) / 'config.toml'
def install_codex():
    subprocess.run(['bash', str(root / 'scripts/install-codex-theme')], check=True, stdout=subprocess.DEVNULL)
install_codex()
assert '"used-tokens"' in config.read_text()
for custom in ('["git-branch"]', '[]'):
    config.write_text('[tui]\nstatus_line = ' + custom + '\n')
    install_codex()
    assert 'status_line = ' + custom in config.read_text()
    assert 'used-tokens' not in config.read_text()

transcript = tmp / 'session.jsonl'
def record(key, output, **extra):
    return dict(type='assistant', requestId=key, message=dict(id=key, usage=dict(
        input_tokens=10, cache_creation_input_tokens=100,
        cache_read_input_tokens=1000, output_tokens=output)), **extra)
records = [record('a', 2), record('a', 20), record('a', 20),
           dict(type='system', subtype='compact_boundary'), record('b', 30),
           record('child', 999, isSidechain=True)]
transcript.write_text(''.join(json.dumps(row) + '\n' for row in records) + '{"type":')
payload = dict(transcript_path=str(transcript), model=dict(display_name='Opus'),
               context_window=dict(total_input_tokens=99999, total_output_tokens=99999, used_percentage=12))
def render():
    return subprocess.run(['python3', str(root / 'scripts/claude-session-status')],
                          input=json.dumps(payload), text=True, capture_output=True, check=True)
expected = 'Session tokens: 2,270\n'
assert render().stdout == expected
assert render().stdout == expected  # polling/resume never accumulates twice
fallback = record('c', 5)
del fallback['requestId']
transcript.write_text(json.dumps(fallback) + '\n' + json.dumps(fallback) + '\n')
assert 'Session tokens: 1,115' in render().stdout
transcript.write_text('')
payload['context_window']['used_percentage'] = None
assert 'Session tokens: 0' in render().stdout
transcript.unlink()
assert 'unavailable' in render().stdout and render().stderr
transcript.write_text('not json\n')
assert 'unavailable' in render().stdout

settings = Path(os.environ['HOME']) / '.claude/settings.json'
def install_claude():
    subprocess.run(['bash', str(root / 'scripts/install-claude-settings')], check=True, stdout=subprocess.DEVNULL)
install_claude()
data = json.loads(settings.read_text())
assert shlex.split(data['statusLine']['command']) == ['python3', str(root / 'scripts/claude-session-status')]
custom = dict(type='command', command='echo my existing info', padding=2)
data['statusLine'] = custom
settings.write_text(json.dumps(data))
install_claude()
assert json.loads(settings.read_text())['statusLine'] == custom
PY
echo 'PASS: native session token status, accounting, preservation, and isolated installation'
