# Claude Code 1-hour cache writes

Assessment of the week starting 2026-11-02 (JST), Claude Code 2.1.289, from
`~/.claude/projects/**/*.jsonl` (85 transcripts, about 2,500 requests). Weighted
as in `ai-stats claude`: 1-hour cache writes were 29% of weighted tokens, cache
reads 53%, output 18%, 5-minute writes and uncached input about 0%.

## Method

Requests were deduplicated by `requestId` and compared with the previous
request in the same transcript. If a request read fewer cached tokens than the
previous request had read plus written (by more than 1024), the difference was
counted as a rewritten prefix and attributed to the first matching cause:
`compact_boundary` since the previous request, a gap over one hour, a model
change, or otherwise a prefix break. The rest of each write is growth: new
messages appended after a cached prefix.

## Share of 1-hour cache writes

| Cause | Share | Requests | Notes |
| --- | ---: | ---: | --- |
| Growth, tool loop steps | 45% | 1960 | about 1.3k tokens per step: the previous output plus the tool result |
| Resume after more than 1 h idle | 28% | 17 | 20k–150k tokens each, gaps 1.1–168 h (median about 5 h) |
| Session start | 11% | 65 | about 10k each; the first ~11.7k–25k tokens were read from a cache shared across sessions |
| Growth, user prompt turns | 5% | 377 | prompt plus reminders, about 0.7k each |
| Growth, second request of a session | 4% | 53 | about 3.6k each |
| Compaction | 5% | 11 | the summary is a new prefix |
| Prefix lost within an hour | 3% | 3 | see below |
| Model or settings switch | 0% | 0 | |
| Subagents and delegate sessions | — | — | no subagent transcripts this week; delegate sessions are counted as session starts |

No prefix break happened within five minutes of the previous request. The
hooks this repository installs (`agent-tmux-status`, `agent-approval-marker`,
`rtk hook claude`) and Claude Code's own reminders and attachments (skill and
deferred-tool lists, `total_tokens_reminder`, date) are appended after the
cached prefix, so they cost only their own size as growth. The only
`hook_additional_context` came from a plugin's `SessionStart` hook, not from
this repository.

The resumes after idle were all long-lived sessions in primary checkouts
(`~/agent-config`, `~/dotfiles`, `~/local-ai` and similar) continued hours or
days later. Each rewrote the whole conversation at the 2x price.

## Unverified

- The three prefix losses within an hour (gaps of 16–56 min, 2026-11-03 14:17–14:47
  UTC, three different sessions) kept only the shared system prefix, and
  each was followed by a `thinking_drop` attachment with reason
  `prefix_mismatch` and `clientChange.kinds: "none"`. That suggests a
  server-side eviction rather than a client change, but neither cause can be
  confirmed from transcripts.
- Whether Claude Code chooses the 1-hour TTL deliberately for every request
  is not documented in the transcripts; all writes this week were 1-hour.

## Recommendation

No repository change: none of the measurable causes comes from hooks,
wrappers or settings installed here. The avoidable part is the idle resume
(28%). When returning to a session after more than an hour, especially a
long one in a primary checkout, start a new session (`/clear`, or a handoff
note when work is unfinished) instead of continuing it. Resuming a 100k-token
context costs about 200k input-token equivalents in cache writes, while a new
session starts at about 10k. Growth is inherent to the tool loop and can only
be reduced by smaller tool outputs.
