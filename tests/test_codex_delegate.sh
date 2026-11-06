#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
unset CODEX_HOME
mkdir -p "$HOME/.codex"
printf 'model = "test"\n' > "$HOME/.codex/config.toml"
python3 - "$root" "$tmp" <<'PY'
import concurrent.futures
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

root, base = map(Path, sys.argv[1:])
cli = str(root / 'bin/codex-delegate')
fake = base / 'fake'
fake.mkdir()
# No real Codex or tmux process is started. Real Git worktrees exercise root
# resolution, branch results and reports across linked/deleted worktrees.
stub = fake / 'stub'
stub.write_text('''#!/usr/bin/env python3
import json, os
from pathlib import Path
import subprocess, sys, uuid
base = Path(os.environ['TEST_ROOT'])
name = Path(sys.argv[0]).name
a = sys.argv[1:]
if name == 'gwt-path':
    if os.environ.get('FAIL_GWT'):
        print('fixture worktree creation failed', file=sys.stderr)
        sys.exit(1)
    assert a[0] == '-b'
    directory = base / 'worktrees with spaces' / a[1]
    subprocess.run(['git', 'worktree', 'add', '-qb', a[1], str(directory)], check=True)
    print(directory)
elif name == 'codex':
    (base / 'codex.args').write_text(json.dumps(a))
else:
    with (base / 'tmux.log').open('a') as f: f.write(json.dumps(a) + '\\n')
    if os.environ.get('FAIL_TMUX') == a[0]: sys.exit(1)
    if a[0] == 'display-message':
        if a[-1] == '#{session_id}': print('$7')
        elif a[-1] == '#{pid}': print('123')
        else:
            pane = a[a.index('-t') + 1]
            token = (base / ('pane-' + pane)).read_text()
            print(os.environ.get('SERVER', '123') + '\\t' + token + '\\t' + os.environ.get('DEAD', '0'))
    elif a[0] == 'new-window': print('%' + uuid.uuid4().hex)
    elif a[0] == 'set-option':
        (base / ('pane-' + a[a.index('-t') + 1])).write_text(a[-1])
''')
stub.chmod(0o755)
for name in ('gwt-path', 'tmux', 'codex'):
    (fake / name).symlink_to(stub)
env = dict(os.environ, PATH=str(fake) + ':' + os.environ['PATH'], TEST_ROOT=str(base), TMUX='fake', TMUX_PANE='%1')
primary = base / 'original $(touch injected) with spaces'
primary.mkdir()

def run(*args, cwd=primary, ok=True, extra=None):
    result = subprocess.run(args, cwd=cwd, env=env | (extra or {}), text=True, capture_output=True)
    assert (result.returncode == 0) == ok, (args, result.returncode, result.stdout, result.stderr)
    return result

def git(*args, cwd=primary):
    return run('git', *args, cwd=cwd).stdout.strip()

def call(*args, cwd=primary, ok=True, extra=None):
    return run(cli, *args, cwd=cwd, ok=ok, extra=extra)

def listing(cwd=primary):
    return json.loads(call('--list', cwd=cwd).stdout)

def status(task, **kw):
    return json.loads(call('--status', task['id'], **kw).stdout)

def launch(branch, prompt='Task', *options, cwd=primary, **kw):
    before = {t['id'] for t in listing(cwd)}
    call(*options, branch, prompt, cwd=cwd, **kw)
    tasks = [t for t in listing(cwd) if t['id'] not in before]
    assert len(tasks) == 1
    return tasks[0]

def report(task, state, *options, ok=True, cwd=None):
    return call('--report', task['id'], state, *options, cwd=cwd or task['worktree'], ok=ok)

git('init', '-qb', 'main')
git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'initial', '--allow-empty')
config = (Path(env['HOME']) / '.codex/config.toml').read_bytes()
assert listing() == []
assert not (primary / '.codex-tasks').exists()
assert not (primary / '.git/codex-delegate.lock').exists()
call('feat/no-prompt', ok=False)
call('feat/outside', 'x', extra={'TMUX': ''}, ok=False)
call('-m', ok=False)
call('--report', '../../evil', 'running', '--summary', 'x', ok=False)
assert not (base / 'worktrees with spaces').exists()

(primary / '.agent-handoff.md').write_text('handoff content')
call('feat/handoff')
first = listing()[0]
worker = Path(first['worktree'])
assert not (primary / '.agent-handoff.md').exists()
assert (worker / '.agent-handoff.md').read_text() == 'handoff content'
assert first['launch'] == 'sent' and first['report'] is None
assert first['session'] == '$7' and first['tmux_server'] == '123'
assert status(first)['pane_observation'].startswith('present')
assert status(first, extra={'DEAD': '1'})['pane_observation'] == 'dead'
assert status(first, extra={'SERVER': '456'})['pane_observation'] == 'identity-mismatch'
# Pane reuse cannot masquerade as the original worker.
marker = base / ('pane-' + first['pane'])
marker.write_text('different-task')
assert status(first)['pane_observation'] == 'identity-mismatch'
marker.unlink()
assert status(first)['pane_observation'] == 'missing or unreachable'

# Shell quoting, -m aliases, handoff prompt and wrapper argument compatibility.
prompt = "fix the build; $(touch injected) `touch injected2` 'quotes'\nsecond line"
model = "model;$(touch injected3) with spaces"
second = launch('feat/quote;literal', prompt, '-m', model, cwd=worker)
commands = [json.loads(line) for line in (base / 'tmux.log').read_text().splitlines()]
keys = [a[-1] for a in commands if a[:1] == ['send-keys'] and '-l' in a]
assert shlex.split(keys[0])[:2] == ['codex', 'new']
assert shlex.split(keys[0])[-1].startswith('Read .agent-handoff.md and continue the work it describes.')
assert shlex.split(keys[-1])[:4] == ['codex', 'new', '--model', model]
assert shlex.split(keys[-1])[-1].startswith(prompt)
assert '--report ' + second['id'] in shlex.split(keys[-1])[-1]
# Execute recorded input against the real launch wrapper with only a fake paid CLI.
run('bash', '-c', keys[-1], extra={'PATH': str(root / 'bin') + ':' + env['PATH']})
arguments = json.loads((base / 'codex.args').read_text())
assert arguments[:4] == ['--no-alt-screen', '--approve-for-me', '--model', model]
assert arguments[-1].startswith(prompt)
assert not any(primary.glob('injected*'))
third = launch('feat/model', '--status is a literal prompt', '--model', 'gpt-6-luna')
assert shlex.split([json.loads(l)[-1] for l in (base / 'tmux.log').read_text().splitlines()
                    if json.loads(l)[:1] == ['send-keys'] and '-l' in json.loads(l)][-1])[:4] == ['codex', 'new', '--model', 'gpt-6-luna']

# Launching itself never installs or changes settings (wrapper fixture above
# may refresh its isolated HOME, so use a fresh baseline).
config = (Path(env['HOME']) / '.codex/config.toml').read_bytes()
launch('feat/no-settings')
assert (Path(env['HOME']) / '.codex/config.toml').read_bytes() == config

summary = "Done; $(touch injected)\nDetails with 'quotes'"
report(first, 'running', '--summary', 'Started')
report(first, 'needs-input', '--summary', 'Need decision')
assert status(first)['report']['state'] == 'needs-input'
report(first, 'completed', '--summary', summary, '--checks', 'fixture checks: passed', '--commit', git('rev-parse', 'HEAD', cwd=worker))
completed = status(first)
assert completed['report']['summary'] == summary
assert all(completed['reported_commits_on_branch'].values())
assert status(second)['report'] is None
snapshot = (primary / '.codex-tasks' / (first['id'] + '.json')).read_bytes()
for args in [('bogus', '--summary', 'x'), ('failed', '--summary', 'x'),
             ('running', '--summary', ' '), ('completed', '--summary', 'x', '--checks', ' '),
             ('running', '--summary', 'x', '--commit', 'HEAD'),
             ('running', '--summary', 'x', '--commit', 'a' * 40)]:
    report(first, *args, ok=False)
report(first, 'running', '--summary', 'wrong worker', cwd=second['worktree'], ok=False)
assert (primary / '.codex-tasks' / (first['id'] + '.json')).read_bytes() == snapshot
report(third, 'failed', '--summary', 'Cannot proceed', '--checks', 'Not run: fixture dependency missing')

# A worker cannot report after switching away from its assigned branch.
git('switch', '-qc', 'feat/wrong', cwd=second['worktree'])
report(second, 'running', '--summary', 'wrong branch', ok=False)
git('switch', '-q', second['branch'], cwd=second['worktree'])
# Independent reports/launches cannot lose another task's writes.
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    futures = [pool.submit(report, second if i % 2 else third, 'running', '--summary', str(i)) for i in range(12)]
    for future in futures: future.result()
assert status(second)['report'] and status(third)['report']
# Nested cwd resolves the same original root, and reads do not touch state/exclude/lock.
nested = worker / 'nested dir'; nested.mkdir()
assert listing(nested) == listing()
shared_files = [primary / '.git/info/exclude', primary / '.git/codex-delegate.lock', *sorted((primary / '.codex-tasks').glob('*.json'))]
before = [(p.read_bytes(), p.stat().st_mtime_ns) for p in shared_files]
call('--list', cwd=nested)
status(first, cwd=nested)
assert before == [(p.read_bytes(), p.stat().st_mtime_ns) for p in shared_files]
assert git('check-ignore', '.codex-tasks/test') == '.codex-tasks/test'
assert not (worker / '.codex-tasks').exists()

# Stored completion survives worker deletion and missing tmux. Git refs are
# independently inspected, including missing branches and nonancestor commits.
git('worktree', 'remove', '--force', str(worker))
(fake / 'tmux').rename(fake / 'tmux.off')
# A minimal PATH proves stored reads do not require a tmux installation.
minimal = base / 'minimal-bin'; minimal.mkdir()
for tool in ('python3', 'git'):
    (minimal / tool).symlink_to(shutil.which(tool))
no_tmux = dict(PATH=str(minimal))
assert json.loads(call('--list', extra=no_tmux).stdout)
assert status(first, extra=no_tmux)['report']['state'] == 'completed'
assert not status(first)['worktree_exists']
git('branch', '-D', first['branch'])
assert status(first)['branch_head'] is None
assert not all(status(first)['reported_commits_on_branch'].values())
(fake / 'tmux.off').rename(fake / 'tmux')

# Partial failure retains identifiable state and moved handoff, never cleanup.
failed = launch('feat/fail-window', extra={'FAIL_TMUX': 'new-window'}, ok=False)
assert failed['launch'] == 'failed' and failed['pane'] is None and Path(failed['worktree']).is_dir()
(primary / '.agent-handoff.md').write_text('retained on failure')
failed = launch('feat/fail-send', extra={'FAIL_TMUX': 'send-keys'}, ok=False)
assert failed['launch'] == 'failed' and failed['pane']
assert not (primary / '.agent-handoff.md').exists()
assert (Path(failed['worktree']) / '.agent-handoff.md').read_text() == 'retained on failure'
failed = launch('feat/fail-gwt', extra={'FAIL_GWT': '1'}, ok=False)
assert failed['launch'] == 'failed' and failed['worktree'] is None
assert 'fixture worktree creation failed' in failed['launch_error']

# Missing task, symlink storage and tracked storage fail explicitly.
call('--status', 'a' * 32, ok=False)
state = primary / '.codex-tasks'
state.rename(primary / 'saved-tasks')
state.symlink_to(primary / 'saved-tasks', target_is_directory=True)
call('--list', ok=False)
state.unlink(); (primary / 'saved-tasks').rename(state)
git('add', '-f', '.codex-tasks')
report(second, 'running', '--summary', 'must fail', ok=False)
git('reset', '-q', '--', '.codex-tasks')
tracked_worker_state = Path(second['worktree']) / '.codex-tasks'
tracked_worker_state.mkdir()
(tracked_worker_state / 'tracked').write_text('preserve')
git('add', '-f', '.codex-tasks', cwd=second['worktree'])
report(third, 'running', '--summary', 'tracked in linked worker', ok=False)
git('reset', '-q', '--', '.codex-tasks', cwd=second['worktree'])
# Ordinary filesystem denial gives approval guidance; this is not a live sandbox test.
assert os.geteuid() != 0
lock = primary / '.git/codex-delegate.lock'
lock.chmod(0o400)
try:
    result = report(second, 'running', '--summary', 'denied', ok=False)
    assert 'require_escalated' in result.stderr
finally:
    lock.chmod(0o600)

# Unsupported roots never acquire state.
for separate in (False, True):
    directory = base / ('unsupported ' + str(separate)); directory.mkdir()
    if separate:
        git('init', '-q', '--separate-git-dir', str(base / 'separate metadata'), cwd=directory)
    else:
        git('init', '--bare', '-q', cwd=directory)
    call('--list', cwd=directory, ok=False)
    assert not (directory / '.codex-tasks').exists()
print('PASS: Codex delegation launch, explicit lifecycle, shared state and failures (fake agents/tmux)')
PY
