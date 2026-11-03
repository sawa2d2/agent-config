#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" TZ=UTC
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ $("$root/bin/bob-stats" 2>&1) == 'bob-stats: database not found: '* ]] || fail 'missing database'

# Subset of Bob Shell's schema (observed in 2.0.6). Task a was created now, c a week ago,
# b on 2026-01-01 (week of 2025-12-29).
mkdir -p "$HOME/.bob/db"
DB="$HOME/.bob/db/bob.db" python3 - <<'PY'
import json, os, sqlite3, time
db = sqlite3.connect(os.environ["DB"])
db.executescript("""
CREATE TABLE tasks (id TEXT PRIMARY KEY, created_at INTEGER NOT NULL);
CREATE TABLE messages (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, role TEXT NOT NULL, data TEXT NOT NULL,
  created_at INTEGER NOT NULL);
""")
now = int(time.time() * 1000)
db.executemany("INSERT INTO tasks VALUES (?, ?)", [("a", now), ("b", 1767225600000), ("c", now - 7 * 86400000)])
def message(id, task, role, meta):
    db.execute("INSERT INTO messages VALUES (?, ?, ?, ?, 0)", (id, task, role, json.dumps({"_meta": meta})))
message("a1", "a", "assistant", {"spend": {"cost": 0.1, "contextTokens": 1000}})
message("a2", "a", "assistant", {"spend": {"cost": 0.3, "contextTokens": 3000}})
message("a3", "a", "user", {"spend": {"cost": 9, "contextTokens": 9}})
message("a4", "a", "assistant", {})
message("b1", "b", "assistant", {"spend": {"cost": 0.05, "contextTokens": 500}})
message("c1", "c", "assistant", {"spend": {"cost": 0.8, "contextTokens": 1000}})
db.commit()
PY

monday=$(date -d "-$(( $(date +%u) - 1 )) days" +%F)
# By default the last 10 weeks show; only assistant messages with spend count.
# This week's row shows cost and cost per request as a percentage of last week's, even when -w 1 hides it.
out=$("$root/bin/bob-stats")
[[ $(wc -l <<< "$out") == 3 ]] || fail "default weeks: $out"
grep -Eqx "$monday +1 +2 +4,000 +0.40 +2,000 +0.200 +50.0% +25.0%" <<< "$out" || fail "this week: $out"
[[ $("$root/bin/bob-stats" -w 1 | tail -n +2) == "$(tail -n1 <<< "$out")" ]] || fail 'ratio with -w 1'
# -w 0 shows every week.
out=$("$root/bin/bob-stats" -w 0)
grep -Eqx '2025-12-29 +1 +1 +500 +0.05 +500 +0.050 +- +-' <<< "$out" || fail "all weeks: $out"
[[ $(wc -l <<< "$out") == 4 ]] || fail "all weeks: $out"

echo 'PASS: bob-stats'
