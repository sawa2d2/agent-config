#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Fake gwt-path creates the worktree directory; fake tmux records its calls and
# acknowledges shell readiness and returns a ready Bob input box.
mkdir -p "$tmp/fake"
cat > "$tmp/fake/gwt-path" <<'SH'
#!/usr/bin/env bash
[[ $1 == -b ]] || exit 2
git worktree add -q -b "$2" "$TEST_ROOT/worktrees/$2"
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
echo '101 100 bob bob'
SH
chmod +x "$tmp/fake/gwt-path" "$tmp/fake/tmux" "$tmp/fake/ps"
export TEST_ROOT="$tmp" PATH="$tmp/fake:$PATH" TMUX=/tmp/fake,1,0 TMUX_PANE=%1
# A fake home keeps the trust entry out of the real ~/.bob/trustedFolders.json.
mkdir -p "$tmp/home/.bob"
echo '{"version":1,"folders":{"/other":"TRUST_FOLDER"}}' > "$tmp/home/.bob/trustedFolders.json"
export HOME="$tmp/home"
git init -q "$tmp/repo"
cd "$tmp/repo"
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

# Without a note or a prompt nothing is created.
if "$root/bin/bob-delegate" feat/x 2>/dev/null; then fail 'ran without a note or prompt'; fi
[[ ! -e $tmp/worktrees && ! -e $tmp/tmux.log ]] || fail 'created a worktree or window without a note'

# The note moves into the new worktree, bob chat is started, and the handoff
# prompt is typed into the pane.
echo note > .agent-handoff.md
"$root/bin/bob-delegate" feat/x > /dev/null
[[ ! -e .agent-handoff.md && $(cat "$tmp/worktrees/feat/x/.agent-handoff.md") == note ]] || fail 'note was not moved'
grep -qx "new-window -d -t \$7 -n feat/x -c $tmp/worktrees/feat/x -P -F #{pane_id}" "$tmp/tmux.log" || fail "window: $(cat "$tmp/tmux.log")"
grep -Fqx "send-keys -t %9 -l -- \$'$root/bin/bob' \$'chat' \$'--auto-approve'" "$tmp/tmux.log" || fail "bob chat: $(cat "$tmp/tmux.log")"
grep -qx 'send-keys -t %9 Enter' "$tmp/tmux.log" || fail 'Enter was not sent'
# The handoff prompt is typed after the input box appears.
[[ $(cat "$tmp/pasted") == "Read .agent-handoff.md and continue the work it describes." ]] || fail "prompt: $(cat "$tmp/tmux.log")"

# The new worktree is trusted; the existing entries are kept.
jq -e --arg dir "$tmp/worktrees/feat/x" \
  '.version == 1 and .folders[$dir] == "TRUST_FOLDER" and .folders["/other"] == "TRUST_FOLDER"' \
  "$HOME/.bob/trustedFolders.json" > /dev/null || fail "trust: $(cat "$HOME/.bob/trustedFolders.json")"

# Workspace hooks report each turn end and the session end; .bob stays untracked.
wt=$tmp/worktrees/feat/x
run_hook() { bash -c "$(jq -r --arg e "$1" '.hooks[$e][0].hooks[0].command' "$wt/.bob/settings.json")" <<< "$2"; }
run_hook Stop '{"session_id":"s1","cwd":"/w","last_assistant_message":"done: tests pass"}'
jq -e '.event == "Stop" and .session_id == "s1" and .last_assistant_message == "done: tests pass" and (.at | length) > 0' \
  "$wt/.bob/delegate-status.json" > /dev/null || fail "Stop report: $(cat "$wt/.bob/delegate-status.json")"
run_hook SessionEnd '{"session_id":"s1","reason":"exit"}'
jq -e '.event == "SessionEnd" and .reason == "exit" and .last_assistant_message == "done: tests pass"' \
  "$wt/.bob/delegate-status.json" > /dev/null || fail "SessionEnd report: $(cat "$wt/.bob/delegate-status.json")"
[[ -z $(git -C "$wt" status --porcelain --ignored=no -- .bob) ]] || fail ".bob not excluded: $(git -C "$wt" status --porcelain -- .bob)"

# A repository that tracks .bob/settings.json keeps it untouched.
mkdir .bob && echo '{}' > .bob/settings.json
git add -f .bob/settings.json && git -c user.name=t -c user.email=t@t commit -q -m bob
"$root/bin/bob-delegate" feat/tracked "x" > /dev/null 2>&1
[[ $(cat "$tmp/worktrees/feat/tracked/.bob/settings.json") == '{}' ]] || fail 'tracked settings changed'

# A missing trust file is created.
rm "$HOME/.bob/trustedFolders.json"
"$root/bin/bob-delegate" feat/w "x" > /dev/null
jq -e --arg dir "$tmp/worktrees/feat/w" \
  '.version == 1 and .folders[$dir] == "TRUST_FOLDER"' \
  "$HOME/.bob/trustedFolders.json" > /dev/null || fail "created trust file: $(cat "$HOME/.bob/trustedFolders.json")"

# An explicit prompt works without a note.
: > "$tmp/tmux.log"
"$root/bin/bob-delegate" feat/y "fix the build" > /dev/null
[[ $(cat "$tmp/pasted") == "fix the build" ]] || fail "explicit prompt: $(cat "$tmp/tmux.log")"

# A leading dash and multiline content remain literal through helper/paste.
"$root/bin/bob-delegate" feat/literal $'--literal\nsecond line' > /dev/null
[[ $(cat "$tmp/pasted") == $'--literal\nsecond line' ]] || fail 'multiline prompt changed'

# Outside tmux it refuses.
if TMUX= "$root/bin/bob-delegate" feat/z "x" 2>/dev/null; then fail 'ran outside tmux'; fi

echo 'PASS: bob-delegate'
