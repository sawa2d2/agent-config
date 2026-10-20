#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(cd -- "$(mktemp -d)" && pwd -P)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Repositories: a (with a subdirectory and a nested repository) and b.
work="$tmp/work"
mkdir -p "$work/a/sub" "$work/a/nested" "$work/b" "$tmp/bin"
for repo in "$work/a" "$work/a/nested" "$work/b"; do git -C "$repo" init -q; done

projects="$HOME/.claude/projects"
session() { # project id cwd extra-json-lines...
  mkdir -p "$projects/$1"
  local file="$projects/$1/$2.jsonl"
  printf '{"type":"user","cwd":"%s","sessionId":"%s","message":{"role":"user","content":"first prompt %s"}}\n' "$3" "$2" "$2" > "$file"
  shift 3
  local line
  for line in "$@"; do printf '%s\n' "$line" >> "$file"; done
}
session pa old "$work/a"
session pa titled "$work/a" '{"type":"ai-title","aiTitle":"AI title"}' '{"type":"custom-title","customTitle":"Custom title"}'
session psub insub "$work/a/sub"
session pnested nested "$work/a/nested"
session pb other "$work/b"
touch -d '2020-01-01' "$projects/pa/old.jsonl"
touch -d '2020-01-02' "$projects/psub/insub.jsonl"
mkdir -p "$projects/pa/titled/subagents" "$HOME/.claude/file-history/titled" "$HOME/.claude/session-env/titled"
mkdir -p "$projects/pa/memory"

# The fake picker records its input and selects rows matching $PICK.
cat > "$tmp/bin/fzf" <<'FZF'
#!/usr/bin/env bash
tee "$TEST_ROOT/picker-input" | grep -E "$PICK" || exit 1
FZF
chmod +x "$tmp/bin/fzf"
export TEST_ROOT="$tmp" PATH="$tmp/bin:$PATH"

# Only sessions of the current Git repository, newest first, with real paths.
cd "$work/a/sub"
PICK=nomatch bash "$root/bin/clauderm" < /dev/null > /dev/null || true
[[ $(wc -l < "$tmp/picker-input") -eq 4 ]] || fail "unexpected rows: $(cat "$tmp/picker-input")"
# Display column: header first, columns padded to the widest value, three spaces apart.
display=$(cut -f3 "$tmp/picker-input")
[[ $(head -1 <<< "$display") == "UPDATED            TITLE                PATH" ]] || fail "header misaligned: $(head -1 <<< "$display")"
[[ $(sed -n 2p <<< "$display") == "$(date -r "$projects/pa/titled.jsonl" '+%Y-%m-%d %H:%M')   Custom title         $projects/pa/titled.jsonl" ]] ||
  fail "custom title row misaligned: $(sed -n 2p <<< "$display")"
tail -1 "$tmp/picker-input" | grep -q 'first prompt old' || fail 'old session not last'
grep -q "$projects/psub/insub.jsonl" "$tmp/picker-input" || fail 'subdirectory session or path missing'
grep -qE 'nested|other' "$tmp/picker-input" && fail 'other repository listed'

# Outside Git, only the current directory matches.
cd "$tmp"
mkdir -p plain && cd plain
session pplain plain "$tmp/plain"
PICK=nomatch bash "$root/bin/clauderm" < /dev/null > /dev/null || true
[[ $(tail -n +2 "$tmp/picker-input" | cut -f1) == plain ]] || fail "non-Git rows: $(cat "$tmp/picker-input")"
cd "$work/a"

# Declining keeps everything.
echo n | PICK=titled bash "$root/bin/clauderm" > /dev/null && fail 'declined removal reported success'
[[ -f "$projects/pa/titled.jsonl" ]] || fail 'declined removal deleted transcript'

# Confirming removes the transcript and its per-session data only.
out=$(echo y | PICK='titled|insub' bash "$root/bin/clauderm")
[[ $out == *"$projects/pa/titled.jsonl"* ]] || fail "removed paths not reported: $out"
for path in "$projects/pa/titled.jsonl" "$projects/pa/titled" \
  "$HOME/.claude/file-history/titled" "$HOME/.claude/session-env/titled" "$projects/psub/insub.jsonl"; do
  [[ ! -e $path ]] || fail "not removed: $path"
done
[[ -f "$projects/pa/old.jsonl" && -d "$projects/pa/memory" && -f "$projects/pb/other.jsonl" ]] || fail 'unselected data removed'

echo 'PASS: clauderm lists current-project sessions with real paths and removes selected ones after confirmation'
