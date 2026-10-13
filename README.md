# agent-config

Shared global coding guidance for IBM Bob (IDE / Shell) and Claude Code.

The repository keeps one canonical set of Karpathy-inspired engineering guidelines in `guidelines/karpathy.md`.

## Install

```bash
git clone https://github.com/sawa2d2/agent-config.git
cd agent-config
bash ./install
```

The installer deploys:

- `~/.bob/rules/karpathy.md` — global rules for Bob IDE and Bob Shell.
- `~/.claude/CLAUDE.md` — global Claude Code instructions, in an `agent-config` managed block.

Edit `guidelines/karpathy.md` and rerun `./install` to synchronize updates. The installer is idempotent, keeps unrelated Claude instructions, and refuses to overwrite an unrecognized Bob rules file or a symlink destination.

If the executable bit is missing after checkout, run `chmod +x install` once (or use `bash ./install`).

Bob's global rules: https://bob.ibm.com/docs/shell/configuration/bobshell-custom-rules

Claude Code memory: https://docs.anthropic.com/en/docs/claude-code/memory
