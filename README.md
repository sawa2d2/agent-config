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

## Components

Launchers (`bin/`):

- `claude`, `bob`, `codex`: resume the latest session in the current directory; `<tool> new` starts a new one. They refresh managed settings and hooks on launch.
- `claudel`, `bobl`, `codexl`, `codexla`: session pickers (current directory; `codexla` for all directories).
- `agent-delegate`, `bob-delegate`, `codex-delegate`: start a new branch in a new worktree and tmux window with the same agent.
- `bobtask`: list, resume, delete, move, dump or hand off Bob tasks (`bobrm` = `bobtask rm -c`).
- `clauderm`: delete Claude Code sessions of the current repository.
- `codexrm`: delete Codex sessions of the current repository (with their subagent threads).
- `claude-stats`, `codex-stats`, `bob-stats`: token/cost usage per week or per fixed window (`--window`).
- `codex-ralph`: bounded loop of fresh `codex exec` runs until a check passes.

Each script except the `claude`, `bob` and `codex` launchers (which pass it to the real CLI) prints its usage with `--help`; header comments in `bin/` and `scripts/` document the details.

Installed by `./install` (`scripts/`):

- Skills from `deploy/skills/` (`handoff`, `autonomous-development`) plus upstream skills, Spec Kit, rtk and Claude Code plugins (`install-tools`, `install-skill`, `install-rtk`, `install-claude-plugins`).
- Agent settings and themes (`install-claude-settings`, `install-bob-settings`, `install-bob-theme`, `install-codex-theme`, `install-codex-compaction`, `install-codex-subagent-model`).
- Hooks (`install-agent-hooks`): tmux window status (`agent-tmux-status`), `approved` merge marker (`agent-approval-marker`), handoff suggestions and rtk output compression.

Further documentation:

- [Codex handoff support](deploy/codex/handoff.md)
- [Codex skill metadata audit](docs/codex-skill-metadata.md)
- [Codex rtk coverage](docs/codex-rtk-coverage.md)
- [Codex session management and language tooling](docs/codex-session-language.md)
- [Claude Code 1-hour cache writes](docs/claude-cache-writes.md)
- [Isolating agent work under a dedicated user](docs/dev-user-isolation.md)

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
