"""Bounded tmux submission through the user's interactive Bash/Zsh shell."""

import argparse
from pathlib import Path
import subprocess
import sys
import time
import uuid


class StartupError(ValueError):
    pass


def launcher(agent):
    # Delegates need wrapper semantics (e.g. `codex new`), even when only
    # aliases select our launchers and PATH resolves the upstream CLI.
    return str(Path(__file__).resolve().parent.parent / "bin" / agent)


def tmux(*args, input=None):
    try:
        return subprocess.run(["tmux", *args], input=input, text=True,
                              capture_output=True, check=True, timeout=5).stdout.rstrip("\n")
    except (OSError, subprocess.SubprocessError) as error:
        detail = getattr(error, "stderr", None) or str(error)
        raise StartupError(f"tmux inaccessible or command failed ({args[0]}): {detail.strip()}") from error


def shell_command(arguments):
    # Real line breaks/control bytes sent as keys can execute shell bindings,
    # even inside quotes. ANSI-C quoting preserves bytes in Bash and Zsh while
    # keeping the submitted command on one physical line.
    def quote(value):
        escaped = ""
        for char in value:
            if char in "\\'":
                escaped += "\\" + char
            elif ord(char) < 32 or ord(char) == 127:
                escaped += f"\\{ord(char):03o}"
            else:
                escaped += char
        return "$'" + escaped + "'"
    return " ".join(quote(arg) for arg in arguments)


def wait_for(check, seconds, description):
    deadline = time.monotonic() + seconds
    while True:
        if check():
            return
        if time.monotonic() >= deadline:
            raise StartupError(f"timed out after {seconds}s waiting for {description}")
        time.sleep(0.25)


def pane_alive(pane):
    dead = tmux("display-message", "-p", "-t", pane, "#{pane_dead}")
    if dead != "0":
        raise StartupError(f"pane {pane} exited or is unavailable")


def submit(pane, arguments):
    # A shell acknowledgement proves startup files have finished and the pane
    # consumes commands. Never resend after a timeout: delivery is ambiguous.
    token = uuid.uuid4().hex
    probe = shell_command(["tmux", "set-option", "-p", "-t", pane,
                           "@delegate_ready", token])
    tmux("send-keys", "-t", pane, "-l", probe)
    tmux("send-keys", "-t", pane, "Enter")

    def ready():
        pane_alive(pane)
        return tmux("display-message", "-p", "-t", pane, "#{@delegate_ready}") == token
    wait_for(ready, 10, "interactive shell acknowledgement")
    tmux("send-keys", "-t", pane, "-l", shell_command(arguments))
    tmux("send-keys", "-t", pane, "Enter")


def agent_process(pane, agent):
    pane_alive(pane)
    pid = int(tmux("display-message", "-p", "-t", pane, "#{pane_pid}"))
    result = subprocess.run(["ps", "-eo", "pid=,ppid=,comm=,args="],
                            text=True, capture_output=True, check=True, timeout=5)
    rows = [line.split(None, 3) for line in result.stdout.splitlines()]
    descendants = {pid}
    while True:
        children = {int(row[0]) for row in rows if len(row) == 4 and int(row[1]) in descendants}
        if children <= descendants:
            break
        descendants |= children
    for row in rows:
        if len(row) != 4 or int(row[0]) not in descendants:
            continue
        # Exclude shell wrappers and prompt arguments that happen to name an
        # agent. Native binaries and node/python CLI entrypoints are supported.
        if row[2] in ("bash", "zsh", "sh", "fish", "dash"):
            continue
        # ps does not shell-quote argv; prompt quotes must not affect parsing.
        argv = row[3].split(None, 2)
        names = [Path(argv[0]).name] if argv else []
        if len(argv) > 1 and names[0] in ("node", "nodejs", "python", "python3"):
            names.append(Path(argv[1]).name)
        if row[2] == agent or any(name in (agent, agent + ".js") for name in names):
            return int(row[0])
    return None


def verify_process(pane, agent):
    observed = None
    since = 0

    def started():
        nonlocal observed, since
        pid = agent_process(pane, agent)
        if pid != observed:
            observed, since = pid, time.monotonic()
        return pid is not None and time.monotonic() - since >= 1
    wait_for(started, 30, f"a stable {agent} process in pane {pane}")


def bob_prompt(pane, prompt):
    def ready():
        pane_alive(pane)
        return agent_process(pane, "bob") is not None and "❯" in tmux("capture-pane", "-p", "-t", pane)
    wait_for(ready, 30, "Bob's input box")
    # Bracketed paste protects multiline content from being submitted as
    # separate messages. A named buffer preserves the user's paste buffer.
    buffer = "delegate-" + uuid.uuid4().hex
    tmux("load-buffer", "-b", buffer, "-", input=prompt)
    try:
        tmux("paste-buffer", "-p", "-t", pane, "-b", buffer)
    finally:
        tmux("delete-buffer", "-b", buffer)
    tmux("send-keys", "-t", pane, "Enter")
    pane_alive(pane)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pane")
    parser.add_argument("agent", choices=("claude", "bob"))
    parser.add_argument("prompt")
    parser.add_argument("model", nargs="?")
    args = parser.parse_args()
    label = "agent-delegate" if args.agent == "claude" else "bob-delegate"
    command = [launcher(args.agent)]
    if args.agent == "claude":
        if args.model:
            command += ["--model", args.model]
        command.append(args.prompt)
    else:
        command.append("new")
    try:
        submit(args.pane, command)
        print(f"{label}: launch input sent (pane {args.pane}); verifying startup", flush=True)
        verify_process(args.pane, args.agent)
        if args.agent == "bob":
            bob_prompt(args.pane, args.prompt)
        print(f"{label}: verified agent process startup (pane {args.pane}); "
              "prompt submitted, task acceptance/progress unverified")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"{label}: startup unconfirmed: {error}; retained pane {args.pane} and worktree. "
              "No automatic retry; inspect the pane before retrying to avoid duplicate agents.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
