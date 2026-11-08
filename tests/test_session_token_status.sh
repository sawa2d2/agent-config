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
assert '"context-used", "context-window-size"' in config.read_text()
initial = config.read_bytes()
install_codex()
assert config.read_bytes() == initial
old_default = '["model-with-reasoning", "context-remaining", "current-dir", "used-tokens"]'
for custom in ('["git-branch"]', '[]', old_default):
    config.write_text('[tui]\nstatus_line = ' + custom + '\n')
    install_codex()
    assert 'status_line = ' + custom in config.read_text()
    if custom != old_default:
        assert 'used-tokens' not in config.read_text()
config.write_text('tui.status_line = []\n')
install_codex()
assert 'tui.status_line = []' in config.read_text()
assert 'context-used' not in config.read_text()

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
               context_window=dict(total_input_tokens=99999, total_output_tokens=99999, used_percentage=12,
                                   context_window_size=200000,
                                   current_usage=dict(input_tokens=1000, cache_creation_input_tokens=3000,
                                                      cache_read_input_tokens=20000, output_tokens=999)))
def render():
    return subprocess.run(['python3', str(root / 'scripts/claude-session-status')],
                          input=json.dumps(payload), text=True, capture_output=True, check=True)
expected = 'Context (last input): 24,000/200,000 tokens (12%) | Session tokens: 2,270\n'
assert render().stdout == expected
assert render().stdout == expected  # polling/resume never accumulates twice
# Compaction can reduce context while the cumulative session total stays intact.
payload['context_window']['current_usage']['cache_read_input_tokens'] = 0
assert render().stdout == 'Context (last input): 4,000/200,000 tokens (2%) | Session tokens: 2,270\n'
for usage in (None, {}):
    payload['context_window']['current_usage'] = usage
    assert render().stdout == 'Context (last input): unavailable | Session tokens: 2,270\n'
payload['context_window']['current_usage'] = dict(input_tokens=0, cache_creation_input_tokens=0,
                                                 cache_read_input_tokens=0)
assert render().stdout.startswith('Context (last input): 0/200,000 tokens (0%)')
for size in (None, 0):
    payload['context_window']['context_window_size'] = size
    assert render().stdout.startswith('Context (last input): unavailable')
payload['context_window']['context_window_size'] = 200000
fallback = record('c', 5)
del fallback['requestId']
transcript.write_text(json.dumps(fallback) + '\n' + json.dumps(fallback) + '\n')
assert 'Session tokens: 1,115' in render().stdout
transcript.write_text('')
payload['context_window']['used_percentage'] = None
assert 'Session tokens: 0' in render().stdout
transcript.unlink()
assert render().stdout == 'Context (last input): 0/200,000 tokens (0%) | Session tokens: unavailable\n'
assert render().stderr
transcript.write_text('not json\n')
assert 'Session tokens: unavailable' in render().stdout
payload.pop('context_window')
assert render().stdout.startswith('Context (last input): unavailable')

settings = Path(os.environ['HOME']) / '.claude/settings.json'
def install_claude():
    subprocess.run(['bash', str(root / 'scripts/install-claude-settings')], check=True, stdout=subprocess.DEVNULL)
install_claude()
data = json.loads(settings.read_text())
assert shlex.split(data['statusLine']['command']) == ['python3', str(root / 'scripts/claude-session-status')]
install_claude()
assert json.loads(settings.read_text()) == data
custom = dict(type='command', command='echo my existing info', padding=2)
data['statusLine'] = custom
settings.write_text(json.dumps(data))
install_claude()
assert json.loads(settings.read_text())['statusLine'] == custom
PY
echo 'PASS: context and session token status, accounting, preservation, and isolated installation'
