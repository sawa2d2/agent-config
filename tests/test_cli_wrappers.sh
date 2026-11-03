#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/real"
# Wrappers refresh themes under HOME; keep the real home untouched.
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"

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
  "$@"
  [[ "$(cat "$tmp/args")" == "$expected" ]] || fail "$* passed: $(tr '\n' ' ' < "$tmp/args")"
  case ":$(cat "$tmp/path"):" in
    *":$root/bin:"*) fail "$*: wrapper was visible to the original CLI" ;;
  esac
}

# Without arguments, resume the latest session in the current directory.
expect $'chat\n--auto-approve\n--resume\nlatest' bob
# Bob and Claude mark their process tree as an agent for gfinish; Codex does not.
for cli in bob claude codex; do
  XDG_RUNTIME_DIR="$tmp/run" "$cli" new
  expected="$tmp/run/agent-approval"
  [[ $cli == codex ]] && expected=unset
  [[ $(cat "$tmp/approval") == "$expected" ]] || fail "$cli: AGENT_APPROVAL_DIR=$(cat "$tmp/approval")"
done
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
expect $'resume\n--last' codex

# "new" starts a new session and passes the remaining arguments on.
expect $'chat\n--auto-approve' bob new
expect $'chat\n--auto-approve\n--mode\nx' bob new --mode x
expect '' claude new
expect 'two words' claude new 'two words'
expect '' codex new
expect 'two words' codex new 'two words'

# Explicit arguments are passed through unchanged.
expect $'chat\n--auto-approve' bob chat --auto-approve
expect $'--resume\ntwo words\n-p' claude --resume 'two words' -p
expect $'exec\ntwo words' codex exec 'two words'

# Pickers use the native resume commands.
expect '--resume' claudel
expect $'resume' codexl
expect $'resume\n--all' codexla

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
