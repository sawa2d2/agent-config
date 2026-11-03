#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home" XDG_STATE_HOME="$tmp/state"
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$HOME/.bob/settings" "$HOME/.bob/db"
settings() { printf '%s\n' "$1" > "$HOME/.bob/settings/settings.json"; }
# Tasks and messages tables like Bob's, reduced to the columns the hook reads.
# Only the latest assistant message of a task counts for its context size.
python3 -c '
import json, sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute("create table tasks (id text primary key, costs text)")
db.execute("create table messages (task_id text, role text, data text, created_at integer)")
db.executemany("insert into tasks values (?, ?)", [("low", "{\"cost\": 9.9}"), ("high", "{\"cost\": 12.34}"),
               ("other", "{\"cost\": 15}"), ("broken", "not json"), ("big", "{\"cost\": 1}"),
               ("shrunk", "{\"cost\": 1}")])
spend = lambda tokens: json.dumps({"role": "assistant", "_meta": {"spend": {"cost": 0.1, "contextTokens": tokens}}})
db.executemany("insert into messages values (?, ?, ?, ?)", [
    ("low", "assistant", spend(49000), 1), ("big", "assistant", spend(1000), 1),
    ("big", "assistant", spend(60000), 2), ("big", "user", "{}", 3),
    ("shrunk", "assistant", spend(60000), 1), ("shrunk", "assistant", spend(20000), 2),
    ("broken", "assistant", "not json", 1)])
db.commit()' "$HOME/.bob/db/bob.db"
hook() { printf '{"session_id": "%s", "cwd": "/w", "hook_event_name": "UserPromptSubmit", "prompt": "x"}' "$1" \
  | "$root/scripts/bob-handoff-suggest"; }
settings '{"session": {"maxCost": 20}}'

# Below half of the cost limit and the context threshold, nothing is added.
[[ -z $(hook low) && -z $(hook shrunk) ]] || fail 'suggested below half the limit and the threshold'

# At half or more, one line of context is added, once per task.
out=$(hook high)
python3 -c '
import json, sys
d = json.loads(sys.argv[1])["hookSpecificOutput"]
assert d["hookEventName"] == "UserPromptSubmit", d
assert "12.3 of its 20 Bobcoin" in d["additionalContext"] and "handoff skill" in d["additionalContext"], d
' "$out" || fail "suggestion: $out"
[[ -z $(hook high) ]] || fail 'suggested twice'
[[ -n $(hook other) ]] || fail 'another task not suggested'

# A context above the threshold is suggested once, with or without a cost
# limit; the environment variable moves the threshold, and 0 turns it off.
out=$(hook big)
python3 -c '
import json, sys
d = json.loads(sys.argv[1])["hookSpecificOutput"]
assert "grown to 60000 tokens" in d["additionalContext"] and "handoff skill" in d["additionalContext"], d
' "$out" || fail "context suggestion: $out"
[[ -z $(hook big) ]] || fail 'context suggested twice'
rm -rf "$XDG_STATE_HOME"
[[ -n $(AGENT_CONFIG_BOB_HANDOFF_TOKENS=40000 hook low) ]] || fail 'lowered threshold ignored'
[[ -z $(AGENT_CONFIG_BOB_HANDOFF_TOKENS=0 hook big) ]] || fail 'zero threshold suggested'
rm "$HOME/.bob/settings/settings.json"
[[ -n $(hook big) ]] || fail 'context not suggested without settings'

# Without a cost limit, or with an unknown task, broken costs, missing settings
# or a missing database, the hook adds nothing and succeeds.
rm -rf "$XDG_STATE_HOME"
settings '{"session": {}}'
[[ -z $(hook high) ]] || fail 'suggested without a cost limit'
settings '{"session": {"maxCost": 0}}'
[[ -z $(hook high) ]] || fail 'suggested with a zero cost limit'
settings '{"session": {"maxCost": 20}}'
[[ -z $(hook missing) && -z $(hook broken) ]] || fail 'suggested for an unknown task or broken costs'
[[ -z $(echo 'not json' | "$root/scripts/bob-handoff-suggest") ]] || fail 'suggested for invalid input'
mv "$HOME/.bob/db/bob.db" "$tmp/bob.db"
[[ -z $(hook high) ]] || fail 'suggested without a database'
mv "$tmp/bob.db" "$HOME/.bob/db/bob.db"
rm "$HOME/.bob/settings/settings.json"
[[ -z $(hook high) ]] || fail 'suggested without settings'

echo 'PASS: bob-handoff-suggest'
