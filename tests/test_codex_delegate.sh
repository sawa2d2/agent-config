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
import shutil
import shlex
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
    if a == ['app-server']:
        for line in sys.stdin:
            message = json.loads(line)
            if message['method'] == 'initialize':
                print(json.dumps({'id': 1, 'result': {}}), flush=True)
            elif message['method'] == 'config/value/write':
                assert message['params']['value'] == 'trusted'
                assert message['params']['mergeStrategy'] == 'replace'
                if os.environ.get('FAIL_TRUST'):
                    print(json.dumps({'id': 2, 'error': {'message': 'fixture trust denied'}}), flush=True)
                else:
                    with (base / 'trust.log').open('a') as f:
                        f.write(json.dumps(message['params']) + '\\n')
                    print(json.dumps({'id': 2, 'result': {'status': 'ok'}}), flush=True)
        sys.exit(0)
    (base / 'codex.args').write_text(json.dumps(a))
    if os.environ.get('AUTO_REPORT') and not os.environ.get('NO_REPORT'):
        import re
        task = re.search(r'Delegated Codex task ID: ([0-9a-f]{32})', a[-1]).group(1)
        subprocess.run([os.environ['TEST_CLI'], '--report', task,
                        os.environ.get('WORKER_REPORT', 'running'), '--summary', 'Fixture worker acknowledged',
                        '--checks', 'fixture startup'], check=True)
else:
    with (base / 'tmux.log').open('a') as f: f.write(json.dumps(a) + '\\n')
    if os.environ.get('FAIL_TMUX') == a[0]:
        print(os.environ.get('TMUX_ERROR', 'fixture permission denied'), file=sys.stderr)
        sys.exit(1)
    if a[0] == 'display-message':
        if a[-1] == '#{session_id}': print('$7')
        elif a[-1] == '#{pid}': print('123')
        elif a[-1] == '#{pane_dead}': print(os.environ.get('DEAD', '0'))
        elif a[-1] == '#{@delegate_ready}': print((base / 'ready').read_text() if (base / 'ready').exists() else '')
        else:
            pane = a[a.index('-t') + 1]
            token = (base / ('pane-' + pane)).read_text()
            print(os.environ.get('SERVER', '123') + '\\t' + token + '\\t' + os.environ.get('DEAD', '0'))
    elif a[0] == 'new-window':
        directory = str(Path(a[a.index('-c') + 1]).resolve())
        assert any(json.loads(line)['keyPath'] == 'projects.' + json.dumps(directory, ensure_ascii=False) + '.trust_level'
                   for line in (base / 'trust.log').read_text().splitlines())
        pane = '%' + uuid.uuid4().hex
        (base / ('dir-' + pane)).write_text(a[a.index('-c') + 1])
        print(pane)
    elif a[0] == 'set-option':
        (base / ('ready' if a[-2] == '@delegate_ready' else 'pane-' + a[a.index('-t') + 1])).write_text(a[-1])
    elif a[0] == 'send-keys':
        pane = a[a.index('-t') + 1]
        keys = base / ('keys-' + pane)
        if '-l' in a:
            keys.write_text(a[-1])
        elif a[-1] == 'Enter':
            subprocess.run(['bash', '-c', keys.read_text()], cwd=(base / ('dir-' + pane)).read_text(),
                           env=dict(os.environ, AUTO_REPORT='1'), check=True)
''')
stub.chmod(0o755)
for name in ('gwt-path', 'tmux', 'codex'):
    (fake / name).symlink_to(stub)
env = dict(os.environ, PATH=str(fake) + ':' + os.environ['PATH'], TEST_ROOT=str(base), TEST_CLI=cli, TMUX='fake', TMUX_PANE='%1')
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
    result = call(*options, branch, prompt, cwd=cwd, **kw)
    if kw.get('ok', True):
        assert 'launch input sent' in result.stdout and 'verified worker startup' in result.stdout
    tasks = [t for t in listing(cwd) if t['id'] not in before]
    assert len(tasks) == 1
    return tasks[0]

def report(task, state, *options, ok=True, cwd=None):
    return call('--report', task['id'], state, *options, cwd=cwd or task['worktree'], ok=ok)

def shell_words(command):
    assert '\n' not in command and '\r' not in command, repr(command)
    # JSON avoids subprocess text mode normalizing CRLF inside arguments.
    capture = '; python3 -c \'import json, sys; print(json.dumps(sys.argv[1:]))\' "$@"'
    return json.loads(run('bash', '-c', 'set -- ' + command + capture).stdout)

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
assert first['launch'] == 'verified' and first['report']['state'] == 'running'
assert first['session'] == '$7' and first['tmux_server'] == '123'
assert status(first)['pane_observation'].startswith('present')
assert status(first, extra={'DEAD': '1'})['pane_observation'] == 'dead'
assert status(first, extra={'SERVER': '456'})['pane_observation'] == 'identity-mismatch'
# Pane reuse cannot masquerade as the original worker.
marker = base / ('pane-' + first['pane'])
marker.write_text('different-task')
assert status(first)['pane_observation'] == 'identity-mismatch'
marker.unlink()
assert status(first)['pane_observation'] == 'inaccessible'
denied = status(first, extra={'FAIL_TMUX': 'display-message', 'TMUX_ERROR': 'Operation not permitted'})
assert denied['pane_observation'] == 'inaccessible'
assert denied['pane_observation_error'] == 'Operation not permitted'

# Shell quoting, -m aliases, handoff prompt and wrapper argument compatibility.
prompt = "fix the build; $(touch injected) `touch injected2` 'quotes'\nsecond line\r\n日本語 \\n literal\n"
prompt += "\t\x1b[31m\x7f\\end"
model = "model;$(touch injected3) with spaces"
second = launch('feat/quote;literal', prompt, '-m', model, cwd=worker)
commands = [json.loads(line) for line in (base / 'tmux.log').read_text().splitlines()]
keys = [a[-1] for a in commands if a[:1] == ['send-keys'] and '-l' in a]
keys = [key for key in keys if "codex" in key]
permissions = ['--sandbox', 'danger-full-access', '--ask-for-approval', 'on-request']
assert shell_words(keys[0])[:6] == [str(root / 'bin/codex'), 'new', *permissions]
assert shell_words(keys[0])[-1].startswith('Read .agent-handoff.md and continue the work it describes.')
assert shell_words(keys[-1])[:8] == [str(root / 'bin/codex'), 'new', *permissions, '--model', model]
assert shell_words(keys[-1])[-1].startswith(prompt)
assert '--report ' + second['id'] in shell_words(keys[-1])[-1]
# Report instructions must work even when codex-delegate is missing from PATH.
worker_text = shell_words(keys[-1])[-1]
report_line = next(line.strip() for line in worker_text.splitlines()
                   if ' running --summary ' in line)
report_args = shlex.split(report_line)
assert report_args[:4] == [cli, '--report', second['id'], 'running']
run(*report_args[:4], '--summary', 'Reporting without installed PATH launcher', cwd=second['worktree'])
assert status(second)['report']['summary'] == 'Reporting without installed PATH launcher'
assert 'do not ask for conversational confirmation again' in worker_text
assert 'report any denial without bypassing it' in worker_text
# Execute recorded input against the real launch wrapper with only a fake paid CLI.
run('bash', '-c', keys[-1], extra={'PATH': str(root / 'bin') + ':' + env['PATH']})
arguments = json.loads((base / 'codex.args').read_text())
assert arguments[:9] == ['-c', 'tui.animations=false', '--no-alt-screen', *permissions, '--model', model]
assert '--approve-for-me' not in arguments
assert arguments[-1].startswith(prompt)
assert arguments[-1] == shell_words(keys[-1])[-1]
assert not any(primary.glob('injected*'))
third = launch('feat/model', '--status is a literal prompt', '--model', 'gpt-6-luna')
assert json.loads((base / 'codex.args').read_text())[:9] == ['-c', 'tui.animations=false', '--no-alt-screen', *permissions, '--model', 'gpt-6-luna']

# The intended wrapper refreshes only the isolated HOME; repeated launches
# preserve the already installed configuration.
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
assert status(second)['report']['state'] == 'running'
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
tmux_before = (base / 'tmux.log').read_bytes()
failed = launch('feat/fail-trust', extra={'FAIL_TRUST': '1'}, ok=False)
assert failed['launch'] == 'failed' and failed['pane'] is None and Path(failed['worktree']).is_dir()
assert 'fixture trust denied' in failed['launch_error']
assert (base / 'tmux.log').read_bytes() == tmux_before
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
    assert 'Report the denied operation' in result.stderr
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
# Explicit selection isolates every mutation from the originating repository.
target = base / 'target repo with spaces'; target.mkdir()
git('init', '-qb', 'main', cwd=target)
(target / 'target-only').write_text('target commit')
git('add', 'target-only', cwd=target)
git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'target', cwd=target)
target_head = git('rev-parse', 'HEAD', cwd=target)
(primary / '.agent-handoff.md').write_text('origin must retain this note')

def snapshot(directory):
    return {str(p.relative_to(directory)): (p.read_bytes(), p.stat().st_mtime_ns)
            if p.is_file() else None for p in directory.rglob('*')}

origin_before = snapshot(primary)
target_before = snapshot(target)
assert json.loads(call('--repo', str(target), '--list').stdout) == []
assert snapshot(target) == target_before
# Missing, empty, file, non-Git and unsupported paths fail before any writes.
nonrepo = base / 'not a repository'; nonrepo.mkdir()
invalid_paths = ['', str(base / 'missing repo'), str(target / 'target-only'),
                 str(nonrepo), str(base / 'unsupported False'), str(base / 'unsupported True')]
tmux_before = (base / 'tmux.log').read_bytes()
for path in invalid_paths:
    for operation in [('feat/invalid-repo', 'Task'), ('--list',),
                      ('--status', second['id']),
                      ('--report', second['id'], 'running', '--summary', 'invalid')]:
        call('--repo', path, *operation, ok=False)
call('--repo', ok=False)
call('--repo=', 'feat/empty-repo', 'Task', ok=False)
assert (base / 'tmux.log').read_bytes() == tmux_before
assert snapshot(target) == target_before
assert not any(nonrepo.iterdir())

# A note in the origin cannot satisfy a missing target handoff.
call('--repo', str(target), 'feat/target-missing-note', ok=False)
assert snapshot(target) == target_before
(target / '.agent-handoff.md').write_text('target handoff')
target_nested = target / 'nested directory'; target_nested.mkdir()
call('--repo', os.path.relpath(target_nested, primary), 'feat/target-handoff')
selected = listing(target)[0]
selected_worker = Path(selected['worktree'])
assert git('rev-parse', 'HEAD', cwd=selected_worker) == target_head
assert (selected_worker / 'target-only').read_text() == 'target commit'
assert (selected_worker / '.agent-handoff.md').read_text() == 'target handoff'
assert not (target / '.agent-handoff.md').exists()
assert (target / '.git/codex-delegate.lock').is_file()
assert git('check-ignore', '.codex-tasks/test', cwd=target) == '.codex-tasks/test'
assert json.loads(call('--repo', str(target), '--list').stdout) == listing(target)
assert json.loads(call('--repo', str(target), '--status', selected['id']).stdout)['branch_head'] == target_head
call('--status', selected['id'], ok=False)
call('--repo', str(target), '--status', second['id'], ok=False)

# Reporting still validates the selected worker and branch, even from elsewhere.
record = target / '.codex-tasks' / (selected['id'] + '.json')
record_before = record.read_bytes()
call('--repo', str(target), '--report', selected['id'], 'running', '--summary', 'wrong checkout', ok=False)
call('--repo', second['worktree'], '--report', selected['id'], 'running', '--summary', 'wrong repo', ok=False)
assert record.read_bytes() == record_before
selected_nested = selected_worker / 'worker subdirectory'; selected_nested.mkdir()
call('--repo', str(selected_nested), '--report', selected['id'], 'completed',
     '--summary', 'selected worker', '--checks', 'fixture checks passed', '--commit', target_head, cwd=nonrepo)
assert status(selected, cwd=target)['reported_commits_on_branch'] == {target_head: True}
git('switch', '-qc', 'feat/selected-wrong', cwd=selected_worker)
call('--repo', str(selected_worker), '--report', selected['id'], 'running', '--summary', 'wrong branch', ok=False)
git('switch', '-q', selected['branch'], cwd=selected_worker)

# Both option orders and model spellings retain literal option-like prompts.
for index, options in enumerate([
    ['--repo', str(target), '-m', model],
    ['-m', model, '--repo', str(target)],
    ['--repo', str(target), '--model', model],
    ['--model', model, '--repo', str(target)],
    ['--repo=' + str(target), '--model=' + model],
]):
    literal = '--repo /ignored --status --model literal prompt'
    call(*options, f'feat/selected-grammar-{index}', literal)
    command = [json.loads(line)[-1] for line in (base / 'tmux.log').read_text().splitlines()
               if json.loads(line)[:1] == ['send-keys'] and '-l' in json.loads(line)][-1]
    assert shell_words(command)[:8] == [str(root / 'bin/codex'), 'new', *permissions, '--model', model]
    assert shell_words(command)[-1].startswith(literal)

# A selected linked checkout supplies its own HEAD and note, not the main root.
git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'worker commit', '--allow-empty', cwd=selected_worker)
linked_head = git('rev-parse', 'HEAD', cwd=selected_worker)
(target / '.agent-handoff.md').write_text('main note stays')
call('--repo', str(selected_nested), 'feat/selected-linked')
linked = next(t for t in listing(target) if t['branch'] == 'feat/selected-linked')
assert git('rev-parse', 'HEAD', cwd=linked['worktree']) == linked_head
assert (Path(linked['worktree']) / '.agent-handoff.md').read_text() == 'target handoff'
assert (target / '.agent-handoff.md').read_text() == 'main note stays'
assert not (selected_worker / '.codex-tasks').exists()
assert snapshot(primary) == origin_before
print('PASS: Codex delegation launch, explicit repository selection, lifecycle, shared state and failures (fake agents/tmux)')
PY
