#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(cd -- "$(mktemp -d)" && pwd -P)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Repositories: a (with a subdirectory and a nested repository) and b.
work="$tmp/work"
mkdir -p "$work/a/sub" "$work/a/nested" "$work/b" "$tmp/bin" "$HOME/.bob/db"
plain="$tmp/plain"; mkdir -p "$plain"
for repo in "$work/a" "$work/a/nested" "$work/b"; do git -C "$repo" init -q; done

# Subset of Bob Shell's schema (observed in 2.0.6).
db="$HOME/.bob/db/bob.db"
WORK="$work" PLAIN="$plain" DB="$db" python3 - <<'PY'
import os, sqlite3, time
work, now = os.environ["WORK"], int(time.time() * 1000)
db = sqlite3.connect(os.environ["DB"])
db.executescript("""
PRAGMA foreign_keys = ON;
CREATE TABLE tasks (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, parent_id TEXT REFERENCES tasks(id),
  title TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'active', first_message TEXT, directory TEXT NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, locked_by TEXT, lock_lease_until INTEGER);
CREATE TABLE messages (id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  role TEXT NOT NULL, data TEXT NOT NULL, created_at INTEGER NOT NULL);
""")
def task(id, directory, title, updated, parent=None, user=True, lock=None):
    # Bob 2.0.6 stores "file:<launch directory>" in project_id and leaves directory empty.
    db.execute("INSERT INTO tasks VALUES (?, ?, ?, ?, 'active', ?, '', 0, ?, ?, ?)",
               (id, directory if ":" in directory else f"file:{directory}", parent, title, f"first message {id}", updated,
                "other-session" if lock else None, lock))
    if user:
        db.execute("INSERT INTO messages VALUES (?, ?, 'user', '{}', 0)", (f"m-{id}", id))
task("old", f"file:{work}/a?x%3D1", "", now - 3_000_000)
task("titled", f"{work}/a", "Bob title", now - 1_000)
task("child", f"{work}/a", "Child", now, parent="titled")
task("insub", f"{work}/a/sub", "In sub", now - 2_000_000)
task("empty", f"{work}/a", "No user message", now, user=False)
task("locked", f"{work}/a", "Running", now, lock=now + 300_000)
task("nested", f"{work}/a/nested", "Nested", now)
task("other", f"{work}/b", "Other", now)
task("unknown", "", "No workspace", now)
task("remote", f"vscode-remote:{work}/a", "Remote scheme", now)
task("plain", f"{os.environ['PLAIN']}", "Outside Git", now)
# Rows that do record directory use it in preference to project_id.
db.execute("UPDATE tasks SET directory = ?, project_id = 'opaque-id' WHERE id = 'insub'", (f"{work}/a/sub",))
db.commit()
PY
count() { sqlite3 -readonly "$db" "$1"; }

# The fake picker records its input and selects rows matching $PICK.
cat > "$tmp/bin/fzf" <<'FZF'
#!/usr/bin/env bash
tee "$TEST_ROOT/picker-input" | grep -E "$PICK" || exit 1
FZF
chmod +x "$tmp/bin/fzf"
export TEST_ROOT="$tmp" PATH="$tmp/bin:$PATH"

# Only resumable, unlocked top-level tasks of the current Git repository.
cd "$work/a/sub"
PICK=nomatch bash "$root/bin/bobrm" < /dev/null > /dev/null || true
[[ $(tail -n +2 "$tmp/picker-input" | cut -f1 | paste -sd,) == titled,insub,old ]] ||
  fail "unexpected rows: $(cat "$tmp/picker-input")"
display=$(cut -f2 "$tmp/picker-input")
[[ $(head -1 <<< "$display" | tr -s ' ') == 'UPDATED PROJECT_ID TITLE ID' ]] || fail "header: $(head -1 <<< "$display")"
grep -qE "   file:$work/a\?x%3D1   first message old   old$" <<< "$display" ||
  fail "raw project_id or title fallback missing: $display"
grep -qE "   opaque-id +   In sub +   insub$" <<< "$display" || fail "legacy directory row missing: $display"
# Columns are aligned: every row (and the header) starts ID at the same offset.
[[ $(awk '{ match($0, /[^ ]+$/); print RSTART }' <<< "$display" | sort -u | wc -l) -eq 1 ]] || fail "misaligned: $display"

# Outside Git, only tasks started in the current directory match.
(cd "$plain" && PICK=nomatch bash "$root/bin/bobrm" < /dev/null > /dev/null || true)
[[ $(tail -n +2 "$tmp/picker-input" | cut -f1) == plain ]] || fail "non-Git rows: $(cat "$tmp/picker-input")"

# Declining keeps everything.
echo n | PICK=titled bash "$root/bin/bobrm" > /dev/null && fail 'declined removal reported success'
[[ $(count "SELECT count(*) FROM tasks") -eq 11 ]] || fail 'declined removal deleted tasks'

# Confirming removes the tasks, their subtasks and messages only.
out=$(echo y | PICK='titled|insub' bash "$root/bin/bobrm")
[[ $out == *'Removed 2 tasks.'* ]] || fail "unexpected output: $out"
[[ $(count "SELECT group_concat(id, ',') FROM (SELECT id FROM tasks ORDER BY id)") == empty,locked,nested,old,other,plain,remote,unknown ]] ||
  fail "unexpected remaining tasks: $(count 'SELECT id FROM tasks')"
[[ $(count "SELECT count(*) FROM messages WHERE task_id IN ('titled','child','insub')") -eq 0 ]] || fail 'messages not removed'

echo 'PASS: bobrm lists current-project tasks and removes selected ones after confirmation'
