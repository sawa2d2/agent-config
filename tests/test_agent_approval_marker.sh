#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export AGENT_APPROVAL_DIR="$tmp/approval"
fail() { echo "FAIL: $*" >&2; exit 1; }
# A repository reached through a symlink: the marker names its real top level.
mkdir -p "$tmp/real repo/sub" "$tmp/plain"
git -C "$tmp/real repo" init -q
ln -s "$tmp/real repo" "$tmp/link"
marker="$AGENT_APPROVAL_DIR/$(printf %s "$(git -C "$tmp/link/sub" rev-parse --show-toplevel | xargs -d '\n' realpath)" | sha256sum | cut -c1-64)"
hook() {
  PROMPT=$1 CWD=$2 python3 -c 'import json, os; print(json.dumps({"session_id": "s", "hook_event_name": "UserPromptSubmit", "cwd": os.environ["CWD"], "prompt": os.environ["PROMPT"]}))' \
    | "$root/scripts/agent-approval-marker"
}

# Anything but the exact word, trimmed, leaves no marker and prints nothing.
for prompt in 'approve 可能？' 'Approved' 'approved?' 'approved, merge it' 'not approved' ''; do
  out=$(hook "$prompt" "$tmp/link/sub")
  [[ -z $out && ! -e $AGENT_APPROVAL_DIR ]] || fail "marker or output for: $prompt"
done

# "approved" with surrounding whitespace writes the marker for the repository's real top level.
[[ -z $(hook $'  approved\n' "$tmp/link/sub") ]] || fail 'output on approval'
[[ -f $marker ]] || fail "marker missing: $(ls -A "$AGENT_APPROVAL_DIR")"
[[ $(ls -A "$AGENT_APPROVAL_DIR" | wc -l) == 1 ]] || fail 'extra markers'
# Approving again refreshes the marker's time.
touch -d '2 hours ago' "$marker"
hook approved "$tmp/real repo"
[[ -n $(find "$marker" -mmin -1) ]] || fail 'marker not refreshed'

# Outside a git repository, without AGENT_APPROVAL_DIR or with invalid input, nothing happens and the hook succeeds.
rm -rf "$AGENT_APPROVAL_DIR"
hook approved "$tmp/plain" || fail 'failed outside a repository'
hook approved "$tmp/missing" || fail 'failed for a missing cwd'
(unset AGENT_APPROVAL_DIR; hook approved "$tmp/real repo") || fail 'failed without AGENT_APPROVAL_DIR'
echo 'not json' | "$root/scripts/agent-approval-marker" || fail 'failed for invalid input'
[[ ! -e $AGENT_APPROVAL_DIR ]] || fail 'marker written without approval in a repository'

# An unwritable directory is reported but does not block the prompt.
printf x > "$AGENT_APPROVAL_DIR"
err=$(hook approved "$tmp/real repo" 2>&1 >/dev/null) || fail 'blocked on a write error'
[[ $err == agent-approval-marker:* ]] || fail "write error not reported: $err"

echo 'PASS: agent-approval-marker'
