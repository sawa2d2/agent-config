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
case $1 in
  display-message)
    case ${!#} in
      '#{session_id}') echo '$7' ;;
      '#{pane_dead}') echo 0 ;;
      '#{pane_pid}') echo 100 ;;
      '#{@delegate_ready}') cat "$TEST_ROOT/ready" ;;
    esac ;;
  new-window) echo %9 ;;
  send-keys)
    if [[ ${!#} == *'@delegate_ready'* ]]; then
      printf '%s' "${!#}" > "$TEST_ROOT/probe"
    elif [[ ${!#} == Enter && -f $TEST_ROOT/probe ]]; then
      bash -c "$(cat "$TEST_ROOT/probe")"
      rm "$TEST_ROOT/probe"
    fi ;;
  set-option) printf '%s\n' "${!#}" > "$TEST_ROOT/ready" ;;
  capture-pane) echo '❯' ;;
  load-buffer) cat > "$TEST_ROOT/pasted" ;;
esac
SH
cat > "$tmp/fake/ps" <<'SH'
#!/usr/bin/env bash
echo '100 1 bash bash'
echo '101 100 claude claude'
SH
chmod +x "$tmp/fake/gwt-path" "$tmp/fake/tmux" "$tmp/fake/ps"
export TEST_ROOT="$tmp" PATH="$tmp/fake:$PATH" TMUX=/tmp/fake,1,0 TMUX_PANE=%1
# A fake home keeps the trust entry out of the real ~/.claude.json.
mkdir -p "$tmp/home"
echo '{"projects":{"/other":{"hasTrustDialogAccepted":false}},"numStartups":3}' > "$tmp/home/.claude.json"
export HOME="$tmp/home"
git init -q "$tmp/repo"
cd "$tmp/repo"

# Without a note or a prompt nothing is created.
if "$root/bin/agent-delegate" feat/x 2>/dev/null; then fail 'ran without a note or prompt'; fi
[[ ! -e $tmp/worktrees && ! -e $tmp/tmux.log ]] || fail 'created a worktree or window without a note'

# The note moves into the new worktree and claude is typed into a detached window.
echo note > .agent-handoff.md
"$root/bin/agent-delegate" feat/x > /dev/null
[[ ! -e .agent-handoff.md && $(cat "$tmp/worktrees/feat/x/.agent-handoff.md") == note ]] || fail 'note was not moved'
grep -qx "new-window -d -t \$7 -n feat/x -c $tmp/worktrees/feat/x -P -F #{pane_id}" "$tmp/tmux.log" || fail "window: $(cat "$tmp/tmux.log")"
grep -Fqx "send-keys -t %9 -l \$'claude' \$'Read .agent-handoff.md and continue the work it describes.'" "$tmp/tmux.log" || fail "keys: $(cat "$tmp/tmux.log")"
grep -qx 'send-keys -t %9 Enter' "$tmp/tmux.log" || fail 'Enter was not sent'
# The new worktree is trusted; the rest of the config is kept.
jq -e --arg dir "$tmp/worktrees/feat/x" \
  '.projects[$dir].hasTrustDialogAccepted == true and .projects["/other"].hasTrustDialogAccepted == false and .numStartups == 3' \
  "$HOME/.claude.json" > /dev/null || fail "trust: $(cat "$HOME/.claude.json")"

# An explicit prompt works without a note.
: > "$tmp/tmux.log"
"$root/bin/agent-delegate" feat/y "fix the build" > /dev/null
grep -Fqx "send-keys -t %9 -l \$'claude' \$'fix the build'" "$tmp/tmux.log" || fail "prompt: $(cat "$tmp/tmux.log")"

# A model is passed through to claude; a missing model value is rejected.
: > "$tmp/tmux.log"
"$root/bin/agent-delegate" --model sonnet feat/m "merge it" > /dev/null
grep -Fqx "send-keys -t %9 -l \$'claude' \$'--model' \$'sonnet' \$'merge it'" "$tmp/tmux.log" || fail "model: $(cat "$tmp/tmux.log")"
if "$root/bin/agent-delegate" -m 2>/dev/null; then fail 'ran with -m and no model'; fi

# A prompt beginning with '-' remains a positional helper argument.
"$root/bin/agent-delegate" feat/literal --literal > /dev/null

# Outside tmux it refuses.
if TMUX= "$root/bin/agent-delegate" feat/z "x" 2>/dev/null; then fail 'ran outside tmux'; fi

echo 'PASS: agent-delegate'
