# agent-config

Shared configuration and tooling for Bob, Claude Code, and Codex: global
instructions (`deploy/AGENTS.md` and the Codex variant), skills, settings,
hooks and CLI launchers.
No dotfiles dependency.

## Install

Requires Git; most scripts also need Python 3. Merging an invocation default
into an existing Codex skill `agents/openai.yaml` additionally requires PyYAML
for that Python (`python3 -m pip install PyYAML`, or the OS package equivalent).
The installer reports a missing parser and stops rather than editing YAML as
text or silently leaving the policy unset. It does not install Python packages.

```bash
curl -fsSL https://raw.githubusercontent.com/sawa2d2/agent-config/main/bootstrap.sh | bash
```

This clones into `~/agent-config` (override with `AGENT_CONFIG_DIR`) and runs
`./install`. Run global installation only from the persistent original checkout;
linked development worktrees are rejected before pull or HOME changes. Re-running
`./install` is safe: installed items are skipped and unmanaged files are never
overwritten.

To enable the launchers in interactive Bash or Zsh, add to your startup file:

```bash
[[ -f "$HOME/agent-config/shell/aliases.sh" ]] && source "$HOME/agent-config/shell/aliases.sh"
```

Use a persistent checkout such as `~/agent-config` for this line, rather than a
temporary development worktree. Open a new shell after editing the startup file,
or run the line above in the current shell. `alias codex` should then name
`~/agent-config/bin/codex` (with the home directory expanded).

If bare `codex` starts a new session instead of resuming, check `type -a codex`
and `alias codex`. The standalone installer owns `~/.local/bin/codex` and may
replace it during updates; leave that link pointing to the underlying CLI.
Load `shell/aliases.sh` from `.bashrc` or `.zshrc` to select the repository
launcher even when `~/.local/bin` comes first on PATH. The launcher removes its
own `bin` directory from PATH before resolving the underlying CLI, avoiding
recursion. Do not replace the installer's link with a link to `bin/codex`.
Aliases apply to interactive shell commands; scripts should invoke the
repository launcher explicitly when they need its resume defaults.

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
- `aistats claude|bob|codex`: token/cost usage with matching date/project filters, before/after comparisons, JSON Lines, and calendar or rolling-hour windows (see [usage statistics](docs/aistats.md)).
- `codex-ralph`: bounded loop of fresh `codex exec` runs until a check passes;
  `$loop` routes Codex tasks to it. Check results (including failed stdout/stderr)
  persist in the workspace’s uncommitted `.agent-progress.md`.
- `agent-backlog`: list, add, or remove untracked future tasks shared by all worktrees (see below).
- `agent-tmux-overview`: native tmux agent window picker with pane previews (see below).

Each script except the `claude`, `bob` and `codex` launchers (which pass it to the real CLI) prints its usage with `--help`; header comments in `bin/` and `scripts/` document the details.

Installed by `./install` (`scripts/`):

- Skills from `deploy/skills/` (`handoff`, `takeover`, `backlog`, `loop`) plus upstream skills, Spec Kit, rtk and Claude Code plugins (`install-tools`, `install-skill`, `install-rtk`, `install-claude-plugins`).
- Agent settings and themes (`install-claude-settings`, `install-bob-settings`, `install-bob-theme`, `install-codex-theme`, `install-codex-compaction`, `install-codex-subagent-model`).
  Bob task cost is unlimited by default (`session.maxCost: 0`). The next normal
  `bob` wrapper launch migrates the old repository default of `20` to `0`,
  preserving other explicit values. To clear an existing task limit and resume
  immediately, run `bob chat --resume latest --max-cost 0`.
- Hooks (`install-agent-hooks`): tmux window status (`agent-tmux-status`), `approved` merge marker (`agent-approval-marker`), handoff suggestions and rtk output compression. Standalone hook executables are copied to `~/.local/share/agent-config/hooks/`, so deleting the source worktree does not break installed hooks. `--codex-only` updates only Codex settings and its required executables.

Further documentation:

- [Project roadmap](ROADMAP.md)
- [Native compaction](docs/native-compaction.md) is the normal Claude Code, Bob Shell and Codex launch mode. The retained [automatic handoff](docs/automatic-handoff.md) is opt-in with `<cli> auto-handoff`; manual handoff/takeover remains available.
- [Codex skill metadata audit](docs/codex-skill-metadata.md)
- [Codex rtk coverage](docs/codex-rtk-coverage.md)
- [Codex session management and language tooling](docs/codex-session-language.md)
- [Claude Code 1-hour cache writes](docs/claude-cache-writes.md)
- [Isolating agent work under a dedicated user](docs/dev-user-isolation.md)

## Codex task coordination

`./install` removes the former repository-owned `gfinish` rule symlink. Custom
symlinks and regular rule files are preserved for explicit review.

The originating Codex agent can stay in its original checkout on `main`, launch
workers, and inspect their results on demand.
Existing launch and handoff behavior remains: `-m`/`--model` selects the model;
without a prompt, `.agent-handoff.md` is required and moved into the new worktree.
Before launching a worker, Codex's config API registers only the new worktree
as trusted in `$CODEX_HOME/config.toml` (default `~/.codex/config.toml`). Existing
settings are preserved. Workers start with `--sandbox danger-full-access` and
`--ask-for-approval on-request`: this disables the Codex sandbox for the whole
worker session while retaining approval requests. It does not authorize merges;
the exact `approved` requirement and approval marker remain. Existing user
permission to commit/push verified development-branch changes carries over without
another conversational confirmation; runtime approval requirements still apply.
The coordinator retains its existing permissions, so its shared `.git` launch or
report writes can need tool approval even when the worker has full access.
The resolved repository launcher is embedded in worker report commands, avoiding
reliance on an installed PATH link. Direct Codex launches
keep their existing defaults. Managed environment restrictions still apply.
Hook trust is separate. A failed trust registration stops the launch and is recorded in task
status; the created worktree is retained.

```bash
codex-delegate -m gpt-6.1-sol feat/fix 'Fix the bug; run relevant checks and commit/push'
codex-delegate --list
codex-delegate --status TASK_ID
codex-delegate --repo '/path/to/target repo' -m gpt-6.1-sol feat/fix 'Fix the target repository'
codex-delegate --repo '/path/to/target repo' --list
codex-delegate --repo '/path/to/target repo' --status TASK_ID
```

Use `--repo <path>` when the target repository is explicitly named; otherwise
the current directory remains the default. Put it before the branch (before or
after `-m`/`--model`). Relative paths resolve from the caller's directory; paths
may name a checkout or a subdirectory, including a linked worktree. The selected
checkout supplies the starting commit and handoff note, and its repository owns
the task records, lock and exclusions. The originating repository is untouched.
Invalid or unsupported repository paths fail before mutations. For `--report`,
`--repo` must select the assigned worker worktree (or a subdirectory), preserving
the worktree/branch identity checks. A prompt after the branch remains literal,
even when it starts with `--repo` or another option.

Claude's command is `agent-delegate`, not `claude-delegate`. Neither
`agent-delegate` nor `bob-delegate` supports `--repo`; run those commands from the
target checkout. Their implementations are unchanged.

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
state blocks writes. Use the CLI for all writers. Report blocked launch/report
writes; never fall back to worktree-local state. Reads never create files or
change exclusions.

All three delegates first wait up to 10 seconds for the interactive shell to
acknowledge readiness. Bash/Zsh arguments are serialized onto one physical line;
multiline prompt contents, quotes and control characters remain literal. The
user's shell still resolves the existing CLI wrappers and model arguments.
No launch is automatically retried: ambiguous delivery can leave a running agent.
On failure, inspect the retained pane/worktree before deciding whether to retry.
A tmux access denial is reported as inaccessible, never as proof of a missing pane.

Codex launch waits up to 90 seconds after submission for an explicit worker
`running` or `completed` report. A `failed`/`needs-input` report, lost pane,
inaccessible tmux, or timeout exits nonzero with the task ID and inspection advice.
Launch state (`starting`, `sent`, `verified`, `failed`), worker report, and pane
observation are independent. `sent` only confirms input submission; `verified`
confirms the worker reported startup, not that its implementation is correct.
The starting report must describe the worker's actual first action; never submit
example summaries verbatim. If reporting is blocked, explain the missing report
in the session.

Claude/Bob wait up to 30 seconds for a stable agent process in the pane's process
tree. Bob additionally waits up to 30 seconds for its input box before submitting
the prompt via a named bracketed-paste buffer. Timeouts never send the prompt to
a shell or an unready UI. Their success message confirms process startup and
submission; task acceptance and progress remain unverified. Each tmux operation
has a five-second timeout; no user startup files or CLI settings are changed by
the startup checks.
A pane token plus tmux server identity detects stale/reused panes; even a matching
live pane proves neither progress nor success. Failed pane queries are reported
as `inaccessible` with the query error; sandbox denial is not proof of a missing
pane. Missing tmux/panes or deleted
worktrees do not erase reports. Git refs may also disappear; status shows this
separately. Status does not capture terminal output or authenticate worker claims.

On partial launch failure the command exits nonzero, retains its record with
an error, and leaves any created worktree/window and moved handoff in place for
inspection. A crash can leave `starting`; report/storage permission failure may
prevent the final launch update. Inspect the recorded paths and tmux before any
manual recovery; do not blindly relaunch the same branch. Worker reports must be
made before deleting the worker checkout. No daemon, polling, follow-up injection,
automatic resume, cross-agent management, or automatic merge is provided.

## tmux agent overview

Run `agent-tmux-overview` inside an attached tmux session (`--help` for usage).
It uses native `choose-tree` across sessions on the current server, showing
window names, `@agent_status` and `@agent_attention`, with native pane previews.
Labels also show the last hook update (`@agent_status_at`, local time), and
application-provided native progress (`pane_pb_state` / `pane_pb_progress`) when
available. Window rows collect progress from every pane, identified by pane
index; expanded pane rows show only that pane's progress. For example:

```text
agent-config                 [working  ]   updated=11-07 14:32:10 p1=normal:42%
local-ai                     [waiting  ] ! updated=11-07 14:31:05
dots                         [untracked]   updated=-
```

Names use a 28-column field (long names are shortened with `...`); state,
attention and update fields are aligned, with optional pane details last.
An `!` marks an unacknowledged agent notification; otherwise that column is
blank. Missing update values are shown as `-`.

Progress can be `normal`, `error`, `indeterminate` or `paused`; indeterminate
progress has no percentage. Hidden or unsupported progress is omitted. Shared
agent hooks supply lifecycle state, not task phases or completion percentages;
a percentage appears only when a pane application supplies OSC 9;4 progress.

Bob, Claude Code and Codex use the existing shared hooks installed by `./install`
and refreshed by their launchers; no Fleet, model calls or additional daemon is
involved. `./install` links the command into `~/.local/bin`; sourcing
`shell/aliases.sh` also exposes it interactively.

Use Up/Down and Enter to switch to the selected target, `+` to expand a window's
panes, `v` to toggle previews, and `q` to close. With no marked agent windows the
command prints guidance instead of opening an unfiltered tree. Outside tmux it
asks you to start or attach a session and exits nonzero.

The filter requests marked agent windows. In tmux 3.7c, native `choose-tree` can
retain an unmarked window with multiple panes even when all its panes fail the
filter. These rows are labeled `[untracked]`, with a blank notification column
and `-` for the update field. This picker does not guarantee an agent-only list.

Suggested optional binding (prefix + `A`, unused in tmux's default prefix table;
check your own bindings first):

```tmux
bind-key A run-shell '~/.local/bin/agent-tmux-overview'
```

Add this yourself to your tmux configuration if wanted. This repository does
not edit `~/.tmux.conf` or its dotfiles symlink target, or apply live bindings.

Native `choose-tree` is not a continuously refreshed agent dashboard: item
labels are evaluated when the tree is built, and hook updates do not force a
rebuild. Close and reopen for current membership, state, progress and update
labels; terminal previews can change while the picker is open. Attention remains
set through resumed work until a submitted prompt or your tmux configuration
clears it; selecting a target does not acknowledge it. `stale` means no recent
hook update (normally 300 seconds), and `done` records the agent's Stop event.
Neither proves task completion
or successful checks; inspect the agent output and verification results.

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

Blocked backlog writes use the agent's normal tool approval workflow. Report
denials without creating a worktree-local backlog. Installing this feature
does not create a backlog in existing repositories.

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
All three installed variants contain the same shared Verification section.

## On-demand global procedures

`deploy/AGENTS.md` keeps shared engineering principles, test delegation and
safety rules always loaded. Bob and Claude load that shared file; Codex loads
it plus `deploy/codex/instructions.md`, rendered into `deploy/codex/AGENTS.md`.
Codex's approval, coordinator and deleted-worktree triggers
therefore reach only Codex. All agents retain the mandatory delegation
procedure trigger. Backlog storage/consultation and handoff creation/resumption
require the existing `backlog`, `handoff` and `takeover` skills only at their
respective triggers; storage, permission and note-lifecycle details stay there.

| Installed path | Linked repository file |
| --- | --- |
| `~/.bob/rules/agent-config.md` | `deploy/AGENTS.md` |
| `~/.claude/CLAUDE.md` | `deploy/AGENTS.md` |
| `~/.codex/AGENTS.md` | `deploy/codex/AGENTS.md` |

After editing either instruction source, run
`python3 scripts/render-codex-instructions` and commit the rendered file too.
The distribution test checks that it is current. These tracked files keep the
existing immediate-update symlink behavior without startup rendering or a
new always-on workflow. Rerun `./install` once to migrate Codex's former shared
link; the exact legacy target from any registered checkout of this repository
is migrated, and foreign symlinks remain untouched. The rendering command only
writes repository files.

Mandatory triggers direct agents to read only the applicable operational
reference before delegation/coordination/reporting, Codex finalization, or the
confirmed deleted-worktree hook failure. These references
are not a new skill or automatically invoked workflow.

`./install` links `deploy/operations/` to
`$HOME/.local/share/agent-config/operations/`, outside all agents' auto-loaded
instruction and skill directories. This fixed path works from arbitrary
repositories and linked worktrees; it does not depend on the session CWD or
resolving the global instruction symlink. Existing foreign links/directories
are refused. Installation from a linked development worktree is rejected before
pull or HOME changes, so finalizing that branch cannot break global links.
Reinstall from the persistent original checkout to repair links left by older
installers. Deleted worktrees are recognized while their Git registration remains;
dangling symlinks can also be repaired after removal/pruning. Existing regular
files and live unrelated symlinks are preserved. Review dangling link destinations
before authorizing a reinstall; the installer replaces missing symlink targets.
Rerun the installer after updating to create this link before
using the shortened global instructions; repair a missing reference rather
than skipping its mandatory procedure.

For skills with `disable-model-invocation: true`, `install-skill` fills an
unspecified Codex `policy.allow_implicit_invocation` with `false`, including
upstream metadata that contains only `interface` fields. Other parsed YAML
fields are preserved; an explicit policy choice is left byte-for-byte intact.
When adding the default, YAML comments/formatting may change. Invalid YAML,
duplicate keys or a non-mapping policy fail before replacing that Codex copy.
Bob/Claude copies and upstream sources are unchanged by the conversion.
The explicitly invoked `$loop` skill replaces `autonomous-development`. After
an authorized reinstall, remove the old installed skill only if its
`.agent-config-managed` marker confirms agent-config ownership.
Managed installed skills need a separate authorized reinstall to receive it;
repository changes alone do not rewrite real user settings. This does not
guarantee removal of skill metadata from the initial model context.

## Session token status lines

The launch/install hooks provide separate current-context and cumulative-session
indicators. Compaction can reduce context usage without resetting session totals;
neither total is a billing total.

- **Codex:** new settings use `model-with-reasoning`, `context-used`,
  `context-window-size`, `current-dir`, and `used-tokens`. The first two context
  items show native usage percentage and window capacity; `used-tokens` remains
  the cumulative session total. Codex 0.167.0 has no native status-line item for
  current context tokens. We do not estimate that count from rounded percentages
  or substitute cumulative input tokens. Unknown context items may be omitted.
  Supported items and their meanings were checked against the
  [0.167.0 status-line implementation](https://github.com/openai/codex/blob/rust-v0.167.0/codex-rs/tui/src/bottom_pane/status_line_setup.rs).
- **Claude:** `scripts/claude-session-status` displays, for example,
  `Context (last input): 24,000/200,000 tokens (12%) | Session tokens: 1,234,567`.
  Context uses the status JSON's `context_window.current_usage` input, cache-write,
  and cache-read tokens divided by `context_window_size`. This is the latest
  reported input snapshot, not a live count of newly generated output. It matches
  Claude's documented input-only percentage formula. Missing/null usage (including
  before the first response or just after compaction) displays `unavailable`, not
  zero. Session tokens separately sum transcript input, cache creation, cache read,
  and output once per main-session request, excluding subagents. A transcript read
  failure does not hide valid context data. See the
  [Claude status JSON reference](https://code.claude.com/docs/en/statusline#context-window-fields).

Existing status settings are preserved, including disabled/custom Codex footers
and the previous managed default: the installer cannot distinguish that default
from a deliberate user choice. To update an existing Codex footer, use
`/statusline` to replace `context-remaining` with `context-used`, add
`context-window-size`, and retain `used-tokens`. Existing Claude status commands
pointing to this repository's script pick up its new output; other custom commands
need manual integration with the same stdin JSON.

From the repository root, when ready to modify user settings:

```bash
bash scripts/install-codex-theme
bash scripts/install-claude-settings
```

Restart the CLIs afterward. These installers also apply their existing theme and
settings defaults; this change does not alter compaction thresholds. No real home
settings are installed by the tests. See
[Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference).

## Tests

```bash
tests/run
```

Runs every `tests/*.sh` (or the files given) and prints only failures.
