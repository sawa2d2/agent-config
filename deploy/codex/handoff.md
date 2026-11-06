# Codex budget and context handoff support

Checked against installed `codex-cli 0.160.0` and official documentation on
2026-11-03. All local CLI probes and installation tests use temporary HOME
and CODEX_HOME directories; no real session or credentials are required.

## Implemented boundary

`scripts/codex-handoff-suggest` handles `PreCompact` with `trigger: "auto"`.
It returns only `systemMessage`, a UI warning offering a handoff after
compaction. Manual compaction and other events produce no output. Each
automatic compaction can show a warning; no persistent session tracking is
needed. The installer preserves unmanaged hooks and is idempotent.

The warning does not claim that any fixed percentage or budget has been
reached. Codex decides when to compact using its model/configuration.
`model_auto_compact_token_limit` is a compaction threshold, not a spend cap;
we do not change it or `model_context_window`.

`PreCompact` supports a UI warning but does not document model-visible
`additionalContext`. Returning `continue: false` would stop compaction;
we deliberately omit it. A hook cannot make the model write a note before
this boundary simply by returning instructions. The script neither writes
a fabricated handoff note nor starts another session.

After compaction, ask the agent to use the handoff skill to write
`.agent-handoff.md`. To continue with a fresh conversation, exit normally
and run in the same worktree:

```sh
codex new '$takeover'
```

The `takeover` skill reads the note, checks the recorded state against the
repository and continues. Its description also matches the plain prompt
that `codex-delegate` sends to continue from a moved note.

`codex new` is this repository's wrapper syntax. `codex resume` continues
the old conversation; `fork` retains earlier conversation history. Neither
is a replacement for starting a fresh session from a handoff note.

## Why Bob's budget automation is not copied

| Existing Bob behavior | Codex evidence and outcome |
| --- | --- |
| `session.maxCost` in Bobcoins; warnings at 80% | No equivalent normal-session Bobcoin cap is established by Codex CLI help or the official configuration reference. No currency conversion or invented setting. |
| `bob-handoff-suggest` reads task costs and context size, and warns at half the cap or above a token threshold on `UserPromptSubmit` | Codex's documented prompt hook has no spend or context-remaining fields. We do not parse internal transcripts, whose format the hook docs call unstable. |
| `bin/bob` detects a task reaching its cost cap after exit and offers `bobtask handoff` | No equivalent normal-session cap-exit contract was established. `bin/codex` keeps its existing exec/session control; no exit-code interpretation or automatic restart is added. |
| Fresh Bob task reads the handoff note or a compact transcript | Codex can start with a prompt pointing to the shared handoff note. No transcript export or database access is needed. |

## Actual usage signals

`codex app-server generate-ts --out <temporary-directory>` on 0.160.0 exposes:

- `HookEventName`: includes `preCompact` and `postCompact`; does not include
  `preModelRequest` or `postModelRequest` in this installed version.
- `ThreadTokenUsage`: `total`, `last`, and nullable `modelContextWindow`.
  App Server publishes `thread/tokenUsage/updated`; these are protocol
  notifications, not fields automatically passed to a command hook.
- `RateLimitWindow`: `usedPercent`, nullable `windowDurationMins` and
  `resetsAt`. Account quota windows are not a per-session spending cap.
- `ThreadGoal`: nullable `tokenBudget` and `tokensUsed`. An explicit goal's
  token budget is distinct from an arbitrary interactive session or Bob's
  currency limit; this integration does not create or alter goals.

Current hook documentation also describes `PostModelRequest.token_usage`
(nullable per-attempt counts), with diagnostic-only output. This event is
absent from the installed CLI's generated hook enum, so this implementation
does not register it. Summing request input counts would include repeated
context and would not measure context remaining or establish billed cost.

## Sources and verification limits

- [Official hooks reference](https://learn.chatgpt.com/docs/hooks): event
  payloads, `auto`/`manual` matchers, UI output, trust, and transcript stability.
- [Official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference):
  compaction and context settings.
- [Official App Server reference](https://learn.chatgpt.com/docs/app-server):
  protocol usage notifications.
- Local evidence: `codex --version`, `codex --help`, and generated App Server
  types, all with temporary HOME/CODEX_HOME.

Fixture tests cover hook output, ignored inputs, installer preservation and
idempotence. A temporary App Server `hooks/list` probe also confirmed the
installed CLI recognizes the `auto` PreCompact hook without errors and keeps
its trust status `untrusted`. These checks do not claim a live model reached compaction, wrote a note,
or continued successfully. No token savings or billing outcome was measured.
