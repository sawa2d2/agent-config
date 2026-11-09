#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/real"
# Wrappers refresh themes under HOME; keep the real home untouched.
export HOME="$tmp/home"
export CODEX_HOME="$tmp/codex-home"
export XDG_CONFIG_HOME="$HOME/.config"
unset CODEX_HOME

# Fake CLIs record their argv and the PATH they were launched with.
for cli in bob claude codex; do
  cat > "$tmp/real/$cli" <<'CLI'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_ROOT/args"
printf '%s\n' "$PATH" > "$TEST_ROOT/path"
printf '%s\n' "${AGENT_APPROVAL_DIR-unset}" > "$TEST_ROOT/approval"
CLI
  chmod +x "$tmp/real/$cli"
done
export TEST_ROOT="$tmp"
unset AGENT_APPROVAL_DIR
export PATH="$root/bin:$tmp/real:/usr/bin:/bin"

fail() { echo "FAIL: $*" >&2; exit 1; }

expect() {
  local expected=$1
  shift
  # Resume stays directory-scoped even when Codex enables linked worktrees.
  if [[ $1 == codexl || $1 == codexla || ($1 == codex && (${2:-} == resume || $# == 1)) ]]; then
    expected=${expected/resume/$'-c\nfeatures.worktrees=false\nresume'}
  fi
  case $1 in
    codex|codexl|codexla) expected=$'-c\ntui.animations=false\n--no-alt-screen\n'"$expected" ;;
  esac
  "$@"
  [[ "$(cat "$tmp/args")" == "$expected" ]] || fail "$* passed: $(tr '\n' ' ' < "$tmp/args")"
  case ":$(cat "$tmp/path"):" in
    *":$root/bin:"*) fail "$*: wrapper was visible to the original CLI" ;;
  esac
}

# Without arguments, resume the latest session in the current directory.
expect $'chat\n--auto-approve\n--resume\nlatest' bob
# All wrappers mark their process tree as an agent for gfinish.
for cli in bob claude codex; do
  XDG_RUNTIME_DIR="$tmp/run" "$cli" new
  expected="$tmp/run/agent-approval"
  [[ $(cat "$tmp/approval") == "$expected" ]] || fail "$cli: AGENT_APPROVAL_DIR=$(cat "$tmp/approval")"
done
# An explicit directory wins; without a runtime directory use HOME's cache.
AGENT_APPROVAL_DIR="$tmp/custom" codex new
[[ $(cat "$tmp/approval") == "$tmp/custom" ]] || fail 'Codex replaced explicit approval directory'
(env -u XDG_RUNTIME_DIR codex new)
[[ $(cat "$tmp/approval") == "$HOME/.cache/agent-approval" ]] || fail 'Codex approval cache fallback'
# Claude continues only when this directory has a session; otherwise it starts a new one.
mkdir -p "$tmp/work.dir"
cd "$tmp/work.dir"
expect '' claude
project="$HOME/.claude/projects/$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$project"
expect '' claude
touch "$project/session.jsonl"
expect '--continue' claude
cd "$root"
[[ -f "$HOME/.bob/theme.json" ]] || fail 'bob: theme was not refreshed'
[[ -f "$HOME/.bob/settings/settings.json" ]] || fail 'bob: settings were not added'
expect $'--approve-for-me\nresume\n--last' codex
grep -q '^model_auto_compact_token_limit = 35000$' "$HOME/.codex/config.toml" || fail 'codex: compaction default missing'

# "new" starts a new session and passes the remaining arguments on.
expect $'chat\n--auto-approve' bob new
expect $'chat\n--auto-approve\n--mode\nx' bob new --mode x
expect '' claude new
expect 'two words' claude new 'two words'
expect '--approve-for-me' codex new
expect $'--approve-for-me\ntwo words' codex new 'two words'

# Arguments are preserved; Codex adds its automatic-review default.
expect $'chat\n--auto-approve' bob chat --auto-approve
expect $'--resume\ntwo words\n-p' claude --resume 'two words' -p
expect $'--approve-for-me\nexec\ntwo words' codex exec 'two words'

# Pickers use the native resume commands.
expect '--resume' claudel
expect $'--approve-for-me\nresume' codexl
expect $'--approve-for-me\nresume\n--all' codexla

# All session entry points share the automatic-review default.
expect $'--approve-for-me\ntwo words' codex 'two words'
expect $'--approve-for-me\nresume\n--last' codex resume --last
expect $'--approve-for-me\nresume\n--last\n--all' codex resume --last --all
expect $'--approve-for-me\nresume\n11111111-1111-4111-8111-111111111111' codex resume 11111111-1111-4111-8111-111111111111
# An intentional config override follows the directory-scoped default.
expect $'--approve-for-me\nresume\n-c\nfeatures.worktrees=true' codex resume -c features.worktrees=true
expect $'--approve-for-me\nfork\n--last' codex fork --last
expect $'--approve-for-me\nreview\n--uncommitted' codex review --uncommitted

# Explicit approval/sandbox choices win, including compact and config forms.
for option in '--approve-for-me' '--sandbox=read-only' '-sread-only' \
  '--ask-for-approval=on-request' '-aon-request' \
  '--dangerously-bypass-approvals-and-sandbox' '--yolo' '--full-auto'; do
  expect "$option" codex new "$option"
done
expect $'resume\n-s\nread-only' codex resume -s read-only
expect $'--sandbox\nread-only' codex new --sandbox read-only
expect $'resume\n--all\n-a\non-request' codexla -a on-request
expect $'--ask-for-approval\non-request' codex new --ask-for-approval on-request
for setting in 'approval_policy="on-request"' 'approvals_reviewer="user"' \
  'sandbox_mode="read-only"' 'sandbox_permissions=["disk-read-access"]' \
  'default_permissions=":read-only"'; do
  expect $'-c\n'"$setting" codex new -c "$setting"
  expect "--config=$setting" codex new "--config=$setting"
  expect "-c$setting" codex new "-c$setting"
done
expect $'--profile\ncustom' codex new --profile custom
expect $'--approve-for-me\n-m\ntest\nhello' codex new -m test hello
expect $'--approve-for-me\n-c\nmodel="test"' codex new -c 'model="test"'
expect $'--approve-for-me\n-c\nmodel_auto_compact_token_limit=64000' codex new -c model_auto_compact_token_limit=64000
# Option-looking prompts after -- are literal, and values are not options.
expect $'--approve-for-me\n--\n--sandbox=read-only' codex new -- --sandbox=read-only
expect $'--approve-for-me\n-m\n--sandbox=read-only' codex new -m --sandbox=read-only

codex new --sandbox read-only --no-alt-screen
[[ $(cat "$tmp/args") == $'-c\ntui.animations=false\n--sandbox\nread-only\n--no-alt-screen' ]] || fail 'Codex duplicated inline flag after sandbox'

# An explicit inline flag is passed through once; a prompt after -- is literal.
codex new --no-alt-screen
[[ $(cat "$tmp/args") == $'-c\ntui.animations=false\n--approve-for-me\n--no-alt-screen' ]] || fail 'Codex duplicated --no-alt-screen'
expect $'--approve-for-me\n--\n--no-alt-screen' codex new -- --no-alt-screen

# Explicit animation preferences follow the default; prompts remain literal.
expect $'--approve-for-me\n-c\ntui.animations=true' codex new -c tui.animations=true
expect $'--approve-for-me\n--config=tui.animations=true' codex new --config=tui.animations=true
expect $'--approve-for-me\n--\n-c tui.animations=true' codex new -- '-c tui.animations=true'

# Leaving a task that stopped at its cost limit offers a new task; in tmux the first message is typed.
mkdir -p "$tmp/loop" "$tmp/work.git" "$HOME/.bob/db"
git -C "$tmp/work.git" init -q
python3 -c '
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""
CREATE TABLE tasks (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, parent_id TEXT, title TEXT NOT NULL,
  first_message TEXT, directory TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  locked_by TEXT, lock_lease_until INTEGER, costs TEXT);
CREATE TABLE messages (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, role TEXT NOT NULL, data TEXT NOT NULL,
  created_at INTEGER NOT NULL);
""")
db.execute("INSERT INTO tasks VALUES (?, ?, NULL, ?, ?, ?, 0, 0, NULL, NULL, ?)",
           ("limited", "file:" + sys.argv[2], "Limited", "go", "", "{\"cost\": 0}"))
db.execute("INSERT INTO messages VALUES (?, ?, ?, ?, 1)", ("m1", "limited", "user", "{\"role\": \"user\", \"content\": \"go\"}"))
db.commit()' "$HOME/.bob/db/bob.db" "$tmp/work.git"
# Use an explicit cost cap distinct from the migrated repository default.
printf '%s\n' '{"session": {"maxCost": 10}}' > "$HOME/.bob/settings/settings.json"
# Fake Bob: the first chat spends past the cost limit, later ones spend nothing.
cat > "$tmp/loop/bob" <<'CLI'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_ROOT/chats"
if [[ $(wc -l < "$TEST_ROOT/chats") == 1 ]]; then
  sqlite3 "$HOME/.bob/db/bob.db" "UPDATE tasks SET costs = '{\"cost\": 25}', updated_at = $(( ($(date +%s) + 1) * 1000 ))"
fi
CLI
cat > "$tmp/loop/tmux" <<'CLI'
#!/usr/bin/env bash
# The input box shows on the third look.
if [[ $1 == capture-pane ]]; then
  echo x >> "$TEST_ROOT/looks"
  [[ $(wc -l < "$TEST_ROOT/looks") -ge 3 ]] && echo '❯'
  exit 0
fi
printf '%s\n' "$*" >> "$TEST_ROOT/tmux"
CLI
printf '%s\n' '#!/usr/bin/env bash' > "$tmp/loop/sleep"
chmod +x "$tmp/loop/bob" "$tmp/loop/tmux" "$tmp/loop/sleep"
cd "$tmp/work.git"
echo y | TMUX=1 TMUX_PANE=%1 TMPDIR="$tmp" PATH="$root/bin:$tmp/loop:/usr/bin:/bin" bob new 2> /dev/null
[[ $(cat "$tmp/chats") == $'chat --auto-approve\nchat --auto-approve' ]] || fail "handoff chats: $(cat "$tmp/chats")"
for _ in 1 2 3 4 5; do [[ -s $tmp/tmux ]] && break; /bin/sleep 0.2; done
[[ $(cat "$tmp/tmux") == "send-keys -t %1 -l The transcript of an earlier Bob task in this workspace is $tmp/bob-handoff/limited.md."*$'\nsend-keys -t %1 Enter' ]] \
  || fail "handoff typing: $(cat "$tmp/tmux")"
[[ $(wc -l < "$tmp/looks") == 3 ]] || fail "handoff typing did not wait for the input box: $(wc -l < "$tmp/looks")"
# Declining ends the loop.
rm "$tmp/chats"
echo n | TMPDIR="$tmp" PATH="$root/bin:$tmp/loop:/usr/bin:/bin" bob new 2> /dev/null
[[ $(cat "$tmp/chats") == 'chat --auto-approve' ]] || fail "declined handoff chats: $(cat "$tmp/chats")"
cd "$root"

# Without the original CLI, fail instead of recursing.
export PATH="$root/bin:/usr/bin:/bin"
for cli in bob claude codex; do
  status=0
  "$cli" 2> /dev/null || status=$?
  [[ $status -eq 127 ]] || fail "$cli: expected exit 127, got $status"
done

echo 'PASS: Bob, Claude and Codex wrappers resume by default and pass arguments through'
