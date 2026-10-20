#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(cd -- "$(mktemp -d)" && pwd -P)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$tmp/bin" "$HOME/.bob/db" "$tmp/ws/a" "$tmp/ws/legacy"

# Subset of Bob Shell's schema (observed in 2.0.6).
db="$HOME/.bob/db/bob.db"
WS="$tmp/ws" DB="$db" python3 - <<'PY'
import os, sqlite3, time
ws, now = os.environ["WS"], int(time.time() * 1000)
db = sqlite3.connect(os.environ["DB"])
db.executescript("""
CREATE TABLE tasks (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, parent_id TEXT,
  title TEXT NOT NULL DEFAULT '', directory TEXT NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE messages (id TEXT PRIMARY KEY, task_id TEXT NOT NULL, role TEXT NOT NULL);
""")
def task(id, project, updated, directory="", parent=None, user=True):
    db.execute("INSERT INTO tasks VALUES (?, ?, ?, ?, ?, ?)", (id, project, parent, f"Title {id}", directory, updated))
    if user:
        db.execute("INSERT INTO messages VALUES (?, ?, 'user')", (f"m-{id}", id))
# Bob 2.0.6 stores "file:<launch directory>[?query]" in project_id and leaves directory empty.
task("current", f"file:{ws}/a?x%3D1", now)
task("legacy", "opaque", now - 1_000, directory=f"{ws}/legacy")
task("child", f"file:{ws}/a", now, parent="current")
task("empty", f"file:{ws}/a", now, user=False)
task("remote", f"vscode-remote:{ws}/a", now)
db.commit()
PY

# Fake picker selects rows matching $PICK; fake Bob records its cwd and argv.
cat > "$tmp/bin/fzf" <<'FZF'
#!/usr/bin/env bash
tee "$TEST_ROOT/picker-input" | grep -E "$PICK" | head -1
FZF
cat > "$tmp/bin/bob" <<'BOB'
#!/usr/bin/env bash
pwd -P > "$TEST_ROOT/bob-cwd"
printf '%s\n' "$@" > "$TEST_ROOT/bob-args"
BOB
chmod +x "$tmp/bin/fzf" "$tmp/bin/bob"
export TEST_ROOT="$tmp" PATH="$tmp/bin:$PATH"

# Only resumable top-level tasks with a local workspace are listed.
PICK=$'^current\t' bash "$root/bin/bobla"
[[ $(cut -f1 "$tmp/picker-input" | paste -sd,) == current,legacy ]] || fail "unexpected rows: $(cat "$tmp/picker-input")"
[[ $(cat "$tmp/bob-cwd") == "$tmp/ws/a" ]] || fail "wrong cwd: $(cat "$tmp/bob-cwd")"
[[ $(cat "$tmp/bob-args") == $'chat\n--resume\ncurrent\n--auto-approve' ]] || fail "wrong args: $(cat "$tmp/bob-args")"

# Rows that record directory use it.
PICK=$'^legacy\t' bash "$root/bin/bobla"
[[ $(cat "$tmp/bob-cwd") == "$tmp/ws/legacy" ]] || fail "legacy cwd: $(cat "$tmp/bob-cwd")"

echo 'PASS: bobla resumes Bob 2.0.6 tasks in their stored workspace'
