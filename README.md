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
│       ├── prd/                # snarktank/ralph
│       ├── ralph/              # snarktank/ralph
│       └── .../
├── .claude/
│   ├── rules/
│   │   └── karpathy.md
│   ├── skills/
│   │   ├── grill-me/
│   │   ├── grill-with-docs/
│   │   ├── grilling/
│   │   └── domain-modeling/
│   └── plugins/                 # Superpowers + Ralph Loop (official)
│       └── .../
└── .local/
    └── bin/
        └── specify             # Spec Kit (uv default)
```

## Experimental Bob Ralph

Run `bash scripts/install-bob-ralph` explicitly to install experimental Bob Ralph; the standard `bash ./install` does not install it. This separate installer fetches [snarktank/ralph](https://github.com/snarktank/ralph), applies `deploy/ralph/bob.patch` (a small Bob Shell 2.x backend adapter), and stores the result at `~/.local/share/agent-config/ralph`. It also installs the upstream `prd` and `ralph` skills into `~/.bob/skills/`, without executing the loop. The skills prepare PRDs; `ralph.sh` runs the loop. Existing unmanaged skills are left intact (identical copies are skipped; differing copies require manual resolution). This is experimental and not validated for production use. The old Heidloff demo is no longer installed.

To prepare a **disposable Git repository** for a later smoke test:

```bash
src="$HOME/.local/share/agent-config/ralph"
trial="$(mktemp -d "$HOME/ralph-test.XXXXXX")"
cd "$trial"
git init -b main
mkdir -p scripts/ralph
cp "$src/ralph.sh" "$src/CLAUDE.md" scripts/ralph/
cp "$src/prd.json.example" scripts/ralph/prd.json
# Edit scripts/ralph/prd.json to set branchName and small test stories.
# Set up Bob Shell 2.x authentication before executing.
# bash scripts/ralph/ralph.sh --tool bob 1
```

The commented-out command is deliberately not run by the installer. The adapter currently reuses upstream's Claude-oriented `CLAUDE.md`, caps Bob at 10 turns / 0.5 cost units per iteration, and has not been smoke-tested. Upstream may commit, create branches, or modify files; use an isolated repository. Upstream currently suppresses per-agent command errors with `|| true`, so verify progress and exit behavior before real use.
