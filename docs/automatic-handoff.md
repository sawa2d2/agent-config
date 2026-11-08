# Automatic interactive handoff

Ordinary `claude`, `bob` and `codex` launches use
[native compaction](native-compaction.md). Select the retained custom handoff
with `claude auto-handoff`, `bob auto-handoff`, or `codex auto-handoff`.
Put `auto-handoff` first, before `new`, resume arguments, or a prompt. The
usual no-argument resume defaults still apply after this prefix. The
launcher owns a pseudo-terminal; native UI, tools and approval policies remain
in control. It never answers an approval. Noninteractive/utility invocations
retain their existing behavior. Unverified Claude/Bob versions run normally with a visible automation-disabled
warning; explicit Codex auto-handoff rejects an unverified version.

| Agent | Installed interface investigated | Trigger at a successful turn boundary |
| --- | --- | --- |
| Claude Code 2.1.319 | `--help`, embedded hook schema, `SessionStart(source=clear)`, `UserPromptSubmit`, `Stop`, native `/clear` | Latest transcript request input + cache creation + cache read >= 35,000 tokens |
| Bob Shell 2.0.9 | `--help`, `chat --help`, installed `@ibm/bob/dist/bob.js` hook lifecycle and built-in `clear` command (aliases `new`, `task`) | Latest request context > 50,000 tokens |
| Codex 0.167.0 | `--help`, `app-server --help`, App Server thread/turn/token events, native `/clear` | Latest request input >= min(35,000, 80% of context window) |

Measurements are latest request sizes, not accumulated tokens. Long autonomous
turns may compact before a successful boundary. Bob's database is opened
read-only, using the same schema as the existing suggestion hook. Cumulative
cost and `--max-cost` do not trigger rotation; Bob still enforces its native
cost limit.
A cost-limit failure is not a successful boundary and cannot clear a chat.

Native compaction remains enabled in opt-in mode. With the new lower defaults
it can run before the handoff threshold is observed, including during the
handoff turn. The prefix selects the retained automation; it does not guarantee
rotation or silently change a user's compaction settings. For a comparison
with the previous native headroom, explicitly use the prior 100k Codex limit,
120k Claude window, or 37% Bob threshold as described in the native guide.

## Sequence

1. After a successful completed turn, if usage is high and the user has not
   typed during that turn, submit a handoff skill request through the owned TUI.
2. Wait for that handoff turn to finish normally. Verify a changed, regular,
   non-symlinked worktree-root `.agent-handoff.md`, under 1 MiB, containing this
   rotation's random marker. The prompt explicitly records unfinished work and
   verification results; the agent writes it using ordinary tools/approvals.
3. Submit native `/clear`. Claude and Codex must report a different session ID
   in the same cwd before takeover is sent. Bob only emits `SessionStart` when
   submitting the next prompt: its synchronous `UserPromptSubmit` relay blocks
   automatic takeover with exit 2 unless the preceding `SessionStart(startup)`
   confirmed a different task ID and the same cwd. Sending `/clear` alone is
   never treated as proof of success.
4. Continue with the takeover skill. Repeat when the new context grows again;
   there is no one-rotation cap. Fresh context must first be measured below the
   threshold to prevent an oversized takeover from causing a rotation loop.

Physical input takes priority and is forwarded unchanged. A draft prevents
rotation at that boundary; input during a handoff transition cancels automation
for that launch. This includes interacting with an approval dialog: the normal
approval still works, but the launcher leaves the resulting note for manual
recovery. Handoff execution itself has no timeout; command transitions do.
Claude background tasks and scheduled session work disable rotation rather
than leaving them behind.

Missing/stale notes, failed turns, a handoff compaction, mismatched identities,
relay failures and transition timeouts report errors and disable further
actions. Saved histories are never deleted. A failure after `/clear` cannot
restore the old visible chat; resume its old ID using the native session picker,
or start `claude new '/takeover'`, `bob new` followed by `$takeover`, or
`codex new '$takeover'` in the same worktree. The note remains available.

## Installation and scope

The existing launch-time `install-agent-hooks` refresh installs
`agent-handoff-event` for Claude and Bob. It is a no-op without the private
launcher socket. Existing settings and unmanaged hooks are preserved. Bob's
older suggestion hook remains available outside an owned launcher and avoids
duplicate suggestions inside one. No separate deployment command or new user
setting is required. Implementing and testing this change does not itself
install settings into the user's home.

Codex profiles, explicitly remote endpoints and `--worktree` are not supported
by its owned App Server integration and visibly fall back to the native CLI.
The owned Codex TUI receives an explicit `--cd` for the launch directory unless
one was supplied, so `tui.resume_cwd = "current"` also works through its remote
transport. Explicit `-C`/`--cd` choices are preserved.
Claude print, background, safe/bare, and worktree launches bypass automation.
This integration targets the inspected native TUIs and hook contracts; it is
not an API for controlling unrelated tmux panes. Terminal text alone is never
used to validate the fresh conversation.

Sources: [Claude hook reference](https://code.claude.com/docs/en/hooks) and
[Codex App Server reference](https://learn.chatgpt.com/docs/app-server).
Bob evidence is the installed 2.0.9 distribution: built-in `clear` description
“Start a new task”; `newTask()` creates a new root task; `applyInput()` emits
SessionStart on its first prompt; task-manager `stop()` runs only after a
noncancelled successful root turn. Stop cannot block Bob, so rotation belongs
to the launcher, with its next input checked by UserPromptSubmit.

## Verification

```sh
git switch feat/native-context-compaction
bash tests/run tests/test_agent_auto_handoff.sh tests/test_codex_auto_handoff.sh tests/test_install_agent_hooks.sh tests/test_cli_wrappers.sh tests/test_claude_wrapper.sh tests/test_bob_handoff_suggest.sh tests/test_codex_hook_refresh.sh
```

Expected: all suites pass. Tests use temporary homes, fixture databases and
CLI doubles; the PTY/relay fixtures exercise two full rotations for Claude and
Bob. They verify transport and safety, not real model compliance with skills.
The separate installed-Codex synthetic-provider probe is documented in
[Codex handoff support](../deploy/codex/handoff.md). No real model/credential
session is necessary for the deterministic checks.
