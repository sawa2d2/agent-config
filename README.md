# agent-config

Shared configuration and tooling for Bob, Claude Code, and Codex. No dotfiles dependency.

## Install

Requires Git.

```bash
curl -fsSL https://raw.githubusercontent.com/sawa2d2/agent-config/main/bootstrap.sh | bash
```

Clones into `~/agent-config` (override with `AGENT_CONFIG_DIR`) and runs the existing installer. An existing Git checkout is reused without pulling; other existing destinations are not overwritten.

Installs global instructions, agent skills, Spec Kit, Claude Code CLI and its ACP adapter (via Nix when available). Existing unmanaged instructions are protected.

## Claude Code theme

`./install` enables `custom:agent-config-selected`. User message backgrounds
follow the saved dotfiles theme variant (default: teal), with a darker shade
for contrast against Claude Code's light text. It also sets `"tui": "default"`
when no renderer is configured, so output stays in terminal and tmux scrollback;
an explicit `/tui fullscreen` choice is kept. Other settings in
`~/.claude/settings.json` are preserved. Python 3 is required.

To refresh these settings on every new Claude CLI session, ensure `~/agent-config/bin` precedes the original Claude executable in `PATH`. The `bin/claude` wrapper refreshes them and then executes the real CLI with its original arguments. On Linux with X11 forwarding (`ssh -X`, `DISPLAY` set) and `xclip` installed, it also unsets `SSH_CONNECTION`, `SSH_TTY` and `SSH_CLIENT`, because Claude Code otherwise copies only via OSC 52, which terminals such as GNOME Terminal ignore. To refresh manually instead, run:

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

To start a new session, pass any argument so the launcher dispatches to the original CLI:

| Tool | New session | Empty new session |
| --- | --- | --- |
| Bob | `bob chat --auto-approve` | Same |
| Claude Code | `claude "<prompt>"` | `\claude` |
| Codex | `codex "<prompt>"` | `\codex` |

Claude Code and Codex have no `chat` subcommand; `claude chat` starts a new session with `chat` as the first prompt. A leading backslash skips the alias and runs the original CLI. Bob reads auto-approval only from command-line arguments (`--yolo` is a deprecated alias of `--auto-approve`).

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

`bobl` and `bobrm` are shortcuts for `bobtask resume -c` and `bobtask rm -c`.

In the `rm`, `mv` and `dump` pickers, `Tab` toggles a task, `Ctrl-A` selects
all listed tasks and `Ctrl-D` clears the selection. `rm` and `mv` ask for
confirmation. `mv` rewrites `project_id` and the task
environment's workspace as Bob's own import does; paths quoted in past messages
stay unchanged. The database schema is internal to Bob Shell (observed in
2.0.6).
