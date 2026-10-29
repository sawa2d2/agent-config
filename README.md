# agent-config

Shared configuration and tooling for Bob, Claude Code, and Codex. No dotfiles dependency.

## Install

Requires Git.

```bash
curl -fsSL https://raw.githubusercontent.com/sawa2d2/agent-config/main/bootstrap.sh | bash
```

Clones into `~/agent-config` (override with `AGENT_CONFIG_DIR`) and runs the existing installer. An existing Git checkout is reused without pulling; other existing destinations are not overwritten.

Installs global instructions, agent skills, Spec Kit, Claude Code CLI and its ACP adapter (via Nix when available), and the Claude Code plugins `superpowers`, `ralph-loop` and `pyright-lsp` from the official marketplace (`scripts/install-claude-plugins`). `pyright-lsp` needs `pyright-langserver` on `PATH`; an existing one is reused, otherwise Nix adds `pyright`. Re-running skips what is already installed. Existing unmanaged instructions are protected.

## Skills

Skills in `deploy/skills/` are copied to `~/.bob/skills`, `~/.claude/skills` and `~/.codex/skills` by `./install`, alongside upstream skills from `scripts/install-tools`. Copies carry a `.agent-config-managed` marker; a skill of the same name installed some other way is never overwritten.

| Skill | Use |
| --- | --- |
| `autonomous-development` | Invoked by name only (`/autonomous-development`): route an objective to superpowers, Spec Kit or ralph-loop, and run long work with stacked branches, a progress file in the Git directory and batched user checks |

## Claude Code theme

`./install` enables `custom:agent-config-selected`. User message backgrounds
follow the saved dotfiles theme variant (default: teal), with a darker shade
for contrast against Claude Code's light text. It also sets `"tui": "default"`
when no renderer is configured, so output stays in terminal and tmux scrollback;
an explicit `/tui fullscreen` choice is kept. Other settings in
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

## Bob Shell settings

`./install` and the `bin/bob` wrapper add these defaults to
`~/.bob/settings/settings.json` only when the key is missing, so values you set
yourself are kept:

| Key | Value | Effect |
| --- | --- | --- |
| `session.maxTurns` | `300` | Turn limit per task (Bob's default is 100) |
| `session.limitWarnings` | `true` | Tell the agent to wrap up five turns before the limit |

To continue a stopped task in a fresh context, see `bobtask handoff`.

## tmux agent status

`./install` and the `bin/bob` and `bin/claude` wrappers register
`scripts/agent-tmux-status` as Bob Shell and Claude Code hooks (in
`~/.bob/settings/settings.json` and `~/.claude/settings.json`; other hooks are
kept). Inside tmux, it marks the window the agent runs in. `@agent_attention`
is `1` once the agent needed you, also in the window you are looking at, and
stays through resumed work until you submit a prompt there; `@agent_status`
keeps the detail:

| State | Attention | Set when |
| --- | --- | --- |
| `working` | cleared by a prompt, otherwise kept | A prompt is sent or a tool runs |
| `waiting` | `1` | Claude Code asks for a permission |
| `done` | `1` | The agent finished its reply |
| `stale` | `1` | `working` without updates for `@agent_status_stale_after` seconds (default 300): a hang, an error, or Bob waiting for approval (Bob has no event for it) |

A tmux configuration may also unset `@agent_attention` when a window is
selected.
A new Bob session or the end of a Claude Code session clears the mark. The
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

## Neovim chat (optional)

Requires Neovim 0.11+, Nix on Linux x86_64, and authenticated Claude Code or IBM Bob Shell.

```bash
bash scripts/install-nvim-acp
bash nix/apply
```

Restart Neovim and press `<leader>a` to open or close CodeCompanion chat. Press `Ctrl-S` to send; use `ga` in the chat to choose an agent. To choose at launch:

```bash
AGENT_CONFIG_ACP_AGENT=claude_code nvim .
AGENT_CONFIG_ACP_AGENT=bob nvim .
```

For Claude token authentication, run `claude setup-token` and export `CLAUDE_CODE_OAUTH_TOKEN` before launching Neovim. Never commit tokens.

## Bob Shell (optional)

```bash
bash scripts/install-bob-shell
```

Uses IBM's official installer, not Nix. Bob authentication is separate.

## Experimental Bob Ralph (optional)

```bash
bash scripts/install-bob-ralph
```

Installs the experimental Ralph runner and Bob skills without running the loop. Test it only in a disposable repository.

## CLI session resume

Launchers live in `bin/` and dispatch to the original CLI when any arguments are supplied. Enable them in interactive Bash or Zsh with one line anywhere in your startup file:

```bash
[[ -f "$HOME/agent-config/shell/aliases.sh" ]] && source "$HOME/agent-config/shell/aliases.sh"
```

Aliases take precedence however nvm, Nix or other startup files reorder `PATH` later. Scripts and other non-interactive callers still run the original CLIs.

| Tool | Current directory, latest | Current directory, picker | All directories |
| --- | --- | --- | --- |
| Bob | `bob` | `bobl` | `bobtask resume` |
| Claude Code | `claude` | `claudel` | In `claudel` picker, press `Ctrl+A` |
| Codex | `codex` | `codexl` | `codexla` |

To start a new session, run `<tool> new`; arguments after `new` are passed to the original CLI. Any other argument also dispatches to the original CLI unchanged:

| Tool | New session | New session with arguments |
| --- | --- | --- |
| Bob | `bob new` (`bob chat --auto-approve`) | `bob new --mode <mode>` |
| Claude Code | `claude new` | `claude new "<prompt>"` |
| Codex | `codex new` | `codex new "<prompt>"` |

None of the original CLIs has a `new` subcommand, so the launchers reserve it; to send `new` as the first prompt, run the original CLI (`\claude new`). When the current directory has no Claude Code session yet, `claude` starts a new one instead of failing with "No conversation found to continue". Claude Code and Codex have no `chat` subcommand; `claude chat` starts a new session with `chat` as the first prompt. A leading backslash skips the alias and runs the original CLI. Bob reads auto-approval only from command-line arguments (`--yolo` is a deprecated alias of `--auto-approve`).

The native resume pickers are used rather than custom fzf/database parsing.

To delete Claude Code sessions, run `clauderm` (requires Python 3 and fzf).
It lists the sessions of the current Git repository (or, outside Git, the
current directory), newest first, with their title and transcript path
(`~/.claude/projects/<project>/<session-id>.jsonl`). Sessions of nested
repositories are excluded. Select with `Tab`; after confirmation it removes the
transcript and that session's `projects/<project>/<session-id>/`,
`file-history/<session-id>` and `session-env/<session-id>` data. Project memory
is never touched.

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
`$TMPDIR/bob-handoff/<task-id>.md`, keeping the first `N` (default 2000)
characters of each tool output, then starts `bob chat` in the task's
workspace. Bob's interactive chat takes no initial prompt, so the first
message that points it at the transcript is copied to the clipboard
(`pbcopy`, `wl-copy` or `xclip`) and printed; paste it to start. Exit the
stopped Bob first: tasks locked by a running Bob are not listed.
