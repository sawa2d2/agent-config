# agent-config

Shared configuration and tooling for Bob, Claude Code, and Codex. No dotfiles dependency.

## Install

```bash
git clone https://github.com/sawa2d2/agent-config.git
cd agent-config
bash ./install
```

Installs global instructions, agent skills, Spec Kit, Claude Code CLI and its ACP adapter (via Nix when available). Existing unmanaged instructions are protected.

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
