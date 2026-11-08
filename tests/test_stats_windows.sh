#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
PYTHONPATH="$root/lib" python3 - <<'PY'
import os
import time
from datetime import date, datetime, timedelta
from unittest.mock import patch

from ai_stats import Windows, parse_time, window_spec


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
print('PASS: calendar windows, local midnight, DST and rolling hours')
PY
