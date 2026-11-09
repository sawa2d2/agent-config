#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
PYTHONPATH="$root/lib" python3 - <<'PY'
import os
import io
from contextlib import redirect_stdout
import time
from datetime import date, datetime, timedelta
from unittest.mock import patch

from ai_stats import Windows, arguments, parse_time, window_spec
from ai_stats import claude, codex, bob


def windows(spec, count=1, now='2026-11-08T15:42:17+09:00'):
    with patch('ai_stats.datetime') as clock:
        clock.now.return_value = datetime.fromisoformat(now)
        return Windows(window_spec(spec), count)


os.environ['TZ'] = 'Asia/Tokyo'
time.tzset()
daily = windows('1d')
assert daily.first == date(2026, 11, 8)
assert daily.key(parse_time('2026-11-07T14:59:59Z')) == date(2026, 11, 7)
assert daily.key(parse_time('2026-11-07T15:00:00Z')) == date(2026, 11, 8)
assert daily.key(parse_time('2026-11-09T00:00:00+09:00')) == date(2026, 11, 9)
assert daily.label(daily.first).strip() == '2026-11-08 00:00'
assert not daily.shown(daily.first - daily.step)
assert windows('1d', 0).shown(date(2000, 1, 1))
assert windows('1d', 2).shown(daily.first - daily.step)
assert windows('1d', now='2026-11-08T00:00:00+09:00').first == daily.first
assert windows('1d', now='2026-11-09T00:00:00+09:00').first == date(2026, 11, 9)

for spec in ('1w', '1week', 'week'):
    weekly = windows(spec)
    assert weekly.first == date(2026, 11, 2), spec
    assert weekly.key(parse_time('2026-11-02T00:00:00+09:00')) == date(2026, 11, 2)
    assert weekly.key(parse_time('2026-11-01T23:59:59+09:00')) == date(2026, 10, 26)
    assert windows(spec, now='2026-11-09T00:00:00+09:00').first == date(2026, 11, 9)
assert windows('week').weekly and not windows('1week').weekly

for spec, first, previous in (('2d', date(2026, 11, 7), date(2026, 11, 5)),
                              ('2week', date(2026, 10, 26), date(2026, 10, 12))):
    w = windows(spec)
    assert w.first == first
    assert w.key(parse_time(f'{first}T00:00:00')) == first
    assert w.key(parse_time(f'{first}T00:00:00') - timedelta(seconds=1)) == previous
    assert w.first - w.step == previous  # Previous-window ratio lookup.
    assert windows(spec, 0).key(parse_time(f'{first}T00:00:00')) == first

# Midnight keys and previous-window lookup must survive both DST transitions.
os.environ['TZ'] = 'America/New_York'
time.tzset()
for day, before, after in (('2026-03-08', '-05:00', '-04:00'),
                           ('2026-11-01', '-04:00', '-05:00')):
    w = windows('1d', now=f'{day}T15:00:00{after}')
    expected = date.fromisoformat(day)
    for stamp in (f'{day}T00:00:00{before}', f'{day}T23:59:59{after}'):
        assert w.key(parse_time(stamp)) == expected, stamp
    previous = w.key(parse_time(f'{day}T00:00:00{before}') - timedelta(seconds=1))
    assert previous == w.first - w.step
    assert w.label(previous).strip().endswith('00:00')

# Hour windows retain their rolling anchor and end-inclusive exact boundaries.
for spec, hours in (('5h', 5), ('24h', 24)):
    w = windows(spec)
    assert w.end == parse_time('2026-11-08T15:42:17+09:00')
    assert w.first == w.end - timedelta(hours=hours)
    assert w.key(w.end) == w.first
    assert w.key(w.first) == w.first - w.step
    assert w.key(w.first + timedelta(microseconds=1)) == w.first
# The shared default and alias select local dates for every provider.
for agent in ('claude', 'bob', 'codex'):
    with patch('sys.argv', ['aistats', agent]):
        args = arguments()
    assert args.window == '1d' and args.windows == 10
assert window_spec('1day') == '1d' and window_spec('2day') == '2d'

os.environ['TZ'] = 'UTC'
time.tzset()
# Day 2 is absent, day 3 is measured zero, day 5 unknown (where supported).
# Hidden day 1 must remain the baseline for day 4. Unknown day 5 must not be
# skipped when computing day 6's ratio.
def stamp(day):
    return parse_time(f'2026-11-{day:02d}T12:00:00Z')

def render(backend, sessions, count=0):
    out = io.StringIO()
    with redirect_stdout(out):
        backend.print_windows(sessions, windows('1day', count, '2026-11-06T15:00:00+00:00'))
    return out.getvalue()

for backend in (claude, codex, bob):
    sessions = []
    for day, value in ((1, 10), (3, 0), (4, 20), (5, None), (6, 40)):
        if backend is claude and value is None:
            continue
        row = {'id': str(day), 'start': stamp(day), 'requests': 1, 'weighted': value,
               'cache_write': 0, 'cache_read': 0, 'task_cost': value, '_models': []}
        if backend is claude:
            row['request_times'] = [(stamp(day), value, 0, 0)]
        elif backend is codex:
            record = {metric: 0 for metric in codex.TOKEN_FIELDS}
            record.update(time=stamp(day), input=value, total=value, weighted=value,
                          model=None, context_window=None)
            row['request_times'] = [record]
        else:
            row['request_times'] = [({'spend': {'cost': value, 'contextTokens': 0}},
                                     int(stamp(day).timestamp() * 1000))]
        sessions.append(row)
    out = render(backend, sessions)
    assert '2026-11-02 00:00' not in out and '2026-11-03 00:00' not in out, out
    lines = [line for line in out.splitlines() if line.startswith('2026-11-04 00:00')]
    assert '200.0%' in lines[0], out
    hidden = render(backend, sessions, 3)
    assert lines[0] in hidden and '2026-11-01 00:00' not in hidden, hidden
    if backend is not claude:
        assert '2026-11-05 00:00' in out and 'unknown' in out, out
        line = next(line for line in out.splitlines() if line.startswith('2026-11-06 00:00'))
        assert '%' not in line, line
    assert '2026-11-' not in render(backend, [sessions[1]]), backend
    # Zero requests on an otherwise active day still count in per-request means.
    mixed = dict(sessions[0])
    mixed['request_times'] = [sessions[0]['request_times'][0], sessions[0]['request_times'][0]]
    if backend is claude:
        mixed['request_times'][1] = (stamp(1), 0, 0, 0)
    elif backend is codex:
        mixed['request_times'][1] = {**mixed['request_times'][0], **dict.fromkeys(codex.TOKEN_FIELDS, 0), 'weighted': 0}
    else:
        mixed['request_times'][1] = ({'spend': {'cost': 0, 'contextTokens': 0}}, int(stamp(1).timestamp() * 1000))
    line = next(line for line in render(backend, [mixed]).splitlines() if line.startswith('2026-11-01 00:00'))
    fields = line.split()
    assert fields[3] == '2', line
    assert fields[6 if backend is bob else 5] == ('5.000' if backend is bob else '5'), line

# A rounded-to-zero Claude total is still measured nonzero usage.
row = {'start': stamp(3), 'request_times': [(stamp(3), 0.1, 0, 1)]}
assert '2026-11-03 00:00' in render(claude, [row])
# Free Bob requests still consume context; missing cost is not measured zero.
row = {'id': 'free', 'start': stamp(3), 'task_cost': 0, '_models': [],
       'request_times': [({'spend': {'cost': 0, 'contextTokens': 10}}, int(stamp(3).timestamp() * 1000))]}
assert '2026-11-03 00:00' in render(bob, [row])
print('PASS: calendar windows, defaults, zero/unknown days, ratios, DST and rolling hours')
PY
