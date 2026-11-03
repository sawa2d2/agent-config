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
# recorded cost, so its messages' spend stands in.
mkdir -p "$HOME/.bob/db"
DB="$HOME/.bob/db/bob.db" python3 - <<'PY'
import json, os, sqlite3, time
db = sqlite3.connect(os.environ["DB"])
db.executescript("""
CREATE TABLE tasks (id TEXT PRIMARY KEY, parent_id TEXT, costs TEXT, created_at INTEGER NOT NULL,
  task_type TEXT NOT NULL DEFAULT 'normal');
CREATE TABLE messages (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, role TEXT NOT NULL, data TEXT NOT NULL,
  created_at INTEGER NOT NULL);
""")
now = int(time.time() * 1000)
week = 7 * 86400000
def task(id, created, cost, parent=None, type="normal"):
    costs = None if cost is None else json.dumps({"cost": cost, "contextTokens": 0})
    db.execute("INSERT INTO tasks VALUES (?, ?, ?, ?, ?)", (id, parent, costs, created, type))
task("a", now, 0.6)
task("b", 1767225600000, 0.05)
task("c", now - week, 0.8)
task("d", now, None)
task("s", now - week, 0.2, "a", "subagent")
task("t", now, 1.0, "a", "subtask")
def message(id, task, role, meta):
    db.execute("INSERT INTO messages VALUES (?, ?, ?, ?, 0)", (id, task, role, json.dumps({"_meta": meta})))
message("a1", "a", "assistant", {"spend": {"cost": 0.1, "contextTokens": 1000}})
message("a2", "a", "assistant", {"spend": {"cost": 0.3, "contextTokens": 3000}})
message("a3", "a", "user", {"spend": {"cost": 9, "contextTokens": 9}})
message("a4", "a", "assistant", {})
message("b1", "b", "assistant", {"spend": {"cost": 0.05, "contextTokens": 500}})
message("c1", "c", "assistant", {"spend": {"cost": 0.8, "contextTokens": 1000}})
message("d1", "d", "assistant", {"spend": {"cost": 0.2, "contextTokens": 1000}})
message("s1", "s", "assistant", {"spend": {"cost": 0.2, "contextTokens": 2000}})
message("t1", "t", "assistant", {"spend": {"cost": 1.0, "contextTokens": 2000}})
db.commit()
PY

monday=$(date -d "-$(( $(date +%u) - 1 )) days" +%F)
# By default the last 10 weeks show; only assistant messages with spend count.
# This week's row shows cost and cost per request as a percentage of last week's, even when -w 1 hides it,
# then the median, 90th percentile and maximum of the task costs 0.2 (d), 0.6 (a and s) and 1.0 (t).
out=$("$root/bin/bob-stats")
[[ $(rows <<< "$out") == 2 ]] || fail "default weeks: $out"
grep -Fqx 'per req  = cost / requests' <<< "$out" || fail "legend: $out"
grep -Fqx 'task p50, task p90, task max' <<< "$out" || fail "legend: $out"
grep -Eqx "$monday +3 +5 +1,800 +1.80 +0.360 +225.0% +45.0% +0.60 +0.92 +1.00" <<< "$out" || fail "this week: $out"
[[ $("$root/bin/bob-stats" -w 1 | rows) == 1 ]] || fail "-w 1 rows"
[[ $("$root/bin/bob-stats" -w 1 | tail -n1) == "$(tail -n1 <<< "$out")" ]] || fail 'ratio with -w 1'
# -w 0 shows every week.
out=$("$root/bin/bob-stats" -w 0)
grep -Eqx '2025-12-29 +1 +1 +500 +0.05 +0.050 +- +- +0.05 +0.05 +0.05' <<< "$out" || fail "all weeks: $out"
[[ $(rows <<< "$out") == 3 ]] || fail "all weeks: $out"

echo 'PASS: bob-stats'
