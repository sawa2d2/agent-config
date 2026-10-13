# agent-config

## Install

```bash
cd agent-config
bash ./install
```

The installer deploys:

```text
~/
├── .bob/
│   └── rules/
│       └── karpathy.md
└── .claude/
    └── rules/
        └── karpathy.md
```

External tools installed by `./install`:

- Bob/Claude: `~/.bob/skills/{grill-me,grill-with-docs,grilling,domain-modeling}/` and matching `~/.claude/skills/`.
- Bob: Superpowers skill directories under `~/.bob/skills/`.
- Claude: official `superpowers@claude-plugins-official` plugin (user scope).
- Spec Kit: `specify` CLI via `uv tool install specify-cli` (requires `uv`).

Initialize Spec Kit **per project** using `specify init --here --integration bob` or `specify init --here --integration claude`. Superpowers on Bob is skills-only (no Claude plugin hooks).

Sources: [grill-me](https://github.com/joshuawheelock/grill-me), [Matt Pocock skills](https://github.com/mattpocock/skills), [Superpowers](https://github.com/obra/superpowers), [Spec Kit](https://github.com/github/spec-kit).
