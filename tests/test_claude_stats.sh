#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export CLAUDE_CONFIG_DIR="$tmp/claude"
fail() { echo "FAIL: $*" >&2; exit 1; }
rows() { grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2} '; } # week rows, after the legend and header
stats() { "$root/bin/aistats" claude --window week "$@"; }

# Session a: two requests, the first logged twice under one requestId (one line per content block).
mkdir -p "$CLAUDE_CONFIG_DIR/projects/-home-a" "$CLAUDE_CONFIG_DIR/projects/-home-b"
cat > "$CLAUDE_CONFIG_DIR/projects/-home-a/a.jsonl" <<'EOF'
{"type":"user","timestamp":"2026-01-01T00:00:00Z","message":{"role":"user","content":"hi"}}
{"type":"assistant","timestamp":"2026-01-01T00:00:01Z","requestId":"r1","message":{"id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_creation":{"ephemeral_1h_input_tokens":40},"cache_read_input_tokens":1000,"output_tokens":20}}}
{"type":"assistant","timestamp":"2026-01-01T00:00:02Z","requestId":"r1","message":{"id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":100,"cache_creation":{"ephemeral_1h_input_tokens":40},"cache_read_input_tokens":1000,"output_tokens":20}}}
{"type":"assistant","timestamp":"2026-01-01T00:00:03Z","requestId":"r2","message":{"id":"m2","usage":{"input_tokens":5,"cache_read_input_tokens":2000,"output_tokens":11}}}
EOF
# Session b: one request without requestId (keyed by message id), plus lines to skip.
cat > "$CLAUDE_CONFIG_DIR/projects/-home-b/b.jsonl" <<'EOF'
not json
{"type":"summary","summary":"no usage"}
{"type":"assistant","timestamp":"2026-03-01T00:00:00Z","message":{"id":"m3","usage":{"input_tokens":1,"output_tokens":1}}}
EOF

# --json prints one deduplicated row per session, oldest first.
a='{"path": "'"$CLAUDE_CONFIG_DIR"'/projects/-home-a/a.jsonl", "start": "2026-01-01T00:00:00+00:00", "requests": 2, "input": 15, "cache_write": 100, "cache_read": 3000, "output": 31, "total": 3146, "weighted": 625, "total_per_request": 1573}'
b='{"path": "'"$CLAUDE_CONFIG_DIR"'/projects/-home-b/b.jsonl", "start": "2026-03-01T00:00:00+00:00", "requests": 1, "input": 1, "cache_write": 0, "cache_read": 0, "output": 1, "total": 2, "weighted": 6, "total_per_request": 2}'
[[ $(stats --json) == "$a"$'\n'"$b" ]] || fail "json: $(stats --json)"

# Filters.
[[ $(stats --json --project=-home-a) == "$a" ]] || fail 'project'
[[ $(stats --json --min-requests 2) == "$a" ]] || fail 'min-requests'
[[ $(stats --json --since 2026-02-01T00:00:00Z) == "$b" ]] || fail 'since'
[[ $(stats --json --until 2026-02-01T00:00:00Z) == "$a" ]] || fail 'until'

# A split reports mean, stdev and median per metric for each group.
out=$(stats --split 2100-01-01T00:00:00Z)
grep -qx 'before: 2 sessions' <<< "$out" || fail "before: $out"
grep -Eqx ' +requests +requests +2 +1 +2' <<< "$out" || fail "requests row: $out"
grep -Eqx ' +weighted +tokens +316 +438 +316' <<< "$out" || fail "weighted row: $out"
! grep -Eq '^ +total ' <<< "$out" || fail "total row: $out"
grep -qx 'values are per session' <<< "$out" || fail "split legend: $out"

# --split and --split-commit divide sessions into before/after.
out=$(stats --split 2026-02-01T00:00:00Z)
grep -qx 'before: 1 sessions' <<< "$out" && grep -qx 'after: 1 sessions' <<< "$out" || fail "split: $out"
git -C "$tmp" init -q repo
GIT_COMMITTER_DATE=2026-02-01T00:00:00Z git -C "$tmp/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m c
out=$(stats --split-commit HEAD --repo "$tmp/repo")
grep -q '^split at 2026-02-01T00:00:00' <<< "$out" && grep -qx 'after: 1 sessions' <<< "$out" || fail "split-commit: $out"

# -w 0 sums every week, grouping sessions by the local Monday of their start week,
# with cache_read per request and cache_read/cache_write.
out=$(TZ=UTC stats -w 0)
grep -Eqx '2025-12-29 +1 +2 +625 +31[23] +- +- +1,500 +30.0' <<< "$out" || fail "weekly a: $out"
grep -Eqx '2026-02-23 +1 +1 +6 +6 +- +- +0 +-' <<< "$out" || fail "weekly b: $out"
[[ $(TZ=Asia/Tokyo stats --weeks 0 --until 2026-02-01T00:00:00Z | tail -n1) == 2025-12-29* ]] || fail 'weekly local time'
# --since/--until without -w show every week in range, not only the last 10.
[[ $(TZ=UTC stats --until 2026-02-01T00:00:00Z | tail -n1) == 2025-12-29* ]] || fail 'until shows old weeks'

# With --window week only the last 10 weeks show: the old sessions drop out, ones started now and a week ago stay.
# This week's row shows its ratio to last week's, even when -w 1 hides last week.
printf '%s\n' '{"type":"assistant","timestamp":"'"$(date -u +%FT%TZ)"'","requestId":"r3","message":{"id":"m4","usage":{"input_tokens":1,"output_tokens":1}}}' \
  > "$CLAUDE_CONFIG_DIR/projects/-home-b/c.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"'"$(date -u -d '-7 days' +%FT%TZ)"'","requestId":"r4","message":{"id":"m5","usage":{"input_tokens":2,"output_tokens":2}}}' \
  > "$CLAUDE_CONFIG_DIR/projects/-home-b/d.jsonl"
monday=$(date -d "-$(( $(date +%u) - 1 )) days" +%F)
out=$(stats)
[[ $(rows <<< "$out") == 2 ]] || fail "default weeks: $out"
grep -Fqx 'per req  = weighted / requests [tokens]' <<< "$out" || fail "legend: $out"
grep -Eqx "$monday +1 +1 +6 +6 +50.0% +50.0% +[0-9,]+ +[0-9.-]+" <<< "$out" || fail "ratio: $out"
[[ $(stats -w 1 | rows) == 1 ]] || fail "-w 1 rows"
[[ $(stats -w 1 | tail -n1) == "$(tail -n1 <<< "$out")" ]] || fail "ratio with -w 1: $(stats -w 1)"
[[ $(stats -w 0 | rows) == 4 ]] || fail 'all weeks'

# --window 5h: consecutive windows ending now, each request in the window of its timestamp.
# Session e has one request 7 hours ago and one an hour ago, so it counts in both windows.
{
  printf '%s\n' '{"type":"assistant","timestamp":"'"$(date -u -d '-7 hours' +%FT%TZ)"'","requestId":"r5","message":{"id":"m6","usage":{"input_tokens":100}}}'
  printf '%s\n' '{"type":"assistant","timestamp":"'"$(date -u -d '-1 hour' +%FT%TZ)"'","requestId":"r6","message":{"id":"m7","usage":{"input_tokens":10,"output_tokens":2}}}'
} > "$CLAUDE_CONFIG_DIR/projects/-home-b/e.jsonl"
out=$(stats --window 5h -w 2)
grep -Eq '^start +sessions ' <<< "$out" || fail "window header: $out"
grep -Fqx 'vs prev  = this window / previous window * 100 [%] (-: no previous window, or it was 0)' <<< "$out" || fail "window legend: $out"
grep -Fq 'start    = start (local time) of each 5h window, the last ending now; each' <<< "$out" || fail "window legend: $out"
[[ $(rows <<< "$out") == 2 ]] || fail "window rows: $out"
grep -Eqx '[0-9-]{10} [0-9]{2}:[0-9]{2} +1 +1 +100 +100 +- +- +[0-9,]+ +[0-9.-]+' <<< "$out" || fail "previous window: $out"
grep -Eqx '[0-9-]{10} [0-9]{2}:[0-9]{2} +2 +2 +26 +13 +26.0% +13.0% +[0-9,]+ +[0-9.-]+' <<< "$out" || fail "current window: $out"
[[ $(stats --window 5h -w 1 | tail -n1) == "$(tail -n1 <<< "$out")" ]] || fail "window -w 1: $(stats --window 5h -w 1)"
! stats --window 5x 2>/dev/null || fail 'invalid window'

echo 'PASS: aistats claude'
