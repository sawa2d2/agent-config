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
│   ├── rules/
│   │   └── karpathy.md
│   └── skills/
│       ├── grill-me/
│       ├── grill-with-docs/
│       ├── grilling/
│       ├── domain-modeling/
│       ├── brainstorming/       # Superpowers (example)
│       └── .../
├── .claude/
│   ├── rules/
│   │   └── karpathy.md
│   ├── skills/
│   │   ├── grill-me/
│   │   ├── grill-with-docs/
│   │   ├── grilling/
│   │   └── domain-modeling/
│   └── plugins/                 # Superpowers via Claude plugin manager
│       └── .../
└── .local/
    └── bin/
        ├── specify             # Spec Kit (uv default)
        └── ralph               # Ralph pilot
```

## Ralph trial

```bash
mkdir -p /tmp/ralph-demo && cd /tmp/ralph-demo
git init
ralph init --demo
ralph doctor
ralph run 1
```

This is a minimal Claude Code fresh-context loop, not the upstream snarktank/ralph CLI. It does not auto-commit or bypass permission checks. Use a disposable repository.
