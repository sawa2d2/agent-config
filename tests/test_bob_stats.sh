#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" TZ=UTC
fail() { echo "FAIL: $*" >&2; exit 1; }
rows() { grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2} '; } # week rows, after the legend and header

[[ $("$root/bin/bob-stats" 2>&1) == 'bob-stats: database not found: '* ]] || fail 'missing database'

# Subset of Bob Shell's schema (observed in 2.0.9). Tasks a and d were created now, c a week
# ago, b on 2026-01-01 (week of 2025-12-29). Subagent s of a was created a week ago but counts
# in a's cost (as Bob records it) and week; subtask t of a is a task of its own. d has no
# recorded cost, so its messages' spend stands in. a and d record premium-ide, t another model,
# and the rest no model; a was compacted once, which stored a summary message without spend.
mkdir -p "$HOME/.bob/db"
DB="$HOME/.bob/db/bob.db" python3 - <<'PY'
import json, os, sqlite3, time
db = sqlite3.connect(os.environ["DB"])
db.executescript("""
CREATE TABLE tasks (id TEXT PRIMARY KEY, parent_id TEXT, costs TEXT, created_at INTEGER NOT NULL,
  task_type TEXT NOT NULL DEFAULT 'normal', env TEXT);
CREATE TABLE messages (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, role TEXT NOT NULL, data TEXT NOT NULL,
  created_at INTEGER NOT NULL);
""")
now = int(time.time() * 1000)
week = 7 * 86400000
def task(id, created, cost, parent=None, type="normal", model=None):
    costs = None if cost is None else json.dumps({"cost": cost, "contextTokens": 0})
    env = json.dumps({"id": id, **({"model": model} if model else {})})
    db.execute("INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?)", (id, parent, costs, created, type, env))
premium = {"id": "premium-ide", "contextWindow": 270000, "maxOutputTokens": 64000}
task("a", now, 0.6, model=premium)
task("b", 1767225600000, 0.05)
task("c", now - week, 0.8)
task("d", now, None, model=premium)
task("s", now - week, 0.2, "a", "subagent")
task("t", now, 1.0, "a", "subtask", model={"id": "other", "contextWindow": 128000})
def message(id, task, role, meta):
    db.execute("INSERT INTO messages VALUES (?, ?, ?, ?, 0)", (id, task, role, json.dumps({"_meta": meta})))
message("a1", "a", "assistant", {"spend": {"cost": 0.1, "contextTokens": 1000}})
message("a2", "a", "assistant", {"spend": {"cost": 0.3, "contextTokens": 3000}})
message("a3", "a", "user", {"spend": {"cost": 9, "contextTokens": 9}})
message("a4", "a", "assistant", {})
message("a5", "a", "assistant", {"notAi": True, "summary": True})
message("b1", "b", "assistant", {"spend": {"cost": 0.05, "contextTokens": 500}})
message("c1", "c", "assistant", {"spend": {"cost": 0.8, "contextTokens": 1000}})
message("d1", "d", "assistant", {"spend": {"cost": 0.2, "contextTokens": 1000}})
message("s1", "s", "assistant", {"spend": {"cost": 0.2, "contextTokens": 2000}})
message("t1", "t", "assistant", {"spend": {"cost": 1.0, "contextTokens": 102000}})
db.commit()
PY

monday=$(date -d "-$(( $(date +%u) - 1 )) days" +%F)
# By default the last 10 weeks show; only assistant messages with spend count.
# This week's row shows cost and cost per request as a percentage of last week's, even when -w 1 hides it,
# then the median, 90th percentile and maximum of the task costs 0.2 (d), 0.6 (a and s) and 1.0 (t).
out=$("$root/bin/bob-stats")
grep -Fqx 'per req  = cost / requests' <<< "$out" || fail "legend: $out"
grep -Fqx 'task p50, task p90, task max' <<< "$out" || fail "legend: $out"
grep -Eqx "$monday +3 +5 +21,800 +1.80 +0.360 +225.0% +45.0% +0.60 +0.92 +1.00" <<< "$out" || fail "this week: $out"
# The second table: context per request 1,000 1,000 2,000 3,000 102,000 this week, one of five
# requests and 102,000 of 109,000 tokens over 100k, and a's compaction; 1,000 last week.
grep -Fqx 'compacts = compactions (summary messages Bob stores when it compacts)' <<< "$out" || fail "legend: $out"
grep -Eqx "$monday +2,000 +62,400 +102,000 +20.0% +93.6% +1" <<< "$out" || fail "context this week: $out"
grep -Eqx "$(date -d "$monday -7 days" +%F) +1,000 +1,000 +1,000 +0.0% +0.0% +0" <<< "$out" || fail "context last week: $out"
# Models of the tasks in the weeks shown (b is older).
grep -Fqx 'model: premium-ide, contextWindow 270,000 (tasks: 2)' <<< "$out" || fail "model: $out"
grep -Fqx 'model: other, contextWindow 128,000 (tasks: 1)' <<< "$out" || fail "model: $out"
grep -Fqx 'model: not recorded (tasks: 2)' <<< "$out" || fail "model: $out"
[[ $(rows <<< "$out") == 4 ]] || fail "default weeks: $out"
out1=$("$root/bin/bob-stats" -w 1)
[[ $(rows <<< "$out1") == 2 ]] || fail "-w 1 rows: $out1"
grep -Fx "$(grep -m1 "^$monday" <<< "$out")" <<< "$out1" >/dev/null || fail "ratio with -w 1: $out1"
grep -Fqx 'model: not recorded (tasks: 1)' <<< "$out1" || fail "-w 1 model: $out1"
# -w 0 shows every week.
out=$("$root/bin/bob-stats" -w 0)
grep -Eqx '2025-12-29 +1 +1 +500 +0.05 +0.050 +- +- +0.05 +0.05 +0.05' <<< "$out" || fail "all weeks: $out"
grep -Eqx '2025-12-29 +500 +500 +500 +0.0% +0.0% +0' <<< "$out" || fail "all weeks: $out"
[[ $(rows <<< "$out") == 6 ]] || fail "all weeks: $out"
grep -Fqx 'model: not recorded (tasks: 3)' <<< "$out" || fail "all weeks model: $out"

# --window 5h: consecutive windows ending now, each request in the window of its message's
# created_at. Task e, created 7 hours ago, has a request then and one plus a compaction an hour
# ago; its task cost columns show the whole task's recorded cost. Older messages (created_at 0)
# fall outside the two windows shown.
DB="$HOME/.bob/db/bob.db" python3 - <<'PY'
import json, os, sqlite3, time
db = sqlite3.connect(os.environ["DB"])
now = int(time.time() * 1000)
hour = 3600000
db.execute("INSERT INTO tasks VALUES ('e', NULL, ?, ?, 'normal', NULL)", (json.dumps({"cost": 0.6}), now - 7 * hour))
for id, created, meta in [("e1", now - 7 * hour, {"spend": {"cost": 0.5, "contextTokens": 5000}}),
                          ("e2", now - hour, {"spend": {"cost": 0.1, "contextTokens": 1000}}),
                          ("e3", now - hour, {"summary": True})]:
    db.execute("INSERT INTO messages VALUES (?, 'e', 'assistant', ?, ?)", (id, json.dumps({"_meta": meta}), created))
db.commit()
PY
out=$("$root/bin/bob-stats" --window 5h -w 2)
grep -Eq '^start +tasks ' <<< "$out" || fail "window header: $out"
grep -Fq 'start    = start (local time) of each 5h window, the last ending now; each' <<< "$out" || fail "window legend: $out"
[[ $(rows <<< "$out") == 4 ]] || fail "window rows: $out"
grep -Eqx '[0-9-]{10} [0-9]{2}:[0-9]{2} +1 +1 +5,000 +0.50 +0.500 +- +- +0.60 +0.60 +0.60' <<< "$out" || fail "previous window: $out"
grep -Eqx '[0-9-]{10} [0-9]{2}:[0-9]{2} +1 +1 +1,000 +0.10 +0.100 +20.0% +20.0% +0.60 +0.60 +0.60' <<< "$out" || fail "current window: $out"
grep -Eqx '[0-9-]{10} [0-9]{2}:[0-9]{2} +1,000 +1,000 +1,000 +0.0% +0.0% +1' <<< "$out" || fail "context current window: $out"

echo 'PASS: bob-stats'
