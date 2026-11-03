#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(cd -- "$(mktemp -d)" && pwd -P)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" CODEX_HOME="$tmp/codex"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Repositories: a (with a subdirectory and a nested repository) and b.
work="$tmp/work"
mkdir -p "$work/a/sub" "$work/a/nested" "$work/b" "$tmp/bin"
for repo in "$work/a" "$work/a/nested" "$work/b"; do git -C "$repo" init -q; done

uuid() { printf '00000000-0000-7000-8000-%012d' "$1"; }
rollout() { # dir id cwd parent prompt
  local file="$CODEX_HOME/$1/rollout-2026-11-04T00-00-00-$2.jsonl" parent=null
  [[ -z $4 ]] || parent="\"$4\""
  mkdir -p "${file%/*}"
  printf '{"type":"session_meta","payload":{"id":"%s","cwd":"%s","parent_thread_id":%s}}\n' "$2" "$3" "$parent" > "$file"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions\\n"}]}}\n' >> "$file"
  printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"%s"}]}}\n' "$5" >> "$file"
  printf '%s\n' "$file"
}
day=sessions/2026/11/04
old=$(rollout "$day" "$(uuid 1)" "$work/a" "" 'first prompt old')
named=$(rollout "$day" "$(uuid 2)" "$work/a" "" 'first prompt named')
child=$(rollout "$day" "$(uuid 3)" "$work/a" "$(uuid 2)" 'child prompt')
grandchild=$(rollout "$day" "$(uuid 4)" "$work/a" "$(uuid 3)" 'grandchild prompt')
insub=$(rollout archived_sessions "$(uuid 5)" "$work/a/sub" "" 'first prompt insub')
rollout "$day" "$(uuid 6)" "$work/a/nested" "" 'first prompt nested' > /dev/null
other=$(rollout "$day" "$(uuid 7)" "$work/b" "" 'first prompt other')
printf '{"id":"%s","thread_name":"Old name"}\n{"id":"%s","thread_name":"Thread name"}\n' "$(uuid 2)" "$(uuid 2)" > "$CODEX_HOME/session_index.jsonl"
touch -d '2020-01-01' "$old"
touch -d '2020-01-02' "$insub"

# The fake picker records its input and selects rows matching $PICK; the fake
# codex records deletions and removes the rollout like the native command.
cat > "$tmp/bin/fzf" <<'FZF'
#!/usr/bin/env bash
tee "$TEST_ROOT/picker-input" | grep -E "$PICK" || exit 1
FZF
cat > "$tmp/bin/codex" <<'CODEX'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_ROOT/codex-calls"
[[ $1 == delete && $2 == --force ]] || exit 2
rm -- "$CODEX_HOME"/sessions/*/*/*/rollout-*-"$3".jsonl "$CODEX_HOME"/archived_sessions/rollout-*-"$3".jsonl 2>/dev/null || true
echo "Deleted session $3."
CODEX
chmod +x "$tmp/bin/fzf" "$tmp/bin/codex"
export TEST_ROOT="$tmp" PATH="$tmp/bin:$PATH"

# Only top-level sessions of the current Git repository, newest first, with real paths.
cd "$work/a/sub"
PICK=nomatch bash "$root/bin/codexrm" < /dev/null > /dev/null || true
[[ $(wc -l < "$tmp/picker-input") -eq 4 ]] || fail "unexpected rows: $(cat "$tmp/picker-input")"
display=$(cut -f3 "$tmp/picker-input")
[[ $(head -1 <<< "$display") == "UPDATED            TITLE                PATH" ]] || fail "header misaligned: $(head -1 <<< "$display")"
[[ $(sed -n 2p <<< "$display") == "$(date -r "$named" '+%Y-%m-%d %H:%M')   Thread name          $named" ]] ||
  fail "named row misaligned: $(sed -n 2p <<< "$display")"
tail -1 "$tmp/picker-input" | grep -q 'first prompt old' || fail 'old session not last'
grep -q "$insub" "$tmp/picker-input" || fail 'archived subdirectory session or path missing'
grep -qE 'nested|other|child' "$tmp/picker-input" && fail 'other repository or subagent thread listed'

# Outside Git, only the current directory matches.
mkdir -p "$tmp/plain" && cd "$tmp/plain"
rollout "$day" "$(uuid 8)" "$tmp/plain" "" 'first prompt plain' > /dev/null
PICK=nomatch bash "$root/bin/codexrm" < /dev/null > /dev/null || true
[[ $(tail -n +2 "$tmp/picker-input" | cut -f1) == "$(uuid 8)" ]] || fail "non-Git rows: $(cat "$tmp/picker-input")"
cd "$work/a"

# Declining deletes nothing.
echo n | PICK='Thread name' bash "$root/bin/codexrm" > /dev/null 2>&1 && fail 'declined removal reported success'
[[ ! -e "$tmp/codex-calls" && -f "$named" ]] || fail 'declined removal deleted a session'

# Confirming deletes the selected sessions natively, subagent threads first.
out=$(echo y | PICK='Thread name|insub' bash "$root/bin/codexrm")
[[ $out == *"$named"* && $out == *"$child"* && $out == *"$insub"* ]] || fail "rollouts not listed: $out"
[[ $(cat "$tmp/codex-calls") == "delete --force $(uuid 4)
delete --force $(uuid 3)
delete --force $(uuid 2)
delete --force $(uuid 5)" ]] || fail "unexpected codex calls: $(cat "$tmp/codex-calls")"
for path in "$named" "$child" "$grandchild" "$insub"; do
  [[ ! -e $path ]] || fail "not removed: $path"
done
[[ -f "$old" && -f "$other" ]] || fail 'unselected session removed'

echo 'PASS: codexrm lists current-project sessions and deletes selected ones with their subagent threads after confirmation'
