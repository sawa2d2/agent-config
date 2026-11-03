# agent-config

Shared configuration and tooling for Bob, Claude Code, and Codex. No dotfiles dependency.

## Install

Requires Git.

```bash
curl -fsSL https://raw.githubusercontent.com/sawa2d2/agent-config/main/bootstrap.sh | bash
```

Clones into `~/agent-config` (override with `AGENT_CONFIG_DIR`) and runs the existing installer. An existing Git checkout is reused without pulling; other existing destinations are not overwritten.

Installs global instructions, agent skills, Spec Kit, rtk, Claude Code CLI and its ACP adapter (via Nix when available), and the Claude Code plugins `ralph-loop` and `pyright-lsp` from the official marketplace (`scripts/install-claude-plugins`). Superpowers is installed as standalone skills for all three agents, without the Claude plugin, whose SessionStart hook injected its `using-superpowers` skill into every session; that skill and `diagnosing-superpowers` are left out, and an earlier plugin install is removed. The other Superpowers skills get `disable-model-invocation: true` for explicit invocation; Codex receives the native policy described below. Invoke them by name or through `autonomous-development`. `pyright-lsp` needs `pyright-langserver` on `PATH`; an existing one is reused, otherwise Nix adds `pyright`. Re-running skips what is already installed. Existing unmanaged instructions are protected.

## Skills

Skills in `deploy/skills/` are copied to `~/.bob/skills`, `~/.claude/skills` and `~/.codex/skills` by `./install`, alongside upstream skills from `scripts/install-tools`. Copies carry a `.agent-config-managed` marker; a skill of the same name installed some other way is never overwritten.

For Codex (`$CODEX_HOME/skills`, default `~/.codex/skills`), the installer translates
`disable-model-invocation: true` in frontmatter into
`policy.allow_implicit_invocation: false` in `agents/openai.yaml` when that file
is absent. Existing upstream metadata is kept unchanged and reported; inspect
its invocation policy separately. Claude/Bob copies and source files are unchanged.
[OpenAI documents explicit `$skill` invocation as supported](https://learn.chatgpt.com/docs/build-skills).
An isolated Codex 0.160.0 check with `debug prompt-input` confirmed the skill
disappears from the initial catalog; app-server `skills/list` still reports it
as enabled. Actual explicit execution and automatic selection were not tested,
and no runtime token or cost savings were measured.

| Skill | Use |
| --- | --- |
| `handoff` | Write `.agent-handoff.md` (see [Agent handoff notes](#agent-handoff-notes)) when asked, when a suggested handoff is accepted, or before stopping with work unfinished |
| `autonomous-development` | Invoked by name only (`/autonomous-development`): route an objective to superpowers, Spec Kit or ralph-loop, and run long work with stacked branches, a progress file at the working-tree root and batched user checks |

The upstream `grill-me`, `grilling` and `domain-modeling` skills, like
Superpowers, are installed with `disable-model-invocation: true`
(`scripts/disable-model-invocation`), as are the Bob `prd` and `ralph` skills
from `scripts/install-bob-ralph`: they serve explicit requests, and every skill
description in the list is resent with each request. Invoke them by name
(`/grill-me`). `handoff` stays model-visible so the agent can offer it. Bob's
built-in skills (`configure-hooks`, `office-insights` and others) have no
setting to hide them in Bob Shell 2.0.9 and stay listed.

## Claude Code theme

`./install` enables `custom:agent-config-selected`. User message backgrounds
follow the saved dotfiles theme variant (default: teal), with a darker shade
for contrast against Claude Code's light text. It also sets `"tui": "default"`
when no renderer is configured, so output stays in terminal and tmux scrollback;
an explicit `/tui fullscreen` choice is kept. Unless set already,
`"autoCompactWindow": 200000` compacts the context at about 200k tokens rather
than near the 1M window, since every request resends the whole context;
`/autocompact` or an explicit value overrides it. Unless set already,
`env.CLAUDE_CODE_SUBAGENT_MODEL` is `sonnet`, so subagents without a model of
their own search and read on Sonnet instead of inheriting the main model
(often Opus). Office and browser skills (`docx`, `pptx`, `xlsx`, `pdf`,
`google-workspace`, `computer-use`, `built-in-browser`, `chrome-browser`,
`claude-in-chrome`, `morning`, `import-memory`) are set to
`user-invocable-only` in `skillOverrides`, so their descriptions stay out of
every request while `/name` still works; an explicit override is kept. The
built-in `plugin-authoring` skill is hidden the same way. Other
settings in
`~/.claude/settings.json` are preserved. Python 3 is required.

To refresh these settings on every new Claude CLI session, ensure `~/agent-config/bin` precedes the original Claude executable in `PATH`. The `bin/claude` wrapper refreshes them and then executes the real CLI with its original arguments. It sets `CLAUDE_CODE_DISABLE_MOUSE=1` unless already set, so mouse selection and scrolling stay with the terminal and tmux. On Linux with X11 forwarding (`ssh -X`, `DISPLAY` set) and `xclip` installed, it also unsets `SSH_CONNECTION`, `SSH_TTY` and `SSH_CLIENT`, because Claude Code otherwise copies only via OSC 52, which terminals such as GNOME Terminal ignore. To refresh manually instead, run:

```bash
bash scripts/install-claude-settings
```

To override the theme variant without dotfiles:

```bash
AGENT_CONFIG_THEME_VARIANT=violet bash scripts/install-claude-settings
```

Claude Code does not currently expose a user-message-only foreground token;
changing `text` to dark would also darken assistant responses.

## Bob Shell theme

`./install` also writes `~/.bob/theme.json` with the same user message
background. Bob reads this file through an undocumented mechanism (observed in
Bob Shell 2.0.6); it replaces terminal background detection, so the file pins
Bob's built-in dark palette and changes only `backgroundColor`. A user-managed
`theme.json` is never overwritten. The `bin/bob` wrapper refreshes it on each
launch. To refresh manually:

```bash
bash scripts/install-bob-theme
```

The background applies only in true-color terminals; Bob uses fixed ANSI
colors for user messages in 256- and 16-color terminals.

## Codex skill metadata

The Claude Office/browser overrides above are not copied into Codex settings.
The Codex 0.160.0 audit found none of those 11 skill names in the local skill
directories or plugin cache. There is therefore no matching installed skill
for this repository to change. Unmanaged plugins and user choices are preserved.
See [the audit and supported controls](docs/codex-skill-metadata.md).

## Codex theme

Codex has no setting for its user message background: it lightens the
terminal background (observed in Codex 0.160). Its syntax theme does supply
the colors of inline code, of type names (which also color table headers and
the model in a colored status line) and of a few controls (scope
`codex.accent`), so `./install` writes `~/.codex/themes/agent-config-selected.tmTheme`:
Codex's default dark theme, Catppuccin Mocha (`deploy/codex/themes/`, MIT
license), with those colors set to the selected dotfiles color. It also sets
`[tui] theme = "agent-config-selected"` in `~/.codex/config.toml` unless a
theme is already configured, so a `/theme` choice is kept. A user-managed theme
file of the same name is never overwritten. The `bin/codex` wrapper refreshes
it on each launch, and `CODEX_HOME` is honored. To refresh manually:

```bash
bash scripts/install-codex-theme
```

The theme is dark; on a light terminal select another one with `/theme`.

## Codex compaction

`./install` and `bin/codex` add `model_auto_compact_token_limit = 200000`
to `$CODEX_HOME/config.toml` (default: `~/.codex/config.toml`) when absent.
This token threshold follows this repository's Claude `autoCompactWindow=200000`
policy; it is not equivalent to Bob's `session.compactionThresholdPercent=80`
and is not an OpenAI recommended value. It targets earlier compaction for large
contexts without overriding the model's context window. Existing explicit values,
including quoted keys and profile settings, are kept; if a profile in this file
sets the threshold, no global default is added. CLI `-c` overrides still apply.
Refresh manually with `bash scripts/install-codex-compaction`.

The [official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
documents this setting as a token threshold; unset uses model defaults.
Support was checked against Codex CLI 0.160.0's generated app-server schema and
configuration loading in a temporary HOME. Actual compaction timing depends on
the model and runtime; runtime compaction and token savings have not been measured.

## Bob Shell settings

`./install` and the `bin/bob` wrapper add these defaults to
`~/.bob/settings/settings.json` only when the key is missing, so values you set
yourself are kept:

| Key | Value | Effect |
| --- | --- | --- |
| `session.limitWarnings` | `true` | Tell the agent to wrap up five turns before the turn limit (Bob's default of 100 model calls per task) and at 80% of `maxCost`; the shared instructions then have it write a handoff note |
| `session.respectGitIgnore` | `true` | Apply each `.gitignore` like a `.bobignore`: ignored files are hidden from listings and search and cannot be read or written |
| `session.compactionThresholdPercent` | `80` | Compact the context at 80% instead of 90%, keeping each turn smaller; instructions given only in chat may be summarized away |
| `session.maxCost` | `20` | Stop a task once it has spent 20 Bobcoins (no limit by default); with `limitWarnings` the agent is told to wrap up at 80%, and continuing doubles the limit for that task |
| `approval.outsideWorkspaceAllowed` and a `read` entry in `approval.permissionOptions` | `true` | Auto-approve reads outside the workspace, so a task started by `bobtask handoff` can read the transcript in `$TMPDIR` (Bob cancels every tool call outside the workspace by default); edits and commands there still ask. Any file the user can read becomes readable without a prompt |

Earlier installs set `session.maxTurns` to `300`; that exact value is removed so Bob's default applies, and any other value is kept.

To continue a stopped task in a fresh context, see `bobtask handoff`.

## Agent handoff notes

The shared instructions (`deploy/AGENTS.md`) tell Bob, Claude Code and Codex
to write a short handoff note with the `handoff` skill (`/handoff`) when asked,
when they accept a suggested handoff, before stopping with work unfinished, and
first thing on a Bob turn or cost limit warning. The note goes to
`.agent-handoff.md` at the root of the working tree, and the agents read it
when continuing. Any of the three agents can pick up from it without the earlier
transcript. The note stays inside the working tree because Codex's sandbox
keeps `.git` read-only. Git ignores it through the global gitignore of the
dotfiles; a repository's `.gitignore` must not list it, since Bob with
`respectGitIgnore` refuses to read or write the files listed there.

`agent-delegate <new-branch> [prompt]` starts a new branch in a new Claude
session and worktree without leaving the current pane; agents run it when they
start a development branch inside tmux, so `./install` links it into
`~/.local/bin`. Inside tmux, it creates
the worktree with `gwt-path -b` from the dotfiles, moves `.agent-handoff.md`
from the current working tree into it, creates one new tmux window per branch
without moving focus, marks the worktree as trusted in `~/.claude.json` so
Claude skips its trust dialog there, and types `claude` with a prompt to read the note (or
the given prompt) into that pane's shell. Like `gwt`, it needs the primary
worktree on `main`.

`bob-delegate <new-branch> [prompt]` and `codex-delegate <new-branch> [prompt]`
use the same worktree, handoff-note, and window conventions for Bob and Codex;
`./install` links all three commands into `~/.local/bin`. Always use the command
for the originating agent: Claude to Claude, Bob to Bob, and Codex to Codex.
Codex delegation starts `codex new` with the prompt through the existing wrapper,
with the automatic-review default described below; trust settings stay unchanged.
With no prompt, a handoff note is required.

For Bob, `./install` also registers `scripts/bob-handoff-suggest` as a
`UserPromptSubmit` hook. Once a task has spent half of `session.maxCost`, or
the latest request's context exceeds 50000 tokens
(`AGENT_CONFIG_BOB_HANDOFF_TOKENS` overrides this; `0` turns it off), read
from Bob's database without using the model, it adds one line of context, once
per task, so the agent suggests a handoff; answering yes writes the note. Bob
charges each request by its context size, so a long task costs more per turn
than a fresh one continuing from the note, and compaction at
`compactionThresholdPercent` may never trigger: Bob takes the context window
from the server at runtime, so the percentage cannot be pinned to a token count
here. The hook relies on Bob's internal `tasks.costs` column and the
`_meta.spend.contextTokens` of assistant messages (Bob Shell 2.0.6 and 2.0.9),
and skips a check whose data is missing.
`bobtask handoff` points the new Bob task at the note when the workspace has
one, keeping the transcript only for details the note lacks.
The `autonomous-development` skill keeps its progress file,
`.agent-progress.md`, at the working-tree root for the same reasons.

For Codex, `./install` registers `scripts/codex-handoff-suggest` on
`PreCompact` with matcher `auto`. It displays a UI warning suggesting a
handoff when automatic compaction starts. It lets compaction continue; it
does not ask the model to write a note before compaction. After compaction,
ask the agent to use the handoff skill, then exit normally and run
`codex new "Read .agent-handoff.md and continue the work described there."`
in the same worktree. New or changed hooks require review in `/hooks`.
There is no Bobcoin conversion, inferred percentage, cost-limit restart,
or automatic session replacement. See [Codex handoff support](deploy/codex/handoff.md)
for the checked CLI version, available signals, and limitations.

## Merge approval marker

The `bin/claude`, `bin/bob` and `bin/codex` wrappers export
`AGENT_APPROVAL_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}/agent-approval"` unless
it is already set; its presence marks the process tree as an agent. `./install`
registers `scripts/agent-approval-marker` as a
`UserPromptSubmit` hook for Claude Code, Bob and Codex. All three wrappers also refresh
hooks at launch. When the whole prompt, trimmed,
is exactly `approved` (case-sensitive), it touches
`$AGENT_APPROVAL_DIR/<sha256 of the real path of the session's git top level>`.
`gfinish` in the dotfiles merges from an agent only with a marker for its
repository from the last 60 minutes, and deletes it, so a question such as
`approve 可能？` is no approval. Outside a git repository the hook does nothing,
and it never blocks the prompt. The agents pass the prompt and the session's
`cwd` to the hook, and Bob runs command hooks with its own environment
(observed in Bob Shell 2.0.9). Codex's
[official hook interface](https://learn.chatgpt.com/docs/hooks) supplies the same
`prompt` and `cwd` fields. New or changed Codex hooks must be reviewed and trusted
in `/hooks`; installation does not bypass hook trust or command approval. This
marker is a local workflow guard, not a sandbox security boundary. The external
`gfinish` currently uses unquoted `xargs realpath` when computing its hash, so
repository paths containing spaces are not compatible with that implementation;
the marker keeps its existing canonical-path hash rule.

## tmux agent status

`./install` and the `bin/bob` and `bin/claude` wrappers register
`scripts/agent-tmux-status` as Bob Shell and Claude Code hooks. The installer
also registers Codex hooks in `$CODEX_HOME/hooks.json` (default
`~/.codex/hooks.json`); other hooks are kept. Inside tmux, it marks the window
the agent runs in. `@agent_attention` is `1` once the agent needed you, also in the window you are looking at, and
stays through resumed work until you submit a prompt there; `@agent_status`
keeps the detail:

| State | Attention | Set when |
| --- | --- | --- |
| `working` | cleared by a prompt, otherwise kept | A prompt is sent or a tool runs |
| `waiting` | `1` | Claude Code or Codex asks for permission |
| `done` | `1` | The agent finished its reply |
| `stale` | `1` | `working` without updates for `@agent_status_stale_after` seconds (default 300): a hang, an error, or Bob waiting for approval (Bob has no event for it) |

A tmux configuration may also unset `@agent_attention` when a window is
selected.
A new Bob session or the end of a Claude Code or Codex session clears the mark.
Interrupting an active Codex turn also clears it. Codex uses `UserPromptSubmit`,
`PreToolUse` and `PostToolUse` for working, `PermissionRequest` for waiting,
`Stop` for done, and `SessionEnd` / `Interrupt` for cleanup, as supported by
[Codex hooks](https://learn.chatgpt.com/docs/hooks) (checked with CLI 0.160.0).
The waiting hook returns no approval decision; normal permission handling
continues. New or changed Codex hooks need trust via `/hooks`. These events
do not cover every input wait (for example, a model asking a question). The
window options `@agent_status`, `@agent_attention` and `@agent_status_at` are
the interface; this repository does not change the tmux status line. To
highlight windows that need you:

```tmux
set -g window-status-format '#{?@agent_attention,#[fg=magenta bold],} #I:#W '
set -g window-status-current-format '#{?@agent_attention,#[fg=magenta bold],} #I:#W '
```

A status line drawn by a script can set `@agent_status_hook` to a command
that `agent-tmux-status` runs (with `tmux run-shell -b`) after each change.
A long-running tool call without other output can also turn a window stale.

## rtk command output compression

`./install` adds [rtk](https://github.com/rtk-ai/rtk) (`scripts/install-rtk`):
the Apache-2.0 `rtk-oss` edition from a pinned GitHub release, checked against
its SHA-256 and installed to `~/.local/bin`, or on macOS with Homebrew the
`rtk-ai/tap/rtk-oss` formula, unless an `rtk` (from Nix, for example) is
already on `PATH`. While it is on `PATH`, `./install` and the `bin/bob` and `bin/claude` wrappers
register `rtk hook claude` as a `PreToolUse` hook for Claude Code's `Bash`
tool and Bob's `execute_command` tool (and a filtered hook for Codex, below),
and remove them once rtk is gone. The
hook rewrites supported commands (`git`, `ls`, `grep`, test runners, ...) to
`rtk` equivalents that condense their output, saving tokens; other commands
run unchanged, and each agent's normal approval still applies. Condensed
output can omit detail (`rtk git log` drops commit bodies); an agent can run
`rtk proxy <command>` for the full output. `rtk gain` shows the savings.

Codex applies a rewritten command only when the hook also approves it, so
`$CODEX_HOME/hooks.json` (default `~/.codex/hooks.json`) gets
`scripts/codex-rtk-hook` instead: it passes only single read-only commands
(`git status|log|diff|show`, `ls`, `find`, `grep`, `rg`, `cat`, `head`, `tail`,
`wc`, without chaining, redirection or options that run programs) to
`rtk hook codex`; everything else keeps Codex's approval. Codex runs a new or
changed hook only after you trust it in the TUI (`/hooks`).
The [coverage review](docs/codex-rtk-coverage.md) records the installed versions,
fixture results and remaining runtime verification needed before expanding it.

## Neovim chat (optional)

Requires Neovim 0.11+, Nix on Linux x86_64, and authenticated Claude Code, IBM Bob Shell, or Codex.

```bash
bash scripts/install-nvim-acp
bash nix/apply
```

Restart Neovim and press `<leader>a` to open or close CodeCompanion chat. Press `Ctrl-S` to send; use `ga` in the chat to choose an agent. To choose at launch:

```bash
AGENT_CONFIG_ACP_AGENT=claude_code nvim .
AGENT_CONFIG_ACP_AGENT=bob nvim .
AGENT_CONFIG_ACP_AGENT=codex nvim .
```

For Claude token authentication, run `claude setup-token` and export `CLAUDE_CODE_OAUTH_TOKEN` before launching Neovim. Never commit tokens.

Codex uses [CodeCompanion's upstream `codex` ACP preset](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/adapters/acp/codex.lua).
Install the maintained [Codex ACP adapter](https://github.com/agentclientprotocol/codex-acp)
separately and put its `codex-acp` executable on Neovim's `PATH`:

```bash
npm install -g @agentclientprotocol/codex-acp
codex-acp --version
```

Use a CodeCompanion version that includes the `codex` preset. The old
`@zed-industries/codex-acp` package has moved to the package above. The adapter
speaks ACP over stdio and starts Codex app-server; it includes a compatible
Codex dependency. `CODEX_PATH` can explicitly select another binary. It does
not use this repository's terminal launcher. The upstream preset defaults to
API-key authentication (`OPENAI_API_KEY`); for ChatGPT authentication, configure
the preset's `defaults.auth_method = "chat-gpt"` in your CodeCompanion setup.
See the adapter's README for authentication and runtime options. The default
agent remains Bob when available, otherwise Claude; Codex is explicitly selected.

## Bob Shell (optional)

```bash
bash scripts/install-bob-shell
```

Uses IBM's official installer, not Nix. Bob authentication is separate.

Bob charges each request by the context it resends, so usage habits matter
more than settings:

- Start a new task for each topic instead of continuing an unrelated one.
- Hand off early: `/handoff` writes the note, then `bobtask handoff` continues
  in a new task with a small context.
- Read narrow line ranges of large files; rtk compresses only
  `execute_command` output, not `read_file`.
- Use `spawn_subagent` for broad exploration, so only its conclusion enters
  the main context.

## Experimental Bob Ralph (optional)

```bash
bash scripts/install-bob-ralph
```

Installs the experimental Ralph runner and Bob skills without running the loop. Test it only in a disposable repository.

## Codex Ralph (optional)

`codex-ralph` (Python 3, linked by `install`) runs bounded fresh `codex exec`
sessions in the current working directory. No external Ralph checkout is needed.

```bash
codex-ralph --prompt-file task.md --max-iterations 5 --check ./verify-task
```

Supply an executable completion check: exit **0** means complete, **1** requests
another iteration, and any other status stops with an error. Make the check
specific to the requested outcome; a generic passing test suite may not prove
that the task is implemented. The check runs directly as your user, outside the
Codex sandbox: use only a trusted script. Each successful Codex invocation is
followed by the check. CLI errors stop immediately; exhausting the limit exits 1.
Ctrl+C or SIGTERM stops the active process group and exits 130 or 143.
Changes already made remain on disk. Keep progress in workspace files because
conversation history is not resumed between iterations.

Unlike Claude's `ralph-loop` stop hook or the experimental Bob upstream adapter,
this runner uses the documented [non-interactive CLI](https://developers.openai.com/codex/noninteractive).
Checked against Codex CLI 0.160.0 (`exec --help`); no native Ralph command was
identified in that interface. It adds no approval, sandbox, trust-bypass, or
retry flags. Existing CLI configuration and any launcher on PATH apply; configure
appropriate permissions beforehand. Non-interactive approval failures stop the
run rather than triggering a permissions bypass. The iteration limit bounds
invocations, not wall time or token usage. No model-backed end-to-end run or
token savings are claimed.

## CLI session resume

Launchers live in `bin/` and dispatch to the original CLI. Enable them in interactive Bash or Zsh with one line anywhere in your startup file:

```bash
[[ -f "$HOME/agent-config/shell/aliases.sh" ]] && source "$HOME/agent-config/shell/aliases.sh"
```

Aliases take precedence however nvm, Nix or other startup files reorder `PATH` later. Scripts and other non-interactive callers still run the original CLIs.

| Tool | Current directory, latest | Current directory, picker | All directories |
| --- | --- | --- | --- |
| Bob | `bob` | `bobl` | `bobtask resume` |
| Claude Code | `claude` | `claudel` | In `claudel` picker, press `Ctrl+A` |
| Codex | `codex` | `codexl` | `codexla` |

To start a new session, run `<tool> new`; arguments after `new` are passed to the original CLI. Other arguments also dispatch to the original CLI, with the Codex default below:

| Tool | New session | New session with arguments |
| --- | --- | --- |
| Bob | `bob new` (`bob chat --auto-approve`) | `bob new --mode <mode>` |
| Claude Code | `claude new` | `claude new "<prompt>"` |
| Codex | `codex new` | `codex new "<prompt>"` |

None of the original CLIs has a `new` subcommand, so the launchers reserve it; to send `new` as the first prompt, run the original CLI (`\claude new`). When the current directory has no Claude Code session yet, `claude` starts a new one instead of failing with "No conversation found to continue". Claude Code and Codex have no `chat` subcommand; `claude chat` starts a new session with `chat` as the first prompt. A leading backslash skips the alias and runs the original CLI. Bob reads auto-approval only from command-line arguments (`--yolo` is a deprecated alias of `--auto-approve`).

Codex launchers default to `--approve-for-me`, including the latest-session
resume, `codex new`, direct prompts, resume pickers, fork, exec, review, and
`codex-delegate`. This selects automatic approval review with a workspace-write
sandbox; it does not bypass sandboxing or hook trust. See the
[official auto-review documentation](https://learn.chatgpt.com/docs/sandboxing/auto-review).
Explicit approval or sandbox flags, permission-related `-c`/`--config` overrides,
and profiles take precedence: the wrapper adds no default flag in those cases.
For example, `codex new --sandbox read-only` and
`codex resume --ask-for-approval on-request` retain exactly those choices.
An explicit `--approve-for-me` is passed through once.

The native resume pickers are used rather than custom fzf/database parsing.

For Codex session cleanup, transcript export, handoff, and Python tooling, see
[the native workflow comparison](docs/codex-session-language.md). It records
verified commands and the remaining differences from `clauderm`, `bobtask`,
and Claude's `pyright-lsp`; no additional picker or language server is installed.

To delete Claude Code sessions, run `clauderm` (requires Python 3 and fzf).
It lists the sessions of the current Git repository (or, outside Git, the
current directory), newest first, with their title and transcript path
(`~/.claude/projects/<project>/<session-id>.jsonl`). Sessions of nested
repositories are excluded. Select with `Tab`; after confirmation it removes the
transcript and that session's `projects/<project>/<session-id>/`,
`file-history/<session-id>` and `session-env/<session-id>` data. Project memory
is never touched.

`claude-stats` (requires Python 3) prints weekly token usage (sessions,
requests, total, input-equivalent weighted total and weighted per request) of
the last 10 weeks from `~/.claude/projects/**/*.jsonl`, honoring
`CLAUDE_CONFIG_DIR`. Each API request is counted once by its `requestId`, and
each session in the week (local time, from Monday) it started. `-w N` sets the
number of weeks (`0` for all). `ratio` and `ratio/req` give weighted and weighted
per request as a percentage of the week before (current ÷ previous; below 100%
is a reduction, 50% is half; `-` without data). Filter with `--since`, `--until`, `--project`
and `--min-requests`; `--split <time>` or `--split-commit <ref>` instead
compares the mean, standard deviation and median per session before and after
a time or commit; `--json` prints one row per session.

`bob-stats` (requires Python 3) prints the same weekly view for Bob tasks from
`~/.bob/db/bob.db`, opened read-only: tasks, requests, context tokens and cost,
in total and per request, with `-w N` as above; `ratio` and `ratio/req` give
cost and cost per request as a percentage of the week before. Bob records only the cost and
context tokens of each request, without an input, cache or output breakdown.

`codex-stats` (requires Python 3) prints the same weekly view as `claude-stats`
for Codex from the rollouts under `~/.codex/sessions` and
`~/.codex/archived_sessions`, honoring `CODEX_HOME`, with `-w N` as above. Each
model response is counted once by its `response_id`, and each rollout (subagent
threads included) as a session. The weighted total uses the GPT-5 price ratios:
cached input 0.1x and output 8x uncached input. The rollout format is internal
to Codex (observed in 0.160.0).

`bobtask` manages Bob tasks (requires Python 3 and fzf). Pickers show the
update time, the stored workspace (`project_id`, such as `file:/path/to/dir`),
title and task ID of resumable tasks from every directory. With `-c`
(`--current`), they list only the tasks of the current Git repository (or,
outside Git, the current directory) with the same rules as `clauderm`. Tasks
locked by a running Bob are neither listed nor changed.

| Command | Action |
| --- | --- |
| `bobtask list [-c]` (`ls`) | Print the same table without a picker |
| `bobtask resume [-c]` | Resume a task in its workspace directory |
| `bobtask rm [-c]` | Delete tasks; subtasks first, messages by cascade |
| `bobtask mv [-c] <dir>` | Move tasks and their subtasks to another workspace, keeping IDs |
| `bobtask dump [-c] [--json]` | Print transcripts as text (system prompts omitted), or raw JSON lines |
| `bobtask handoff [-c] [--tool-limit N]` | Start a new task in a task's workspace from its transcript |

`bobl` and `bobrm` are shortcuts for `bobtask resume -c` and `bobtask rm -c`.

In the `rm`, `mv` and `dump` pickers, `Tab` toggles a task, `Ctrl-A` selects
all listed tasks and `Ctrl-D` clears the selection. `rm` and `mv` ask for
confirmation. `mv` rewrites `project_id` and the task
environment's workspace as Bob's own import does; paths quoted in past messages
stay unchanged. The database schema is internal to Bob Shell (observed in
2.0.6).

`handoff` continues a task that Bob stopped, for example at its turn limit,
in a fresh context. It writes the transcript to
`$TMPDIR/bob-handoff/<task-id>.md`, keeping the first `N` (default 500)
characters of each tool output, then starts `bob chat` in the task's
workspace. To keep the transcript short, successful output of `read_file`,
`list_files` and `glob`, which the new task can get again, is left out, and
output repeating an earlier one is replaced by a pointer to it; the first
message asks the new task to read the start and the end of the transcript and
search the rest instead of reading all of it. Bob's interactive chat takes no initial prompt, so the first
message that points it at the transcript, or at the workspace's handoff note
when there is one (see [Agent handoff notes](#agent-handoff-notes)), is copied
to the clipboard (`pbcopy`, `wl-copy` or `xclip`) and printed; paste it to
start. Exit the
stopped Bob first: tasks locked by a running Bob are not listed.

The `bob` and `bob new` launchers do this on their own when a task stops at
its cost limit: after you exit Bob, they find the newest task of the current
project that was updated during the chat and has spent `session.maxCost`,
ask `Continue in a new task? [Y/n]`, and start a new chat from
`bobtask handoff --cost-limit-since <ms> --no-start`. Inside tmux, the first
message is typed into the new chat once its input box shows; elsewhere
paste it from the clipboard. Bob does not store its turn count, so a task
stopped at the turn limit is not detected; run `bobtask handoff` for it.

## Tests

`tests/run` runs every `tests/*.sh` (or the files given) and prints only the
failures, each with the end of its output, and a one-line summary; it exits 1
if any test fails.
