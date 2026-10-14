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
│   └── plugins/                 # Superpowers + Ralph Loop (official)
│       └── .../
└── .local/
    └── bin/
        └── specify             # Spec Kit (uv default)
```


## Bob Ralph trial

The installer fetches [nheidloff/bob-ralph-wiggum](https://github.com/nheidloff/bob-ralph-wiggum) into `~/.local/share/agent-config/bob-ralph-wiggum` without running it. The upstream sample requires Podman and a Bob Shell API key. Test it in a disposable copy: its `init-bob.sh` deletes the copy's `.git`, builds a container image, and its loop runs file-writing and shell tools and commits changes.

```bash
trial="$(mktemp -d)"
cp -a "$HOME/.local/share/agent-config/bob-ralph-wiggum/." "$trial/"
cd "$trial"

export BOBSHELL_API_KEY="..."  # obtain from Bob Shell
export GIT_USER_NAME="$(git config --global user.name)"
export GIT_USER_EMAIL="$(git config --global user.email)"

sh init-bob.sh
sh start-container-bob.sh
```

Inside the container, verify Bob authentication first, then run one iteration before the loop:

```bash
bob --auth-method api-key -p "Hi"
sh ../ralph/iteration.sh
# Optional: sh ../ralph/loop.sh
```

The upstream example is a personal experiment, not an IBM-supported Bob plugin. Inspect the scripts before running them; avoid real repositories or credentials with broader access than necessary.
