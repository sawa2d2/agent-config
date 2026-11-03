#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake gwt-path creates the worktree directory; fake tmux records its calls.
mkdir -p "$tmp/fake"
cat > "$tmp/fake/gwt-path" <<'SH'
#!/usr/bin/env bash
[[ $1 == -b ]] || exit 2
mkdir -p "$TEST_ROOT/worktrees/$2"
printf '%s\n' "$TEST_ROOT/worktrees/$2"
SH
cat > "$tmp/fake/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_ROOT/tmux.log"
[[ $1 == split-window ]] && echo %9
exit 0
SH
chmod +x "$tmp/fake/gwt-path" "$tmp/fake/tmux"
export TEST_ROOT="$tmp" PATH="$tmp/fake:$PATH" TMUX=/tmp/fake,1,0 TMUX_PANE=%1
# Isolate Codex configuration and ensure delegation leaves it untouched.
mkdir -p "$tmp/home/.codex"
printf 'model = "test"\n' > "$tmp/home/.codex/config.toml"
export HOME="$tmp/home"
cp "$HOME/.codex/config.toml" "$tmp/config.before"
git init -q "$tmp/repo"
cd "$tmp/repo"

# Without a note or a prompt nothing is created.
if "$root/bin/codex-delegate" feat/x 2>/dev/null; then fail 'ran without a note or prompt'; fi
[[ ! -e $tmp/worktrees && ! -e $tmp/tmux.log ]] || fail 'created a worktree or pane without a note'

# The note moves into the new worktree and codex is typed into a detached pane.
echo note > .agent-handoff.md
"$root/bin/codex-delegate" feat/x > /dev/null
[[ ! -e .agent-handoff.md && $(cat "$tmp/worktrees/feat/x/.agent-handoff.md") == note ]] || fail 'note was not moved'
grep -qx "split-window -d -v -b -t %1 -c $tmp/worktrees/feat/x -P -F #{pane_id}" "$tmp/tmux.log" || fail "split: $(cat "$tmp/tmux.log")"
grep -qx 'send-keys -t %9 -l codex new Read\\ .agent-handoff.md\\ and\\ continue\\ the\\ work\\ it\\ describes.' "$tmp/tmux.log" || fail "keys: $(cat "$tmp/tmux.log")"
grep -qx 'send-keys -t %9 Enter' "$tmp/tmux.log" || fail 'Enter was not sent'
cmp "$tmp/config.before" "$HOME/.codex/config.toml" || fail 'Codex config changed'

# An explicit prompt works without a note.
: > "$tmp/tmux.log"
"$root/bin/codex-delegate" feat/y 'fix the build; $(touch injected)' > /dev/null
grep -Fxq "send-keys -t %9 -l codex new $(printf '%q' 'fix the build; $(touch injected)')" "$tmp/tmux.log" || fail "prompt: $(cat "$tmp/tmux.log")"

# Execute the recorded shell input to verify it preserves one literal argument.
cat > "$tmp/fake/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_ROOT/codex.args"
SH
chmod +x "$tmp/fake/codex"
command_line=$(sed -n 's/^send-keys -t %9 -l //p' "$tmp/tmux.log")
PATH="$root/bin:$PATH" bash -c "$command_line"
[[ $(cat "$tmp/codex.args") == $'--approve-for-me\nfix the build; $(touch injected)' ]] || fail 'prompt arguments changed'
[[ ! -e injected ]] || fail 'prompt executed as shell code'

# Outside tmux it refuses.
if TMUX= "$root/bin/codex-delegate" feat/z "x" 2>/dev/null; then fail 'ran outside tmux'; fi

echo 'PASS: codex-delegate'
