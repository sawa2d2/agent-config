#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export CODEX_HOME="$tmp/codex" TZ=UTC
fail() { echo "FAIL: $*" >&2; exit 1; }
rows() { grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2} '; } # week rows, after the legend and header
stats() { "$root/bin/ai-stats" codex "$@"; }
record() { # timestamp response_id input cached output
  printf '{"timestamp":"%s","type":"token_usage_record","payload":{"response_id":"%s","usage":{"input_tokens":%d,"cached_input_tokens":%d,"cache_write_input_tokens":0,"output_tokens":%d,"reasoning_output_tokens":0,"total_tokens":%d}}}\n' \
    "$1" "$2" "$3" "$4" "$5" $(($3 + $5))
}

# Rollout lines observed in codex-cli 0.160.0. Session a: two responses, one logged twice,
# plus token_count events (which repeat the same usage) and lines to skip.
mkdir -p "$CODEX_HOME/sessions/2026/01/01" "$CODEX_HOME/archived_sessions"
{
  echo '{"timestamp":"2026-01-01T00:00:00Z","type":"session_meta","payload":{"id":"a"}}'
  record 2026-01-01T00:00:01Z r1 1000 800 20
  record 2026-01-01T00:00:01Z r1 1000 800 20
  echo '{"timestamp":"2026-01-01T00:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"output_tokens":20,"total_tokens":1020}}}}'
  echo 'not json'
  record 2026-01-01T00:00:02Z r2 500 400 10
} > "$CODEX_HOME/sessions/2026/01/01/rollout-a.jsonl"
# Archived session b in the same week; session e without responses is skipped.
record 2026-01-02T00:00:00Z r3 100 0 5 > "$CODEX_HOME/archived_sessions/rollout-b.jsonl"
echo '{"timestamp":"2026-01-03T00:00:00Z","type":"session_meta","payload":{"id":"e"}}' \
  > "$CODEX_HOME/archived_sessions/rollout-e.jsonl"

# Week of 2025-12-29: 3 requests; weighted 800 = 400 uncached + 1,200 * 0.1 cached + 35 * 8 output.
out=$(stats -w 0)
grep -Eqx '2025-12-29 +2 +3 +800 +267 +- +-' <<< "$out" || fail "all weeks: $out"
[[ $(rows <<< "$out") == 1 ]] || fail "all weeks: $out"
[[ $(TZ=Asia/Tokyo stats -w 0 | tail -n1) == 2025-12-29* ]] || fail 'weekly local time'

# By default only the last 10 weeks show; this week's row shows its ratio to last week's,
# even when -w 1 hides last week.
mkdir -p "$CODEX_HOME/sessions/now"
record "$(date -u +%FT%TZ)" r4 10 0 0 > "$CODEX_HOME/sessions/now/rollout-c.jsonl"
record "$(date -u -d '-7 days' +%FT%TZ)" r5 20 0 0 > "$CODEX_HOME/sessions/now/rollout-d.jsonl"
monday=$(date -d "-$(( $(date +%u) - 1 )) days" +%F)
out=$(stats)
[[ $(rows <<< "$out") == 2 ]] || fail "default weeks: $out"
grep -Fqx 'per req  = weighted / requests [tokens]' <<< "$out" || fail "legend: $out"
grep -Eqx "$monday +1 +1 +10 +10 +50.0% +50.0%" <<< "$out" || fail "ratio: $out"
[[ $(stats -w 1 | rows) == 1 ]] || fail "-w 1 rows"
[[ $(stats -w 1 | tail -n1) == "$(tail -n1 <<< "$out")" ]] || fail "ratio with -w 1: $(stats -w 1)"
[[ $(stats -w 0 | rows) == 3 ]] || fail 'all weeks'

# --window 5h: consecutive windows ending now, each response in the window of its timestamp.
# Session f has one response 7 hours ago and one an hour ago, so it counts in both windows.
{
  record "$(date -u -d '-7 hours' +%FT%TZ)" r6 100 0 0
  record "$(date -u -d '-1 hour' +%FT%TZ)" r7 10 0 0
} > "$CODEX_HOME/sessions/now/rollout-f.jsonl"
out=$(stats --window 5h -w 2)
grep -Eq '^start +sessions ' <<< "$out" || fail "window header: $out"
grep -Fq 'start    = start (local time) of each 5h window, the last ending now; each' <<< "$out" || fail "window legend: $out"
[[ $(rows <<< "$out") == 2 ]] || fail "window rows: $out"
grep -Eqx '[0-9-]{10} [0-9]{2}:[0-9]{2} +1 +1 +100 +100 +- +-' <<< "$out" || fail "previous window: $out"
grep -Eqx '[0-9-]{10} [0-9]{2}:[0-9]{2} +2 +2 +20 +10 +20.0% +10.0%' <<< "$out" || fail "current window: $out"
! stats --window 0h 2>/dev/null || fail 'invalid window'

echo 'PASS: ai-stats codex'
