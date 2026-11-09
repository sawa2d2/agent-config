# Agent usage statistics

`aistats claude|bob|codex` is the sole CLI, with the same options for all
three agents. It replaces the former individual stats commands:

```sh
aistats codex --since 2026-10-01 --until 2026-11-01
aistats bob --project agent-config --min-requests 3 --json
aistats claude --split-commit HEAD~3 --repo .
aistats codex --split 2026-11-01T00:00Z
aistats bob --window 5h -w 6
```

Select any agent with `aistats claude|bob|codex`; all options in these
examples work with all three agents.

- `--since TIME` includes sessions starting at that time; `--until TIME`
  excludes sessions starting at that time. ISO dates and date-times without an
  offset use local time. These select whole sessions, not individual requests.
- `--project TEXT` matches a substring of Claude's transcript directory,
  Codex's recorded `cwd`, or Bob's task `directory`. `--repo` only selects the
  Git repository used by `--split-commit`; it is not a project filter.
- `--min-requests N` selects sessions with at least N requests (default 1).
- `--split TIME` and `--split-commit REF` are mutually exclusive. They compare
  per-session mean, sample standard deviation, and median before/after the
  cutoff. A session starting exactly at the cutoff is in the after group.
- `--window` defaults to `1day` (`1d`): one local calendar day, with requests
  grouped by their timestamps. `Nday` is an alias for `Nd`.
  `--window week` groups whole sessions by their start week's local Monday.
  Explicit lengths group requests by timestamp; a session may occur in several
  windows. `1d` means today, starting at local 00:00. `Nd` uses consecutive
  N-date windows, the newest ending tomorrow at local 00:00 (so `2d` includes
  yesterday and today). `1w` and `1week` mean the current Monday-to-Monday week;
  `Nw`/`Nweek` use N-week windows ending next Monday at local 00:00. These
  calendar windows include their start and exclude their end; a request exactly
  at midnight belongs to the new date/week. The current window is incomplete.
  Local calendar boundaries remain at midnight across daylight-saving changes,
  so a day may contain 23 or 25 hours. `week` retains whole-session grouping,
  while `1w`/`1week` group individual requests.
  Hour lengths such as `5h` retain consecutive fixed-duration windows ending
  at the current time, including the existing end-inclusive boundary behavior.
  Use `24h` for a rolling 24-hour window instead of the calendar-date `1d`.
- Daily (`1day`/`1d`) displays omit days whose usage is known to be zero, as
  well as days with no requests. Claude uses unrounded weighted tokens; Codex
  requires every recorded token metric to be zero; Bob requires both message
  cost and context tokens to be zero. Missing measurements remain unknown and
  retain the day. Ratios compare against the previous retained day, skipping
  gaps and zero days; an unknown baseline produces no ratio. Requests on a
  retained day still all contribute to its per-request calculations. Explicit
  weekly, multi-day and hourly windows keep their existing aggregation and
  adjacent-window comparisons. JSON and per-session split statistics are unchanged.
- `-w`, `--windows`, and `--weeks` are aliases. Default: 10 windows, or all
  windows with `--since`/`--until`; 0 means all. The default therefore covers
  today and the previous nine dates, without extending the range for omitted
  days. The previous retained day (or adjacent window for other window lengths)
  remains available for ratios even when it is hidden.
- `--json` emits one JSON object per selected session, oldest first. It takes
  precedence over text comparisons and ignores display windows. An empty
  selection emits no lines. Argument validation still applies.

## Sources and interpretation

All reads are local. No provider API, model pricing lookup, or history mutation
is performed. There are no new dependencies. The common entry point in
`lib/ai_stats/__init__.py` owns argument validation,
filtering, sorting, JSON, split comparisons, and display selection. The
`lib/ai_stats/{claude,bob,codex}.py` modules provide source readers, window displays,
and split metric definitions. Keep `lib/` alongside `bin/`. Internal session
fields prefixed with `_` and `request_times` are excluded from JSON.

Claude reads `CLAUDE_CONFIG_DIR/projects/**/*.jsonl` (default `~/.claude`). Its
existing request-ID/message-ID deduplication and token/cache metrics are retained.
Claude's existing sparse cache fields are interpreted as zero. Its input count
excludes cache creation/read tokens; Codex's input count includes them, so these
fields must not be compared as if they had identical meanings.

Bob opens `~/.bob/db/bob.db` in read-only mode. A session is a budget-owning task;
subagents roll into that task, while independently budgeted subtasks remain
separate. Filters and splits use the budget owner's start time and directory.
The existing context percentiles, >100k shares, compaction counts, task cost
percentiles, and model/context-window lines remain available. Task cost
percentiles use the whole task's recorded cost, even in a request window; message
spend is the fallback when task cost is absent. JSON separates `task_cost` from
summed message `cost`. Missing spend measurements are unknown, not zero. Bob's
observed spend schema exposes only `cost` and `contextTokens`, not separate
input/cache/output/reasoning tokens. Model information comes from task metadata,
not a per-response model record. Bob's recorded cost is not an invoice.

Codex reads `CODEX_HOME/sessions` and `CODEX_HOME/archived_sessions` (default
`~/.codex`). Inspection of local rollouts found:

- `token_usage_record.payload.usage`: input, cached input, cache-write input,
  output, reasoning output, and total tokens; `response_id` and `thread_id`
  identify the response and its owner.
- `event_msg` / `token_count`: `last_token_usage`, `total_token_usage`, and
  `model_context_window`. Repeated events can report unchanged cumulative usage.
- `session_meta`: session ID, cwd, parent/fork/history metadata and start time;
  `turn_context`: model identifier.

The old Codex implementation discarded the detailed measurements and deduplicated
only within a file. Parent rollouts can also contain child responses. The new
implementation deduplicates response IDs across active/archive copies and
threads, and prefers the owning thread's model metadata. Copies with the same
session ID are merged; unique responses from a longer copy are retained. Child
threads remain separate sessions, with `parent_thread_id` when recorded. Missing
response IDs use owner, timestamp and usage to recognize exact copies; identical
responses without IDs cannot otherwise be distinguished reliably.

When an owner has no local rollout, its response is counted once in the available
rollout, with unknown model/window attribution. For files without response
records, the observed `token_count` schema is supported conservatively: count
last usage only when cumulative total advances; never sum cumulative counters.
A fork's first inherited counter is treated as a baseline. JSON identifies this
source and labels its request count as observed cumulative advances. Local
inspection found both record types together, not an event-only historical CLI
version; the event-only fixture uses the observed schema, not a claimed version.
A session with any response records uses those records exclusively. Gaps in
response recording, missing events, or truncated inherited history cannot be
reconstructed reliably and may undercount usage.

Codex JSON exposes raw token totals, models, unknown model/window request counts,
recorded context windows, and maximum input tokens. Input tokens are only a proxy
for context size. Reasoning is a component of output and is not added again.
Missing measurements produce JSON `null` and text `unknown`; missing model/window
lists are accompanied by explicit unknown counts. Aggregates are unknown if a
required component is missing. Empty sessions do not imply zero usage and are
omitted. Neither Codex token records nor Claude's weighted metrics establish
actual spend. The retained `weighted` columns use legacy fixed comparison weights,
not current or model-specific prices, and are not cross-provider cost estimates.

## Verification

```sh
git switch aistats-default-day
bash tests/run tests/test_claude_stats.sh tests/test_bob_stats.sh tests/test_codex_stats.sh tests/test_stats_parity.sh tests/test_shell_aliases.sh tests/test_stats_windows.sh
```

Expected: `6 passed, 0 failed`. Fixtures are synthetic, contain no conversation
content, and exercise CLI parity, filters, splits, JSON, copies, subagents,
cumulative events, missing fields, empty selections, local midnight boundaries,
daylight-saving transitions, default daily windows, zero-usage days, and
comparisons across inactive days.
