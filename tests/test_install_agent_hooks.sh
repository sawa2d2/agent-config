#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
unset CODEX_HOME
stable="$HOME/.local/share/agent-config/hooks"
codex="$HOME/.codex/hooks.json"
bob="$HOME/.bob/settings/settings.json"
claude="$HOME/.claude/settings.json"
fail() { echo "FAIL: $*" >&2; exit 1; }
# PATH holds python3 and, in $tmp/rtk-bin only, a fake rtk.
mkdir -p "$tmp/bin" "$tmp/rtk-bin"
ln -s "$(command -v python3)" "$tmp/bin/python3"
printf '#!/bin/sh\n' > "$tmp/rtk-bin/rtk" && chmod +x "$tmp/rtk-bin/rtk"
install_hooks() { PATH="$tmp/bin:/usr/bin:/bin" bash "$root/scripts/install-agent-hooks"; }
install_hooks_rtk() { PATH="$tmp/rtk-bin:$tmp/bin:/usr/bin:/bin" bash "$root/scripts/install-agent-hooks"; }
check() {
  CODEX="$codex" BOB="$bob" CLAUDE="$claude" STATUS="$stable/agent-tmux-status" SUGGEST="$stable/bob-handoff-suggest" \
    APPROVAL="$stable/agent-approval-marker" python3 -c "
import json, os
bob, claude, codex = (json.load(open(os.environ[k])) for k in ('BOB', 'CLAUDE', 'CODEX'))
status, suggest, approval = os.environ['STATUS'], os.environ['SUGGEST'], os.environ['APPROVAL']
def states(settings, event):
    return [(g.get('matcher'), h['command']) for g in settings['hooks'].get(event, []) for h in g['hooks']]
assert $1, (bob, claude, codex)
" || fail "$1"
}

# New machine: all agents get status hooks, including Codex without rtk.
install_hooks > /dev/null
check "sorted(codex['hooks']) == ['Interrupt', 'PermissionRequest', 'PostToolUse', 'PreCompact', 'PreToolUse', 'SessionEnd', 'Stop', 'UserPromptSubmit']"
check "all(states(codex, e) == [(None, status + ' ' + state)] for e, state in [('PreToolUse', 'working'), ('PostToolUse', 'working'), ('PermissionRequest', 'waiting'), ('Stop', 'done'), ('Interrupt', 'clear'), ('SessionEnd', 'clear')])"
check "states(bob, 'Stop') == [(None, status + ' done')] and states(bob, 'SessionStart') == [(None, status + ' clear')]"
check "sorted(bob['hooks']) == ['PostToolUse', 'PreToolUse', 'SessionStart', 'Stop', 'UserPromptSubmit']"
check "states(claude, 'Notification') == [('permission_prompt', status + ' waiting')]"
check "sorted(claude['hooks']) == ['Notification', 'PostToolUse', 'PreToolUse', 'SessionEnd', 'Stop', 'UserPromptSubmit']"
check "states(bob, 'UserPromptSubmit') == [(None, status + ' prompt'), (None, suggest), (None, approval)]"
check "states(bob, 'PostToolUse') == [(None, status + ' working'), (None, suggest)]"
check "states(claude, 'UserPromptSubmit') == [(None, status + ' prompt'), (None, approval)]"
check "all(cmd.endswith((' prompt', ' working', ' done', ' waiting', ' clear')) for s in (bob, claude) for e in s['hooks'] for _, cmd in states(s, e) if cmd not in (suggest, approval))"

check "states(codex, 'UserPromptSubmit') == [(None, status + ' prompt'), (None, approval)]"

# The approval-wait command observes only: success with no decision output.
CODEX="$codex" python3 - <<'PYTEST'
import json, os, subprocess
settings = json.load(open(os.environ['CODEX']))
command = settings['hooks']['PermissionRequest'][0]['hooks'][0]['command']
env = {k: v for k, v in os.environ.items() if k not in ('TMUX', 'TMUX_PANE')}
result = subprocess.run(command, shell=True, input='{"tool_name":"Bash"}',
                        text=True, capture_output=True, env=env)
assert (result.returncode, result.stdout, result.stderr) == (0, '', ''), result
PYTEST

check "states(codex, 'PreCompact') == [('auto', '$stable/codex-handoff-suggest')]"

# Re-running leaves the files untouched.
before=$(cat "$bob" "$claude" "$codex")
out=$(install_hooks)
[[ -z $out && $(cat "$bob" "$claude" "$codex") == "$before" ]] || fail "second run changed files: $out"

# With rtk installed, its hook rewrites Claude's Bash and Bob's execute_command calls.
install_hooks_rtk > /dev/null
check "states(claude, 'PreToolUse') == [(None, status + ' working'), ('Bash', 'rtk hook claude')]"
check "states(bob, 'PreToolUse') == [(None, status + ' working'), ('^execute_command$', 'rtk hook claude')]"
check "states(codex, 'PreToolUse') == [(None, status + ' working'), ('Bash', '$stable/codex-rtk-hook')]"
rtk_before=$(cat "$bob" "$claude" "$codex")
out=$(install_hooks_rtk)
[[ -z $out && $(cat "$bob" "$claude" "$codex") == "$rtk_before" ]] || fail "second rtk run changed files: $out"

# Once rtk is gone, its entries are removed.
install_hooks > /dev/null
[[ $(cat "$bob" "$claude" "$codex") == "$before" ]] || fail 'rtk entries not removed'

codex_before=$(cat "$codex")
# A custom Codex home preserves unmanaged entries and replaces old managed paths.
export CODEX_HOME="$tmp/custom-codex"
mkdir -p "$CODEX_HOME"
cat > "$CODEX_HOME/hooks.json" <<'JSON'
{"description": "mine", "hooks": {"UserPromptSubmit": [
  {"hooks": [{"type": "command", "command": "echo custom"}]},
  {"hooks": [{"type": "command", "command": "/old/scripts/agent-approval-marker"}]}]}}
JSON
install_hooks >/dev/null
HANDOFF="$stable/codex-handoff-suggest" STATUS="$stable/agent-tmux-status" CUSTOM="$CODEX_HOME/hooks.json" APPROVAL="$stable/agent-approval-marker" python3 - <<'CHECK'
import json, os
settings = json.load(open(os.environ['CUSTOM']))
assert settings['hooks'].pop('PreCompact') == [{'matcher': 'auto', 'hooks': [{'type': 'command', 'command': os.environ['HANDOFF']}]}]
assert settings['description'] == 'mine'
assert settings['hooks']['UserPromptSubmit'] == [
    {'hooks': [{'type': 'command', 'command': 'echo custom'}]},
    {'hooks': [{'type': 'command', 'command': os.environ['STATUS'] + ' prompt'}]},
    {'hooks': [{'type': 'command', 'command': os.environ['APPROVAL']}]}]
CHECK
[[ $(cat "$codex") == "$codex_before" ]] || fail 'default Codex home changed'
unset CODEX_HOME

# Other hooks and settings are kept; entries from another checkout path are replaced.
cat > "$claude" <<'JSON'
{"theme": "dark", "hooks": {
  "Stop": [{"hooks": [{"type": "command", "command": "say done"}]},
           {"hooks": [{"type": "command", "command": "/old/agent-config/scripts/agent-tmux-status done"}]}],
  "PreCompact": [{"hooks": [{"type": "command", "command": "/old/agent-config/scripts/agent-tmux-status working"}]}]}}
JSON
chmod 600 "$claude"
install_hooks > /dev/null
check "claude['theme'] == 'dark'"
check "states(claude, 'Stop') == [(None, 'say done'), (None, status + ' done')]"
check "'PreCompact' not in claude['hooks']"
[[ $(stat -c %a "$claude" 2>/dev/null || stat -f %Lp "$claude") == 600 ]] || fail 'mode not kept'

# Codex preserves unmanaged hooks, including siblings of an old managed hook,
# and respects CODEX_HOME without changing the default file.
cp "$codex" "$tmp/default-codex.json"
export CODEX_HOME="$tmp/custom-codex"
mkdir -p "$CODEX_HOME"
codex="$CODEX_HOME/hooks.json"
cat > "$codex" <<'JSON'
{"custom": true, "hooks": {"PermissionRequest": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": "custom-permission-policy"},
  {"type": "command", "command": "/old/scripts/agent-tmux-status waiting"}]}]}}
JSON
chmod 600 "$codex"
install_hooks > /dev/null
check "codex['custom'] and states(codex, 'PermissionRequest') == [('Bash', 'custom-permission-policy'), (None, status + ' waiting')]"
[[ $(stat -c %a "$codex" 2>/dev/null || stat -f %Lp "$codex") == 600 ]] || fail 'Codex mode not kept'
cmp "$HOME/.codex/hooks.json" "$tmp/default-codex.json" || fail 'default CODEX_HOME changed'
custom_before=$(cat "$codex")
[[ -z $(install_hooks) && $(cat "$codex") == "$custom_before" ]] || fail 'custom CODEX_HOME not idempotent'

# Commands survive paths with spaces.
mkdir -p "$tmp/with space"
cp -R "$root/scripts" "$tmp/with space/"
PATH="$tmp/bin:/usr/bin:/bin" bash "$tmp/with space/scripts/install-agent-hooks" > /dev/null
check "states(bob, 'Stop') == [(None, status + ' done')]"

# Invalid settings are refused without changes.
printf '%s\n' '{"hooks": {"Stop": {}}}' > "$bob"
install_hooks > /dev/null 2>&1 && fail 'invalid hooks accepted'
[[ $(cat "$bob") == '{"hooks": {"Stop": {}}}' ]] || fail 'invalid hooks changed'
# A symlinked settings file is updated through the link; a dangling link gets a new target.
rm "$bob" && ln -s "$tmp/links/target.json" "$bob"
install_hooks > /dev/null || fail 'symlink refused'
[[ -L $bob ]] || fail 'symlink replaced'
grep -q agent-tmux-status "$tmp/links/target.json" || fail 'symlink target not updated'

# Installed executables survive deletion of either kind of source checkout.
python3 - "$root" "$tmp" <<'REGRESSION'
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

root, temporary = map(Path, sys.argv[1:])
for codex_only in (False, True):
    base = temporary / ("codex only" if codex_only else "all agents")
    source = base / "source checkout"
    shutil.copytree(root / "scripts", source / "scripts")
    home = base / "home with spaces"
    stable = home / ".local/share/agent-config/hooks"
    codex = base / "custom codex/hooks.json"
    bob = home / ".bob/settings/settings.json"
    claude = home / ".claude/settings.json"
    for config in (bob, claude, codex):
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text('{"custom": true, "hooks": {}}')
        config.chmod(0o600)
    bin_dir = base / "bin"
    bin_dir.mkdir()
    rtk = bin_dir / "rtk"
    rtk.write_text("#!/bin/sh\nprintf '{}\\n'\n")
    rtk.chmod(0o755)
    env = dict(os.environ, HOME=str(home), CODEX_HOME=str(codex.parent),
               PATH=str(bin_dir) + ":/usr/bin:/bin")
    # Never touch live tmux sessions, approval markers, or Bob state.
    for key in ("TMUX", "TMUX_PANE", "AGENT_APPROVAL_DIR", "XDG_STATE_HOME"):
        env.pop(key, None)
    command = ["bash", str(source / "scripts/install-agent-hooks")]
    if codex_only:
        command.append("--codex-only")
    subprocess.run(command, env=env, check=True, capture_output=True)
    configs = (codex,) if codex_only else (bob, claude, codex)
    names = {"agent-tmux-status", "agent-approval-marker", "codex-handoff-suggest", "codex-rtk-hook"}
    if not codex_only:
        names.add("bob-handoff-suggest")
    assert {p.name for p in stable.iterdir()} == names
    if codex_only:
        assert all(p.read_text() == '{"custom": true, "hooks": {}}' for p in (bob, claude))
    tracked = [*configs, *stable.iterdir()]
    before = [(p.read_bytes(), p.stat().st_ino, p.stat().st_mtime_ns) for p in tracked]
    rerun = subprocess.run(command, env=env, check=True, capture_output=True)
    assert not rerun.stdout, rerun.stdout
    assert before == [(p.read_bytes(), p.stat().st_ino, p.stat().st_mtime_ns) for p in tracked]
    # Updates replace installed content and restore source executable permissions.
    script = source / "scripts/codex-handoff-suggest"
    script.write_text(script.read_text() + "\n# updated source\n")
    (stable / script.name).chmod(0o600)
    subprocess.run(command, env=env, check=True, capture_output=True)
    assert (stable / script.name).read_bytes() == script.read_bytes()
    shutil.rmtree(source)
    executed = set()
    for config in configs:
        settings = json.loads(config.read_text())
        assert settings['custom'] and config.stat().st_mode & 0o777 == 0o600
        for event, groups in settings['hooks'].items():
            for group in groups:
                for handler in group['hooks']:
                    hook = handler['command']
                    executable = Path(shlex.split(hook)[0])
                    if executable.name != 'rtk':
                        assert executable.parent == stable and not executable.is_symlink(), hook
                        assert executable.stat().st_mode & 0o111, hook
                        executed.add(executable.name)
                    payload = dict(hook_event_name=event, trigger="auto", prompt="test",
                                   tool_input={"command": "ls"})
                    result = subprocess.run(hook, shell=True, env=env, cwd=base,
                                            input=json.dumps(payload), text=True, capture_output=True)
                    assert result.returncode == 0 and not result.stderr, (hook, result)
                    if executable.name == 'codex-handoff-suggest':
                        assert 'systemMessage' in json.loads(result.stdout)
    assert executed == names, executed
REGRESSION

echo 'PASS: install-agent-hooks'
