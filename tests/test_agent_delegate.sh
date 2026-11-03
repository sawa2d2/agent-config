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
# A fake home keeps the trust entry out of the real ~/.claude.json.
mkdir -p "$tmp/home"
echo '{"projects":{"/other":{"hasTrustDialogAccepted":false}},"numStartups":3}' > "$tmp/home/.claude.json"
export HOME="$tmp/home"
git init -q "$tmp/repo"
cd "$tmp/repo"

# Without a note or a prompt nothing is created.
if "$root/bin/agent-delegate" feat/x 2>/dev/null; then fail 'ran without a note or prompt'; fi
[[ ! -e $tmp/worktrees && ! -e $tmp/tmux.log ]] || fail 'created a worktree or pane without a note'

# The note moves into the new worktree and claude is typed into a detached pane.
echo note > .agent-handoff.md
"$root/bin/agent-delegate" feat/x > /dev/null
[[ ! -e .agent-handoff.md && $(cat "$tmp/worktrees/feat/x/.agent-handoff.md") == note ]] || fail 'note was not moved'
grep -qx "split-window -d -v -b -t %1 -c $tmp/worktrees/feat/x -P -F #{pane_id}" "$tmp/tmux.log" || fail "split: $(cat "$tmp/tmux.log")"
grep -qx 'send-keys -t %9 -l claude Read\\ .agent-handoff.md\\ and\\ continue\\ the\\ work\\ it\\ describes.' "$tmp/tmux.log" || fail "keys: $(cat "$tmp/tmux.log")"
grep -qx 'send-keys -t %9 Enter' "$tmp/tmux.log" || fail 'Enter was not sent'
# The new worktree is trusted; the rest of the config is kept.
jq -e --arg dir "$tmp/worktrees/feat/x" \
  '.projects[$dir].hasTrustDialogAccepted == true and .projects["/other"].hasTrustDialogAccepted == false and .numStartups == 3' \
  "$HOME/.claude.json" > /dev/null || fail "trust: $(cat "$HOME/.claude.json")"

# An explicit prompt works without a note.
: > "$tmp/tmux.log"
"$root/bin/agent-delegate" feat/y "fix the build" > /dev/null
grep -qx 'send-keys -t %9 -l claude fix\\ the\\ build' "$tmp/tmux.log" || fail "prompt: $(cat "$tmp/tmux.log")"

# Outside tmux it refuses.
if TMUX= "$root/bin/agent-delegate" feat/z "x" 2>/dev/null; then fail 'ran outside tmux'; fi

echo 'PASS: agent-delegate'
