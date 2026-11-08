# Automatic Codex context handoff

Ordinary interactive `codex`, `codex new`, `codex resume`, and `codex fork`
launches enable automatic handoff. `codex auto-handoff` remains an explicit
alias. Headless/utility commands pass through. See [all three agents](../../docs/automatic-handoff.md)
for Claude Code and Bob Shell.

The integration targets installed `codex-cli 0.167.0`. Unknown versions,
profiles, remote endpoints and new worktrees continue through the native CLI
with an explicit automation-disabled warning; explicit `auto-handoff` fails
instead. Python's standard library is the only added dependency.

## Measurement and threshold

The launcher observes `thread/tokenUsage/updated` on its own TUI connection.
It uses **`tokenUsage.last.inputTokens`**, including cached input, as the latest
measured request context size. It never sums requests, adds cached input again,
or uses `total`, account quotas, monetary spend, or goal budgets. This is the
input to the last model request, not an exact live count of all messages and
tool results currently in memory. Output and newly appended tool results may
make the next request larger. Compaction can lower the next measurement.

The threshold is the smaller of **80,000 input tokens** and **80% of a known
positive `modelContextWindow`**. Without a window, the absolute threshold is
used; without valid input usage no handoff occurs. 80,000 leaves 20,000 tokens
before this repository's existing 100,000 auto-compaction setting, reserving
room for the handoff turn. This is a practical default, not a guarantee that
handoff precedes compaction: long turns may compact first. The launcher waits
for the turn to finish and uses the latest measurement, so it does not stop
tools or act on a pre-compaction high-water mark. It changes neither model
context settings nor the compaction threshold.

## Sequence and safety

1. The launcher owns a private Unix socket, an App Server process, and
   the TUI connected through `--remote unix://…`. It forwards protocol traffic
   unchanged, including approval requests and responses. Unix transport uses
   WebSocket framing; the observer decodes it without changing the frames. It does not attach
   to or try to control an unrelated TUI or shared daemon.
2. After a matching successful `turn/completed`, if the threshold is met and
   the user has not typed during the turn, it asks that TUI to execute the
   handoff skill. The prompt includes a unique freshness marker.
3. The matching handoff turn must complete successfully. The worktree-root
   `.agent-handoff.md` must be a regular, updated note containing that marker.
   Missing, stale, symlinked, failed, interrupted, and unrecognized handoffs
   disable automation and leave the old conversation in place.
4. Only then does the launcher submit `/clear` through the owned terminal.
   It waits for a successful `thread/start` response with a different ID and
   the same working directory before asking the agent to use the takeover skill. A full sentence avoids
   leaving the TUI skill-completion menu open on a bare `$takeover`. It never treats
   a terminal redraw or the existence of a note as proof of a fresh thread.
5. Each verified new thread gets a new freshness marker on its next handoff.
   Rotations can repeat as context grows. A fresh thread must first report
   usage below the threshold before another rotation; an immediately oversized
   takeover disables automation visibly instead of looping.

User input takes priority. Typing during the handoff sequence cancels further
automation; the launcher forwards the input normally. A transition timeout
also disables further actions. If `/clear` has already succeeded, a later
failure cannot restore the old visible chat automatically: its saved thread
remains available via `codex resume`. The note is retained for manual recovery.
The handoff turn itself has no timeout because approvals can take time.

The normal TUI handles sandbox and approval choices; the launcher never
answers an approval. CLI `-c`/`--config` and feature overrides are also forwarded
to its owned server. Profiles, explicitly remote endpoints, and `--worktree`
are rejected in this mode because their equivalent server setup is not
established. Ordinary launches pass those modes through with an automation-disabled warning. An interactive terminal is
required. CLI subcommands other than interactive `resume` are not intended
for automatic handoff.

## Existing hook and manual recovery

`scripts/codex-handoff-suggest` remains a nonblocking `PreCompact` UI warning
for automatic compaction. It does not inject instructions into the model or
claim a particular usage threshold. The hook installer preserves unrelated
hooks. This fallback also applies to normal launches without automatic mode.

To recover manually, ask the active agent to use the handoff skill, then exit
normally and run in the same worktree:

```sh
codex new '$takeover'
```

`resume` continues the old conversation; `fork` retains its history. Neither
provides the fresh context that `/clear` or a new conversation provides.

## Evidence and verification

The installed CLI help exposes `--remote unix://PATH`, `app-server --listen unix://PATH`,
and version 0.167.0. Generated App Server types expose `last.inputTokens`,
`modelContextWindow`, thread start/resume replies, and turn completion.

- [Official App Server reference](https://learn.chatgpt.com/docs/app-server):
  usage notifications, thread creation and turn lifecycle.
- [Official slash command reference](https://learn.chatgpt.com/docs/cli/slash-commands):
  `/clear` creates a fresh chat and is disabled during a running task.
- [Official hooks reference](https://learn.chatgpt.com/docs/hooks):
  the existing `PreCompact` warning is distinct from model-visible instructions.

Run deterministic safety and wrapper regression checks with:

```sh
bash tests/run tests/test_codex_auto_handoff.sh tests/test_codex_handoff_suggest.sh tests/test_codex_hook_refresh.sh tests/test_install_codex_compaction.sh
```

The optional installed-CLI probe uses temporary HOME/CODEX_HOME, a local
synthetic Responses provider, and fixture notes; it needs loopback socket
permission. It does not use real credentials or test model compliance with
the handoff/takeover skills:

```sh
python3 tests/codex_auto_handoff_cli_probe.py /absolute/path/to/real/codex
```
