"""Offline installed-CLI probe, explicitly invoked with an absolute Codex binary.

The local provider emits synthetic usage and writes the fixture handoff note.
It does not test a real model's ability to follow the handoff skill.
"""
import http.server
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import subprocess
import sys
import tempfile
import threading
import time

resume = "--resume" in sys.argv[2:]
seeding = False
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="handoff-cli-probe-") as directory:
    base = Path(directory)
    home = base / "home"
    config = home / ".codex"
    work = base / "work"
    config.mkdir(parents=True)
    work.mkdir()
    subprocess.run(["git", "init", "-q", str(work)], check=True)
    requests = []

    class Provider(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            requests.append(body)
            serialized = json.dumps(body)
            markers = re.findall(r"Automatic handoff: [a-f0-9]{32}", serialized)
            if markers:
                (work / ".agent-handoff.md").write_text("# Goal\nContinue fixture work\n" + markers[-1])
            index = len(requests)
            item = {"id": "msg_" + str(index), "type": "message", "role": "assistant", "status": "completed",
                    "content": [{"type": "output_text", "text": "Fixture turn complete.", "annotations": []}]}
            response = {"id": "resp_" + str(index), "object": "response", "status": "completed", "output": [item],
                        "usage": {"input_tokens": 81000 if index == 1 and not seeding else 100, "output_tokens": 10,
                                  "total_tokens": 81010 if index == 1 and not seeding else 110}}
            events = [
                {"type": "response.created", "response": {**response, "status": "in_progress", "output": []}},
                {"type": "response.output_item.added", "output_index": 0, "item": {**item, "status": "in_progress", "content": []}},
                {"type": "response.output_text.delta", "item_id": item["id"], "output_index": 0, "content_index": 0, "delta": "Fixture turn complete."},
                {"type": "response.output_item.done", "output_index": 0, "item": item},
                {"type": "response.completed", "response": response},
            ]
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for event in events:
                self.wfile.write(("data: " + json.dumps(event) + "\n\n").encode())
            self.wfile.flush()

    provider = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Provider)
    threading.Thread(target=provider.serve_forever, daemon=True).start()
    (config / "config.toml").write_text(
        f'log_dir = "{config / "log"}"\n'
        'model = "gpt-6-sol"\nmodel_provider = "fixture"\n'
        'sandbox_mode = "read-only"\napproval_policy = "never"\n'
        'model_context_window = 200000\nmodel_auto_compact_token_limit = 190000\n'
        'check_for_update_on_startup = false\n[tui]\nresume_cwd = "current"\n'
        '[model_providers.fixture]\nname = "Fixture"\nwire_api = "responses"\n'
        f'base_url = "http://127.0.0.1:{provider.server_port}/v1"\n'
        f'[projects."{work}"]\ntrust_level = "trusted"\n')
    master, slave = pty.openpty()
    import fcntl
    import struct
    import termios
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 160, 0, 0))
    environment = {**os.environ, "HOME": str(home), "CODEX_HOME": str(config), "TERM": "xterm-256color"}
    environment.pop("CODEX_THREAD_ID", None)
    if resume:
        seeding = True
        seed = subprocess.Popen([sys.argv[1], "--no-daemon", "--no-alt-screen", "-s", "read-only", "-a", "never",
                                 "-C", str(work), "Seed the resume fixture."],
                                env=environment, cwd=work, stdin=slave, stdout=slave, stderr=slave,
                                start_new_session=True)
        try:
            seed_deadline = time.monotonic() + 30
            while time.monotonic() < seed_deadline and seed.poll() is None:
                if select.select([master], [], [], 0.1)[0]:
                    data = os.read(master, 65536)
                    if b"\x1b[6n" in data:
                        os.write(master, b"\x1b[1;1R")
                    if b"\x1b[c" in data:
                        os.write(master, b"\x1b[?1;2c")
                sessions = list((config / "sessions").rglob("*.jsonl"))
                if sessions and any('"task_complete"' in session.read_text() for session in sessions):
                    break
            else:
                raise AssertionError("seed interactive turn did not complete")
        finally:
            seed.terminate()
            try:
                seed.wait(timeout=5)
            except subprocess.TimeoutExpired:
                seed.kill()
                seed.wait()
        seeding = False
        sessions = list((config / "sessions").rglob("*.jsonl"))
        assert len(sessions) == 1, sessions
        metadata = json.loads(sessions[0].read_text().splitlines()[0])
        assert metadata["type"] == "session_meta", metadata
        resume_id = metadata["payload"]["id"]
        requests.clear()
    trace = base / "protocol.jsonl"
    harness = base / "harness.py"
    harness.write_text(r"""import importlib.machinery, json, sys
m = importlib.machinery.SourceFileLoader('handoff', sys.argv[1]).load_module()
original_loads = json.loads
def traced_loads(data, *args, **kwargs):
    try:
        return original_loads(data, *args, **kwargs)
    except ValueError:
        with open(sys.argv[2], 'a') as f:
            f.write('invalid JSON: ' + repr(data[:160]) + '\n')
        raise
json.loads = traced_loads
for direction in ('client', 'server'):
    original = getattr(m.Rotation, direction)
    def wrapped(self, msg, original=original, direction=direction):
        with open(sys.argv[2], 'a') as f:
            params = msg.get('params') or {}
            result = msg.get('result') or {}
            summary = {key: msg[key] for key in ('id', 'method', 'error') if key in msg}
            summary['params'] = {key: params[key] for key in ('threadId', 'turnId', 'tokenUsage', 'ephemeral', 'cwd', 'approvalPolicy', 'approvalsReviewer', 'sandbox', 'sandboxPolicy') if key in params}
            if 'turn' in params:
                summary['params']['turn'] = {key: params['turn'].get(key) for key in ('id', 'status', 'error')}
            if 'input' in params:
                summary['input'] = str(params['input'])[:240]
            if 'thread' in result:
                summary['result'] = {'threadId': result['thread']['id'], 'cwd': result.get('cwd', result['thread'].get('cwd'))}
            f.write(json.dumps([direction, summary, self.phase, self.dirty, self.thread, self.turn]) + '\n')
        return original(self, msg)
    setattr(m.Rotation, direction, wrapped)
sys.exit(m.run(sys.argv[3], sys.argv[4:]))
""")
    launch_args = (["resume", resume_id, "Complete the fixture task."] if resume else
                   ["-C", str(work), "Complete the fixture task."])
    process = subprocess.Popen([sys.executable, str(harness), str(root / "scripts/codex-auto-handoff"), str(trace), sys.argv[1],
                                "--no-alt-screen", "-c", "tui.animations=false", *([] if resume else ["-s", "read-only", "-a", "never"]), *launch_args], stdin=slave, stdout=slave, stderr=slave,
                               env=environment, cwd=work, start_new_session=True)
    os.close(slave)
    output = b""
    try:
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline and process.poll() is None and not any("Use the takeover skill to read .agent-handoff.md" in json.dumps(r.get("input")) for r in requests):
            if select.select([master], [], [], 0.1)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                output += data
                # Answer terminal capability queries without injecting human input.
                if b"\x1b[6n" in data:
                    os.write(master, b"\x1b[1;1R")
                if b"\x1b[c" in data:
                    os.write(master, b"\x1b[?1;2c")
        handoffs = [r for r in requests if "Automatic handoff:" in json.dumps(r.get("input"))]
        takeovers = [r for r in requests if "Use the takeover skill to read .agent-handoff.md" in json.dumps(r.get("input"))]
        assert handoffs and takeovers, (len(requests), output[-4000:].decode(errors="replace"), trace.read_text()[-6000:] if trace.exists() else "no trace", (config / "log/codex-tui.log").read_text()[-4000:] if (config / "log/codex-tui.log").exists() else "no TUI log")
        assert "Complete the fixture task." not in json.dumps(takeovers[-1].get("input")), "old context retained"
        events = [json.loads(line) for line in trace.read_text().splitlines()]
        starts = [event[1] for event in events if event[0] == "client" and event[1].get("method") == "thread/start" and not event[1]["params"].get("ephemeral")]
        assert len(starts) == (1 if resume else 2), events
        if resume:
            resumes = [event[1] for event in events if event[0] == "client" and event[1].get("method") == "thread/resume"]
            assert len(resumes) == 1, resumes
            assert resumes[0]["params"].get("threadId") == resume_id, resumes
            assert resumes[0]["params"].get("cwd") == str(work), resumes
        assert all(start["params"].get("sandbox") == "read-only" and start["params"].get("approvalPolicy") == "never" for start in starts), starts
        print("PASS: " + ("resume current cwd; " if resume else "new session; ") + "installed TUI connected, observed usage, completed handoff, cleared, and invoked takeover")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        os.close(master)
        provider.shutdown()
