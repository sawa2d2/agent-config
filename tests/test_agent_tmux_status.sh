#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
command -v tmux >/dev/null 2>&1 || { echo 'SKIP: tmux not installed'; exit 0; }
tmp=$(cd -- "$(mktemp -d)" && pwd -P)
socket="$tmp/tmux.sock"
t() { tmux -S "$socket" "$@"; }
trap 't kill-server 2>/dev/null; rm -rf -- "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
status="$root/scripts/agent-tmux-status"

# Isolated server: window one runs the agent, window two is another window.
t -f /dev/null new-session -d -s test -x 80 -y 24
t new-window -d
pane=$(t display-message -p -t test:0 '#{pane_id}')
other=$(t display-message -p -t test:1 '#{window_id}')
window=$(t display-message -p -t test:0 '#{window_id}')
export TMUX="$socket,0,0" TMUX_PANE="$pane"
t set-option -g @agent_status_hook "printf x >> $tmp/hook"
opt() { t show-options -wqv -t "$window" "$1"; }
hooks() { cat "$tmp/hook" 2>/dev/null | wc -c | tr -d ' '; }

# Outside tmux nothing happens and the agent is never blocked.
(unset TMUX; bash "$status" working) || fail 'outside tmux failed'
[[ -z $(opt @agent_status) ]] || fail 'outside tmux marked the window'

# working marks only the agent's window, without attention but with a timestamp.
bash "$status" working
[[ $(opt @agent_status) == working && -z $(opt @agent_attention) ]] || fail "working: $(opt @agent_status)"
[[ $(opt @agent_status_at) =~ ^[0-9]+$ ]] || fail 'no timestamp'
[[ -z $(t show-options -wqv -t "$other" @agent_status) ]] || fail 'other window marked'
sleep 0.5
[[ $(hooks) == 1 ]] || fail "hook runs after a change: $(hooks)"

# Repeated working (tool hooks) refreshes the timestamp without running the hook again.
bash "$status" working
sleep 0.5
[[ $(hooks) == 1 ]] || fail "hook ran without a change: $(hooks)"

bash "$status" waiting
[[ $(opt @agent_status) == waiting && $(opt @agent_attention) == 1 ]] || fail 'waiting'
bash "$status" 'done'
[[ $(opt @agent_status) == 'done' && $(opt @agent_attention) == 1 ]] || fail 'done'
bash "$status" clear
[[ -z $(opt @agent_status)$(opt @agent_attention)$(opt @agent_status_at) ]] || fail 'clear'
bash "$status" bogus 2> /dev/null || fail 'unknown state blocked the agent'

# Without TMUX_PANE (hooks may not inherit it), the pane is found from process ancestry.
t respawn-pane -k -t "$pane" "env -u TMUX_PANE bash $(printf '%q' "$status") done; sleep 30"
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ $(opt @agent_status) == 'done' ]] && break; sleep 0.2; done
[[ $(opt @agent_status) == 'done' ]] || fail 'ancestry lookup'

# A working window without updates turns stale; an update in time keeps it working.
t set-option -g @agent_status_stale_after 2
bash "$status" working
sleep 1
bash "$status" working
sleep 1.5
[[ $(opt @agent_status) == working ]] || fail "turned stale despite an update: $(opt @agent_status)"
sleep 1.5
[[ $(opt @agent_status) == stale && $(opt @agent_attention) == 1 ]] || fail "not stale: $(opt @agent_status)"
# Finished work is never marked stale.
bash "$status" working
bash "$status" 'done'
sleep 2.5
[[ $(opt @agent_status) == 'done' ]] || fail "done turned stale: $(opt @agent_status)"

# Seen and marked again in the same state: the flag returns and the line redraws.
bash "$status" waiting
t set-option -wu -t "$window" @agent_attention
sleep 0.3
count=$(hooks)
bash "$status" waiting
sleep 0.3
[[ $(opt @agent_attention) == 1 && $(hooks) -gt $count ]] || fail "re-mark: $(opt @agent_attention) $(hooks)"

# A window shown to an attached client needs no notification; others still do.
mkfifo "$tmp/client"
t -C attach -t test:0 < "$tmp/client" > /dev/null &
exec 3> "$tmp/client"
for _ in 1 2 3 4 5 6 7 8 9 10; do [[ $(t list-clients | wc -l) -gt 0 ]] && break; sleep 0.2; done
t select-window -t test:0
bash "$status" 'done'
[[ $(opt @agent_status) == 'done' && -z $(opt @agent_attention) ]] || fail "in view: $(opt @agent_attention)"
t select-window -t test:1
bash "$status" 'done'
[[ $(opt @agent_attention) == 1 ]] || fail 'out of view not marked'
exec 3>&-

# Resumed work keeps a notification that was not seen yet.
bash "$status" working
[[ $(opt @agent_status) == working && $(opt @agent_attention) == 1 ]] || fail 'working dropped the notification'

echo 'PASS: agent-tmux-status'
