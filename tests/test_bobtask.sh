#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(cd -- "$(mktemp -d)" && pwd -P)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Repositories: a (with a subdirectory and a nested repository) and b; plain is outside Git.
work="$tmp/work"
plain="$tmp/plain"
mkdir -p "$work/a/sub" "$work/a/nested" "$work/b" "$plain" "$tmp/bin" "$HOME/.bob/db"
for repo in "$work/a" "$work/a/nested" "$work/b"; do git -C "$repo" init -q; done

# Subset of Bob Shell's schema (observed in 2.0.6).
db="$HOME/.bob/db/bob.db"
WORK="$work" PLAIN="$plain" DB="$db" python3 - <<'PY'
import json, os, sqlite3, time
work, plain, now = os.environ["WORK"], os.environ["PLAIN"], int(time.time() * 1000)
db = sqlite3.connect(os.environ["DB"])
db.executescript("""
PRAGMA foreign_keys = ON;
CREATE TABLE tasks (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, parent_id TEXT REFERENCES tasks(id),
  title TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', first_message TEXT,
  directory TEXT NOT NULL, env TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  locked_by TEXT, lock_lease_until INTEGER);
CREATE TABLE messages (id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  role TEXT NOT NULL, data TEXT NOT NULL, created_at INTEGER NOT NULL);
""")
def task(id, workspace, title, updated, parent=None, user=True, lock=None):
    # Bob 2.0.6 stores "file:<launch directory>" in project_id and leaves directory empty.
    project = workspace if ":" in workspace else f"file:{workspace}"
    env = json.dumps({"workspace": workspace, "scheme": "file", "query": "q", "id": id, "staticEnvInfo": {"keep": 1}})
    db.execute("INSERT INTO tasks VALUES (?, ?, ?, ?, 'active', ?, '', ?, 0, ?, ?, ?)",
               (id, project, parent, title, f"first message {id}", env, updated,
                "other-session" if lock else None, lock))
    if user:
        db.execute("INSERT INTO messages VALUES (?, ?, 'user', ?, 1)", (f"u-{id}", id,
                   json.dumps({"role": "user", "content": f"expanded {id}", "_meta": {"mask": f"hello {id}"}})))
task("old", f"file:{work}/a?x%3D1", "", now - 3_000_000)
task("titled", f"{work}/a", "Bob title", now - 1_000)
task("child", f"{work}/a", "Child", now, parent="titled")
task("grandchild", f"{work}/a", "Grandchild", now, parent="child")
task("insub", f"{work}/a/sub", "In sub", now - 2_000_000)
task("empty", f"{work}/a", "No user message", now, user=False)
task("locked", f"{work}/a", "Running", now, lock=now + 300_000)
task("nested", f"{work}/a/nested", "Nested", now)
task("other", f"{work}/b", "Other", now)
task("remote", f"vscode-remote:{work}/a", "Remote scheme", now)
task("plain", plain, "Outside Git", now)
for i, data in enumerate([
    {"role": "system", "content": "SYSTEM PROMPT"},
    {"role": "assistant", "content": "Let me look.", "toolCalls": [{"id": "c1", "name": "read_file", "arguments": {"path": "x"}}]},
    {"role": "tool", "content": "file body", "toolUsage": {"signature": {"name": "read_file", "arguments": {}, "isError": True}}},
    {"role": "assistant", "content": "Done."},
]):
    db.execute("INSERT INTO messages VALUES (?, 'titled', ?, ?, ?)", (f"t-{i}", data["role"], json.dumps(data), 2 + i))
db.commit()
PY
count() { sqlite3 -readonly "$db" "$1"; }

# Fake picker records its input and selects rows matching $PICK; fake Bob records cwd and argv.
cat > "$tmp/bin/fzf" <<'FZF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_ROOT/picker-args"
tee "$TEST_ROOT/picker-input" | grep -E "$PICK" || exit 1
FZF
cat > "$tmp/bin/bob" <<'BOB'
#!/usr/bin/env bash
pwd -P > "$TEST_ROOT/bob-cwd"
printf '%s\n' "$@" > "$TEST_ROOT/bob-args"
BOB
chmod +x "$tmp/bin/fzf" "$tmp/bin/bob"
export TEST_ROOT="$tmp" PATH="$tmp/bin:$PATH"
bobtask() { python3 "$root/bin/bobtask" "$@"; }
rows() { tail -n +2 "$tmp/picker-input" | cut -f1 | paste -sd,; }

# Pickers list every unlocked resumable task, newest first.
cd "$work/a/sub"
PICK=nomatch bobtask rm < /dev/null > /dev/null || true
[[ $(rows) == plain,other,nested,titled,insub,old ]] || fail "unexpected rows: $(cat "$tmp/picker-input")"

# --current limits them to the current Git repository.
PICK=nomatch bobtask rm --current < /dev/null > /dev/null || true
[[ $(rows) == titled,insub,old ]] || fail "unexpected rows: $(cat "$tmp/picker-input")"
display=$(cut -f2 "$tmp/picker-input")
[[ $(head -1 <<< "$display" | tr -s ' ') == 'UPDATED PROJECT_ID TITLE ID' ]] || fail "header: $(head -1 <<< "$display")"
grep -qE "   file:$work/a\\?x%3D1   first message old   old$" <<< "$display" || fail "row format: $display"
[[ $(awk '{ match($0, /[^ ]+$/); print RSTART }' <<< "$display" | sort -u | wc -l) -eq 1 ]] || fail "misaligned: $display"
grep -q -- --multi "$tmp/picker-args" || fail 'rm picker is not multi-select'
grep -q -- 'ctrl-a:select-all' "$tmp/picker-args" || fail 'rm picker lacks select-all'

# list prints the same table without fzf; ls is an alias.
listed=$(PATH=/usr/bin:/bin bobtask list -c)
[[ $listed == "$display" ]] || fail "list -c differs from picker: $listed"
[[ $(bobtask ls | awk 'NR > 1 { print $NF }' | paste -sd,) == plain,other,nested,titled,insub,old ]] || fail "ls rows: $(bobtask ls)"

# Outside Git, only tasks started in the current directory match; bobrm is rm --current.
(cd "$plain" && PICK=nomatch bash "$root/bin/bobrm" < /dev/null > /dev/null || true)
[[ $(rows) == plain ]] || fail "non-Git rows: $(cat "$tmp/picker-input")"

# dump: readable transcript without system messages; --json keeps raw data.
cd "$work/a"
out=$(PICK=titled bobtask dump)
for expected in '# Bob title' 'ID: titled' "Workspace: file:$work/a" '## user (' 'hello titled' '## assistant (' 'Let me look.' \
  '[tool call] read_file {"path": "x"}' '## tool: read_file (failed) (' 'file body' 'Done.'; do
  [[ $out == *"$expected"* ]] || fail "dump lacks '$expected': $out"
done
[[ $out != *'SYSTEM PROMPT'* && $out != *'expanded titled'* ]] || fail "dump shows system or expanded prompt: $out"
PICK=titled bobtask dump --json | python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
assert data["task"]["id"] == "titled" and len(data["messages"]) == 5, data'

# resume: every directory by default, -c for the current project; Bob starts in the task workspace.
cd "$work/a"
PICK=$'^insub\t' bobtask resume -c
[[ $(rows) == titled,insub,old ]] || fail "resume rows: $(cat "$tmp/picker-input")"
[[ $(cat "$tmp/bob-cwd") == "$work/a/sub" ]] || fail "resume cwd: $(cat "$tmp/bob-cwd")"
cd "$tmp"
PICK=$'^insub\t' bobtask resume
[[ $(rows) == plain,other,nested,titled,insub,old ]] || fail "resume rows: $(cat "$tmp/picker-input")"
grep -q -- --multi "$tmp/picker-args" && fail 'resume picker is multi-select'
[[ $(cat "$tmp/bob-cwd") == "$work/a/sub" ]] || fail "resume cwd: $(cat "$tmp/bob-cwd")"
[[ $(cat "$tmp/bob-args") == $'chat\n--resume\ninsub\n--auto-approve' ]] || fail "resume args: $(cat "$tmp/bob-args")"

# mv: declining keeps the task; confirming rewrites the task tree's workspace.
cd "$work/a"
echo n | PICK=titled bobtask mv "$work/b" > /dev/null 2>&1 && fail 'declined move reported success'
[[ $(count "SELECT project_id FROM tasks WHERE id = 'titled'") == "file:$work/a" ]] || fail 'declined move changed task'
bobtask mv "$tmp/missing" < /dev/null > /dev/null 2>&1 && fail 'missing target accepted'
out=$(echo y | PICK=titled bobtask mv "$work/b/../b")
[[ $out == *"Moved 1 tasks to $work/b."* ]] || fail "unexpected mv output: $out"
for id in titled child grandchild; do
  [[ $(count "SELECT project_id FROM tasks WHERE id = '$id'") == "file:$work/b" ]] || fail "$id project_id not moved"
  count "SELECT env FROM tasks WHERE id = '$id'" | TARGET="$work/b" python3 -c '
import json, os, sys
env = json.loads(sys.stdin.read())
assert env["workspace"] == os.environ["TARGET"] and env["scheme"] == "file" and "query" not in env, env
assert env["staticEnvInfo"] == {"keep": 1}, env' || fail "$id env not moved"
done
[[ $(count "SELECT project_id FROM tasks WHERE id = 'locked'") == "file:$work/a" ]] || fail 'locked task moved'
(cd "$work/b" && PICK=nomatch bobtask rm -c < /dev/null > /dev/null || true)
[[ $(rows) == other,titled ]] || fail "moved task not listed in target: $(cat "$tmp/picker-input")"

# On case-insensitive file systems, mv stores the on-disk spelling of the target.
BOBTASK="$root/bin/bobtask" python3 - <<'PY'
import importlib.machinery, importlib.util, os
loader = importlib.machinery.SourceFileLoader("bobtask", os.environ["BOBTASK"])
spec = importlib.util.spec_from_loader("bobtask", loader)
bobtask = importlib.util.module_from_spec(spec)
loader.exec_module(bobtask)
tree = {"/": ["Users"], "/Users": ["Me"], "/Users/Me": ["Work", "WORK2", "work2"]}
bobtask.os.listdir = lambda path: tree[path] if path in tree else []
assert bobtask.on_disk_case("/users/me/work") == "/Users/Me/Work"
assert bobtask.on_disk_case("/Users/Me/Work") == "/Users/Me/Work"
assert bobtask.on_disk_case("/Users/Me/Work2") == "/Users/Me/Work2"  # ambiguous: kept as typed
assert bobtask.on_disk_case("/Users/Me/work2") == "/Users/Me/work2"
assert bobtask.on_disk_case("/Users/Me/new") == "/Users/Me/new"
PY

# rm: declining keeps everything; confirming removes tasks, subtasks and messages.
echo n | PICK=old bobtask rm > /dev/null 2>&1 && fail 'declined removal reported success'
[[ $(count "SELECT count(*) FROM tasks") -eq 11 ]] || fail 'declined removal deleted tasks'
out=$(echo y | PICK='old|insub' bobtask rm)
[[ $out == *'Removed 2 tasks.'* ]] || fail "unexpected rm output: $out"
[[ $(count "SELECT count(*) FROM tasks WHERE id IN ('old', 'insub')") -eq 0 ]] || fail 'tasks not removed'
[[ $(count "SELECT count(*) FROM messages WHERE task_id IN ('old', 'insub')") -eq 0 ]] || fail 'messages not removed'
[[ $(count "SELECT count(*) FROM tasks") -eq 9 ]] || fail 'unselected tasks removed'
out=$(cd "$work/b" && echo y | PICK=titled bobtask rm)
[[ $(count "SELECT count(*) FROM tasks WHERE id IN ('titled', 'child', 'grandchild')") -eq 0 ]] || fail "nested subtasks not removed: $out"

# bobl is a thin wrapper around bobtask resume --current.
cd "$work/b"
PICK=$'^other\t' bash "$root/bin/bobl"
[[ $(cat "$tmp/bob-args") == $'chat\n--resume\nother\n--auto-approve' ]] || fail "bobl args: $(cat "$tmp/bob-args")"
[[ $(cat "$tmp/bob-cwd") == "$work/b" ]] || fail "bobl cwd: $(cat "$tmp/bob-cwd")"

echo 'PASS: bobtask list, rm, mv, resume and dump'
