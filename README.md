# agent-config

Shared configuration and tooling for Bob, Claude Code, and Codex: global
instructions (`deploy/AGENTS.md`), skills, settings, hooks and CLI launchers.
No dotfiles dependency.

## Install

Requires Git; most scripts also need Python 3.

```bash
curl -fsSL https://raw.githubusercontent.com/sawa2d2/agent-config/main/bootstrap.sh | bash
```

This clones into `~/agent-config` (override with `AGENT_CONFIG_DIR`) and runs
`./install`. Re-running `./install` is safe: installed items are skipped and
unmanaged files are never overwritten.

To enable the launchers in interactive Bash or Zsh, add to your startup file:

```bash
[[ -f "$HOME/agent-config/shell/aliases.sh" ]] && source "$HOME/agent-config/shell/aliases.sh"
```

Optional extras:

```bash
bash scripts/install-bob-shell                    # IBM Bob Shell
bash scripts/install-bob-ralph                    # experimental Bob Ralph runner
bash scripts/install-nvim-acp && bash nix/apply   # Neovim CodeCompanion chat (<leader>a)
```

## Update agent CLIs

Run `bin/update-bob`, `bin/update-claude`, or `bin/update-codex` without arguments
(`--help` prints usage). Sourcing `shell/aliases.sh` also exposes these commands.
They bypass this repository's launch wrappers and managed settings installers.

- `update-bob`: reruns IBM's [recommended installer](https://bob.ibm.com/docs/shell/getting-started/install-and-setup), requiring `curl` and Bash. Unlike `install-bob-shell`, it does not skip an existing installation.
- `update-claude`: runs the underlying `claude install latest` ([official CLI reference](https://code.claude.com/docs/en/cli-reference)), requiring an existing Claude executable. This installs the native binary and selects the latest release channel, even if stable was previously configured.
- `update-codex`: reruns the standalone installer with `curl` and `sh`, as documented in [official OpenAI documentation](https://learn.chatgpt.com/docs/codex/cli).

These commands target macOS/Linux installer-managed installations. Use the
original package manager for Homebrew, npm, or other package-managed installs
to avoid creating a second installation. Upstream installers may change their
own installation metadata or update-channel settings; no agent-config settings
refresh runs. Download and update failures return a nonzero status.

## Components

Launchers (`bin/`):

- `claude`, `bob`, `codex`: resume the latest session in the current directory; `<tool> new` starts a new one. They refresh managed settings and hooks on launch.
- `claudel`, `bobl`, `codexl`, `codexla`: session pickers (current directory; `codexla` for all directories).
- `agent-delegate`, `bob-delegate`, `codex-delegate`: start a new branch in a new worktree and tmux window with the same agent.
- `bobtask`: list, resume, delete, move, dump or hand off Bob tasks (`bobrm` = `bobtask rm -c`).
- `clauderm`: delete Claude Code sessions of the current repository.
- `codexrm`: delete Codex sessions of the current repository (with their subagent threads).
- `ai-stats claude|bob|codex`: token/cost usage with matching date/project filters, before/after comparisons, JSON Lines, and weekly or fixed windows (see [usage statistics](docs/ai-stats.md)).
- `codex-ralph`: bounded loop of fresh `codex exec` runs until a check passes.
- `agent-backlog`: list, add, or remove untracked future tasks shared by all worktrees (see below).

Each script except the `claude`, `bob` and `codex` launchers (which pass it to the real CLI) prints its usage with `--help`; header comments in `bin/` and `scripts/` document the details.

Installed by `./install` (`scripts/`):

- Skills from `deploy/skills/` (`handoff`, `takeover`, `backlog`, `autonomous-development`) plus upstream skills, Spec Kit, rtk and Claude Code plugins (`install-tools`, `install-skill`, `install-rtk`, `install-claude-plugins`).
- Agent settings and themes (`install-claude-settings`, `install-bob-settings`, `install-bob-theme`, `install-codex-theme`, `install-codex-compaction`, `install-codex-subagent-model`).
- Codex rules (`deploy/codex/rules/agent-config.rules`, linked to `~/.codex/rules/`): `gfinish` runs outside the workspace-write sandbox, which cannot write a linked worktree's shared `.git`, the primary worktree or the network; gfinish's `approved` marker check still authorizes the merge. A gfinish chained after other commands still ran in the sandbox, so `deploy/AGENTS.md` also tells Codex to request `require_escalated` for gfinish and for sandbox-blocked Git writes. Only after operation results establish successful authorized deletion of the active session worktree (`gfinish` or explicit branch/worktree discard), subsequent `Hook failed: No such file or directory (os error 2)` is the known missing-session-cwd hook launch failure: Codex starts hooks in the deleted session directory. This message alone calls for no extra checks, deletion/merge investigation or retries, directory recreation, or hook changes/disabling. Actual failed Git commands, unrelated hook errors, errors before deletion, and remaining explicitly authorized cleanup still need ordinary handling; required remaining commands must use an existing original-root workdir.
- Hooks (`install-agent-hooks`): tmux window status (`agent-tmux-status`), `approved` merge marker (`agent-approval-marker`), handoff suggestions and rtk output compression.

Further documentation:

- [Project roadmap](ROADMAP.md)
- [Codex handoff support](deploy/codex/handoff.md)
- [Codex skill metadata audit](docs/codex-skill-metadata.md)
- [Codex rtk coverage](docs/codex-rtk-coverage.md)
- [Codex session management and language tooling](docs/codex-session-language.md)
- [Claude Code 1-hour cache writes](docs/claude-cache-writes.md)
- [Isolating agent work under a dedicated user](docs/dev-user-isolation.md)

## Codex task coordination

The originating Codex agent can stay in its original checkout on `main`, launch
workers, and inspect their results on demand. Claude/Bob delegation is unchanged.
Existing launch and handoff behavior remains: `-m`/`--model` selects the model;
without a prompt, `.agent-handoff.md` is required and moved into the new worktree.
No installed settings or approval rules are changed by these commands.

```bash
codex-delegate -m gpt-6.1-sol feat/fix 'Fix the bug; run relevant checks and commit/push'
codex-delegate --list
codex-delegate --status TASK_ID
```

Launch prints a unique task ID. `--list` returns stored JSON without contacting
tmux; `--status` adds on-demand pane identity, worktree presence, current branch
head and whether reported commits remain ancestors of that branch. Both reads
are read-only, require no tmux installation, and work from any linked worktree.
Check actual diffs and test evidence before accepting a worker's completion:

```bash
git log --oneline main..feat/fix
git diff main...feat/fix
```

The worker prompt includes concrete reporting instructions. From its assigned
worktree and branch, the worker must explicitly run commands like these (replace
TASK_ID and FULL_COMMIT_SHA with the launch ID and a full commit SHA):

```bash
codex-delegate --report TASK_ID running --summary 'Investigating the failure'
codex-delegate --report TASK_ID needs-input --summary 'Need a decision about expected behavior'
codex-delegate --report TASK_ID completed --summary 'Fixed the bug; no remaining work' --checks 'tests/run tests/test_example.sh: passed' --commit FULL_COMMIT_SHA
codex-delegate --report TASK_ID failed --summary 'Dependency unavailable; implementation unfinished' --checks 'Test command failed: dependency missing'
```

Completed/failed reports require actual check commands/outcomes (or why checks
were not run); repeat `--commit` for multiple commits. Explain when no commit is
needed. Invalid reports fail without updating the stored result. Only the latest
report is stored; these are explicit agent statements, not automatic telemetry.
The launch prompt delegates branch commits/pushes unless the task overrides it.
Workers also leave a final outcome in their tmux session if reporting is blocked.

Records persist in the original checkout's untracked `.codex-tasks/`, shared
across linked worktrees and retained after a worker worktree is deleted. Root
validation follows `agent-backlog`; unsupported bare/separate-Git-directory
layouts are rejected. Writes use a common Git metadata lock and atomic record
replacement, and append `/.codex-tasks/` to common `info/exclude`; tracked task
state blocks writes. Use the CLI for all writers. Launch/report writes from a
linked worktree may need supported `require_escalated` approval after a sandbox
denial. Request approval for that exact authorized command; automatic review
still applies. Never change sandbox settings, broaden allow rules or fall back
to worktree-local state. Reads never create files or change exclusions.

Launch state (`starting`, `sent`, `failed`), worker report, and pane observation
are independent. `sent` means input was sent, not that Codex started successfully.
A pane token plus tmux server identity detects stale/reused panes; even a matching
live pane proves neither progress nor success. Missing tmux/panes or deleted
worktrees do not erase reports. Git refs may also disappear; status shows this
separately. Status does not capture terminal output or authenticate worker claims.

On partial launch failure the command exits nonzero, retains its record with
an error, and leaves any created worktree/window and moved handoff in place for
inspection. A crash can leave `starting`; report/storage permission failure may
prevent the final launch update. Inspect the recorded paths and tmux before any
manual recovery; do not blindly relaunch the same branch. Worker reports must be
made before deleting the worker checkout. No daemon, polling, follow-up injection,
automatic resume, cross-agent management, or automatic merge is provided.

## Shared future tasks

From the primary checkout or any linked worktree:

```bash
agent-backlog path
agent-backlog add 'Investigate the slow startup; compare cold and warm runs'
agent-backlog list
agent-backlog remove 'Investigate the slow startup; compare cold and warm runs'
```

The Python 3 CLI uses Git's common directory and worktree metadata to find the
original checkout and validates that it is a working-tree root. Tasks
live in that checkout's `.backlog.md`, independent of the current branch. For
this repository that is `/home/dev/agent-config/.backlog.md`, even when working
under `/home/dev/worktrees/`. Bare repositories have no original checkout and
are rejected, as are separate-Git-directory layouts where Git's worktree list
reports the metadata directory instead of the checkout. Reads do not create
files. Writes use a shared advisory lock and
atomic replacement; use the CLI for all writers to avoid lost updates. Existing
content is preserved, additions are single-line checklist entries, and removal
matches exact task text. Legacy prose is never removed implicitly.

On writes the CLI appends `/.backlog.md` to the common `info/exclude`, preserving
existing exclusions. It never changes tracked `.gitignore` or untracks files;
a tracked backlog in any registered worktree blocks writes pending an explicit
migration decision. `.agent-handoff.md` stays local to each worktree for the
current task. Reading future tasks does not authorize executing them.

`./install` distributes the `backlog` skill to Bob, Claude Code, and Codex and
links `agent-backlog` into `~/.local/bin` for noninteractive use. The shared
instructions discover it through the existing global instruction links;
`shell/aliases.sh` also exposes the CLI in interactive shells. Invoke the skill
as `/backlog` in Claude Code or `$backlog` in Bob and Codex.

Codex's linked-worktree sandbox may deny writes to the original checkout and
common Git directory. For an authorized backlog write, request the supported
`require_escalated` execution after a sandbox denial; automatic approval review
still applies. Bob and Claude Code use their normal tool approvals. A denial
must be reported, with no local backlog fallback, broad allow rule, or sandbox
change. Installing this feature does not modify these permissions or create a
backlog in existing repositories.

`tests/test_agent_backlog.sh` verifies CLI behavior and installation/discovery
in temporary fixtures. These checks do not prove actual Bob/Claude/Codex skill
selection or sandbox approval end to end; those require authorized sessions in
each agent. No installed user settings or data are needed for these tests.

## Test delegation

The shared Verification rules in `deploy/AGENTS.md` delegate each test run to
Bob subagents (`spawn_subagent`), Claude Code subagents, or Codex subagents
(`spawn_agent`). Bob's interactive subtasks are a separate mechanism.
The parent defines commands and scope, reviews results, and handles fixes and
Git operations; the child runs checks directly and reports exit statuses and
failure evidence. Unavailable delegation or missing results never count as a pass.
`./install` links the shared rules to `~/.bob/rules/agent-config.md`,
`~/.claude/CLAUDE.md`, and `~/.codex/AGENTS.md`; no installer changes are needed.

## Tests

```bash
tests/run
```

Runs every `tests/*.sh` (or the files given) and prints only failures.
