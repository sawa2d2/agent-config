#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
python3 - "$root" <<'PY'
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp)
    env = {**os.environ, 'HOME': tmp, 'TZ': 'UTC',
           'CODEX_HOME': str(home / '.codex'), 'CLAUDE_CONFIG_DIR': str(home / '.claude')}
    def run(agent, *args, ok=True):
        p = subprocess.run([str(root / 'bin/ai-stats'), agent, *args],
                           env=env, text=True, capture_output=True)
        assert (p.returncode == 0) == ok, (agent, args, p.returncode, p.stderr)
        return p.stdout if ok else p.stderr
    def rows(agent, *args):
        return [json.loads(line) for line in run(agent, '--json', *args).splitlines()]
    def write(path, records):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('\n'.join(json.dumps(r) for r in records) + '\n')
    def rec(kind, payload, time='2026-01-01T00:00:01Z'):
        return {'timestamp': time, 'type': kind, 'payload': payload}
    def meta(id, project='/repo/alpha', time='2026-01-01T00:00:00Z', **extra):
        return rec('session_meta', {'id': id, 'cwd': project, 'timestamp': time, **extra}, time)
    def usage(i=100, cache=80, out=20):
        return {'input_tokens': i, 'cached_input_tokens': cache, 'cache_write_input_tokens': 0,
                'output_tokens': out, 'reasoning_output_tokens': 5, 'total_tokens': i + out}
    def response(id, owner, u=None, time='2026-01-01T00:00:01Z'):
        return rec('token_usage_record', {'response_id': id, 'thread_id': owner,
                   'session_id': 'root', 'usage': u if u is not None else usage()}, time)
    def event(counter, u=None, time='2026-01-01T00:00:02Z'):
        return rec('event_msg', {'type': 'token_count', 'info': {
            'last_token_usage': usage() if u is None else u,
            'total_token_usage': {**usage(), 'total_tokens': counter},
            'model_context_window': 200000}}, time)

    for agent in ('claude', 'codex'):
        assert not rows(agent)
        assert 'sessions' in run(agent)

    # Sanitized shapes observed in local rollouts: response usage and token_count
    # both describe the same response; the parent may also contain child usage.
    cd = home / '.codex'
    parent = [meta('root'), rec('turn_context', {'model': 'model-a'}),
              response('r1', 'root'), event(120), event(120), response('r2', 'child')]
    child = [meta('child', parent_thread_id='root'), rec('turn_context', {'model': 'model-b'}),
             response('r2', 'child'), event(120)]
    write(cd / 'sessions/root.jsonl', parent)
    write(cd / 'sessions/child.jsonl', child)
    # Archive copies can be shorter or longer than active files.
    write(cd / 'archived_sessions/copy.jsonl', parent + [response('r3', 'root')])
    cr = {r['id']: r for r in rows('codex')}
    assert set(cr) == {'root', 'child'} and cr['root']['requests'] == 2, cr
    assert cr['child']['requests'] == 1 and cr['child']['models'] == ['model-b'], cr
    assert cr['root']['input'] == 200 and cr['root']['cache_read'] == 160, cr
    assert cr['root']['reasoning'] == 10 and cr['root']['total'] == 240, cr
    assert cr['root']['context_windows'] == [200000] and cr['root']['cost'] is None, cr
    assert sum(r['requests'] for r in cr.values()) == 3
    assert len(rows('codex', '--min-requests', '2')) == 1
    assert len(rows('codex', '--project', 'alpha')) == 2
    assert not rows('codex', '--project', 'absent')
    assert not rows('codex', '--until', '2026-01-01')
    assert len(rows('codex', '--since', '2026-01-01')) == 2
    assert len(rows('codex', '--since', '2026-01-01T09:00+09:00')) == 2

    # No response IDs: distinct timestamps must not be collapsed into a None key.
    sparse = [meta('sparse', '/repo/beta', '2026-02-01T00:00:00Z'),
              response(None, 'sparse', {'input_tokens': 12}, '2026-02-01T00:00:01Z'),
              response(None, 'sparse', {'input_tokens': 13}, '2026-02-01T00:00:02Z')]
    write(cd / 'sessions/sparse.jsonl', sparse)
    write(cd / 'archived_sessions/sparse-copy.jsonl', sparse)
    r = rows('codex', '--project', 'beta')[0]
    assert r['requests'] == 2 and r['input'] == 25 and r['cache_read'] is None, r
    assert r['weighted'] is None and r['output'] is None and r['reasoning'] is None, r
    assert 'unknown' in run('codex', '--project', 'beta', '-w', '0')
    # Cumulative events are never summed; unchanged limit notifications add no request.
    write(cd / 'sessions/events.jsonl', [meta('events', '/repo/events'), event(120), event(120),
          event(240, time='2026-01-01T00:00:03Z'), event(240, time='2026-01-01T00:00:04Z')])
    r = rows('codex', '--project', '/events')[0]
    assert r['requests'] == 2 and r['total'] == 240 and r['usage_source'] == 'token_count', r
    # Fork baseline belongs to the old history, not the new fork.
    write(cd / 'sessions/fork.jsonl', [meta('fork', '/repo/fork', forked_from_id='events'),
                                     event(240), event(360, time='2026-01-01T00:00:04Z')])
    r = rows('codex', '--project', '/fork')[0]
    assert r['requests'] == 1 and r['total'] == 120, r
    write(cd / 'sessions/empty.jsonl', [meta('empty'), rec('event_msg', {'type': 'token_count', 'info': None})])
    with (cd / 'sessions/empty.jsonl').open('a') as f:
        f.write('not json\nnull\n')
    assert not rows('codex', '--min-requests', '100')

    # Bob schema: directory is the project; subagents share the parent's budget.
    dbpath = home / '.bob/db/bob.db'
    dbpath.parent.mkdir(parents=True)
    db = sqlite3.connect(dbpath)
    db.executescript('''CREATE TABLE tasks (id TEXT PRIMARY KEY, parent_id TEXT, task_type TEXT,
        created_at INTEGER, costs TEXT, env TEXT, directory TEXT);
        CREATE TABLE messages (id TEXT PRIMARY KEY, task_id TEXT, role TEXT, data TEXT, created_at INTEGER);''')
    assert not rows('bob')
    assert 'tasks' in run('bob')
    def task(id, ms, parent=None, kind='normal', directory='/repo/alpha'):
        db.execute('INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?, ?)',
                   (id, parent, kind, ms, json.dumps({'cost': .25}),
                    json.dumps({'model': {'id': 'bob-model', 'contextWindow': 270000}}), directory))
    def message(id, owner, spend=None, summary=False):
        m = {'summary': True} if summary else {'spend': spend}
        db.execute('INSERT INTO messages VALUES (?, ?, ?, ?, ?)',
                   (id, owner, 'assistant', json.dumps({'_meta': m}), 1767225600000))
    task('a', 1767225600000)
    task('sub', 1769904000000, 'a', 'subagent', '/repo/child')
    task('b', 1769904000000, directory='/repo/beta')
    message('a1', 'a', {'cost': .1, 'contextTokens': 100})
    message('a2', 'sub', {'cost': .2, 'contextTokens': 200})
    message('a3', 'sub', summary=True)
    message('b1', 'b', {'contextTokens': 0})
    db.commit()
    r = rows('bob', '--project', 'alpha')[0]
    assert r['requests'] == 2 and abs(r['cost'] - .3) < 1e-9 and r['compactions'] == 1, r
    assert r['context'] == 300 and r['input'] is None and r['output'] is None, r
    assert r['models'] == [{'id': 'bob-model', 'contextWindow': 270000}], r
    assert len(rows('bob', '--min-requests', '2')) == 1
    assert not rows('bob', '--project', '/child')
    r = rows('bob', '--since', '2026-02-01')[0]
    assert r['id'] == 'b' and r['cost'] is None and r['context'] == 0, r
    assert 'unknown' in run('bob', '--project', 'beta', '-w', '0')
    assert '0.300' in run('bob', '--project', 'alpha', '--split', '2026-02-01')

    for args, ok in ((['--help'], True), ([], False), (['unknown'], False)):
        p = subprocess.run([str(root / 'bin/ai-stats'), *args], env=env,
                           text=True, capture_output=True)
        assert (p.returncode == 0) == ok, (args, p.stderr)
    # Symlink launchers must locate the shared modules from outside the repo.
    link = home / 'stats-link'
    link.symlink_to(root / 'bin/ai-stats')
    p = subprocess.run([str(link), 'codex', '--json'], cwd=home, env=env,
                       text=True, capture_output=True)
    assert p.returncode == 0 and p.stdout == run('codex', '--json'), p.stderr
    assert all(not key.startswith('_') and key != 'request_times'
               for agent in ('bob', 'codex') for row in rows(agent) for key in row)

    # Common semantics and validation for every agent, including empty JSON Lines.
    claude = home / '.claude/projects/alpha/a.jsonl'
    write(claude, [{'timestamp': '2026-01-01T00:00:00Z', 'type': 'assistant', 'requestId': 'a',
                    'message': {'id': 'm', 'usage': {'input_tokens': 10, 'output_tokens': 1}}}])
    repo = home / 'repo'
    subprocess.run(['git', 'init', '-q', str(repo)], check=True)
    subprocess.run(['git', '-C', str(repo), '-c', 'user.name=t', '-c', 'user.email=t@t',
                    'commit', '-q', '--allow-empty', '-m', 'fixture'], check=True,
                   env={**env, 'GIT_COMMITTER_DATE': '2026-02-01T00:00:00Z'})
    for agent in ('claude', 'bob', 'codex'):
        help = run(agent, '--help')
        for option in ('--since', '--until', '--split', '--split-commit', '--repo', '--project',
                       '--min-requests', '--window', '--windows', '--weeks', '--json'):
            assert option in help, (agent, option)
        assert not rows(agent, '--project', 'does-not-exist')
        for args in (('--since', 'bad'), ('--until', 'bad'), ('--split', 'bad'),
                     ('--since', '2026-02-01', '--until', '2026-01-01'), ('-w', '-1'),
                     ('--min-requests', '0'), ('--window', '0h'),
                     ('--split', '2026-01-01', '--split-commit', 'HEAD'),
                     ('--split-commit', 'not-a-ref', '--repo', str(repo))):
            error = run(agent, *args, ok=False)
            assert 'error:' in error and 'Traceback' not in error, (agent, args, error)
        assert run(agent, '--weeks', '0') == run(agent, '--windows', '0') == run(agent, '-w', '0')
        assert rows(agent) == rows(agent, '--window', '5h', '-w', '1')
        assert rows(agent) == rows(agent, '--split', '2026-02-01')
        assert '2025-12-29' in run(agent, '--until', '2026-02-01')
        assert run(agent, '--split', '2026-02-01') == run(
            agent, '--split-commit', 'HEAD', '--repo', str(repo))
        assert 'before: 0 sessions' in run(agent, '--split', '1900-01-01')
        assert 'after: 0 sessions' in run(agent, '--split', '2100-01-01')
    db.close()
print('PASS: stats parity, source formats, deduplication and missing data')
PY
