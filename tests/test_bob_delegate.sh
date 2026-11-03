#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake gwt-path creates the worktree directory; fake tmux records its calls and
# returns the input box marker (❯) on capture-pane so the background waiter
# does not block.
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
if [[ $1 == split-window ]]; then
  echo %9
elif [[ $1 == capture-pane && $2 == -p ]]; then
  # Return the Bob input prompt so the background waiter exits immediately.
  echo '❯'
fi
exit 0
SH
chmod +x "$tmp/fake/gwt-path" "$tmp/fake/tmux"
export TEST_ROOT="$tmp" PATH="$tmp/fake:$PATH" TMUX=/tmp/fake,1,0 TMUX_PANE=%1
git init -q "$tmp/repo"
cd "$tmp/repo"

# Without a note or a prompt nothing is created.
if "$root/bin/bob-delegate" feat/x 2>/dev/null; then fail 'ran without a note or prompt'; fi
[[ ! -e $tmp/worktrees && ! -e $tmp/tmux.log ]] || fail 'created a worktree or pane without a note'

# The note moves into the new worktree, bob new is started, and the handoff
# prompt is typed into the pane.
echo note > .agent-handoff.md
"$root/bin/bob-delegate" feat/x > /dev/null
# Wait briefly for the background subshell to send the prompt.
sleep 1
[[ ! -e .agent-handoff.md && $(cat "$tmp/worktrees/feat/x/.agent-handoff.md") == note ]] || fail 'note was not moved'
grep -qx "split-window -d -v -b -t %1 -c $tmp/worktrees/feat/x -P -F #{pane_id}" "$tmp/tmux.log" || fail "split: $(cat "$tmp/tmux.log")"
grep -qx 'send-keys -t %9 -l bob new' "$tmp/tmux.log" || fail "bob new: $(cat "$tmp/tmux.log")"
grep -qx 'send-keys -t %9 Enter' "$tmp/tmux.log" || fail 'Enter was not sent'
# The handoff prompt is typed after the input box appears.
grep -qx 'send-keys -t %9 -l Read .agent-handoff.md and continue the work it describes.' "$tmp/tmux.log" || fail "prompt: $(cat "$tmp/tmux.log")"

# An explicit prompt works without a note.
: > "$tmp/tmux.log"
"$root/bin/bob-delegate" feat/y "fix the build" > /dev/null
sleep 1
grep -qx 'send-keys -t %9 -l fix the build' "$tmp/tmux.log" || fail "explicit prompt: $(cat "$tmp/tmux.log")"

# Outside tmux it refuses.
if TMUX= "$root/bin/bob-delegate" feat/z "x" 2>/dev/null; then fail 'ran outside tmux'; fi

echo 'PASS: bob-delegate'
