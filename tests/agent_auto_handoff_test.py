"""Hook lifecycle and terminal integration, isolated from credentials/settings."""
import importlib.machinery
import json
import os
from pathlib import Path
import pty
import select
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
module = importlib.machinery.SourceFileLoader("agents_handoff", str(ROOT / "scripts/agent-auto-handoff")).load_module()


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def event(self, state, name, session="old", **fields):
        return state.event(dict(hook_event_name=name, session_id=session, cwd=str(self.root), **fields))

    def handoff(self, agent):
        state = module.Rotation(agent)
        self.event(state, "SessionStart", source="startup")
        self.event(state, "UserPromptSubmit", prompt="work")
        with patch.object(module, "measurement", return_value=81000):
            self.event(state, "Stop")
        self.assertEqual(state.phase, "requested")
        prompt = state.action
        self.event(state, "UserPromptSubmit", prompt=prompt)
        (self.root / ".agent-handoff.md").write_text(state.marker)
        with patch.object(module, "measurement", return_value=82000):
            self.event(state, "Stop")
        self.assertEqual(state.action, "/clear")
        return state

    def test_both_agents_rotate_twice(self):
        for agent in ("claude", "bob"):
            with self.subTest(agent=agent):
                state = self.handoff(agent)
                marker = state.marker
                self.event(state, "SessionStart", "fresh", source="clear" if agent == "claude" else "startup")
                self.assertEqual(state.phase, "takeover")
                self.assertIsNone(state.action) if agent == "bob" else self.assertEqual(state.action, module.core.TAKEOVER_PROMPT)
                self.assertIsNot(self.event(state, "UserPromptSubmit", "fresh", prompt=module.core.TAKEOVER_PROMPT), False)
                with patch.object(module, "measurement", return_value=1000):
                    self.event(state, "Stop", "fresh")
                self.event(state, "UserPromptSubmit", "fresh", prompt="more work")
                with patch.object(module, "measurement", return_value=81000):
                    self.event(state, "Stop", "fresh")
                self.assertEqual(state.phase, "requested")
                self.assertNotEqual(state.marker, marker)

    def test_bob_failed_clear_blocks_takeover(self):
        state = self.handoff("bob")
        self.assertIs(self.event(state, "UserPromptSubmit", prompt=module.core.TAKEOVER_PROMPT), False)
        self.assertEqual(state.phase, "disabled")

    def test_claude_wrong_session_source_prevents_takeover(self):
        state = self.handoff("claude")
        self.event(state, "SessionStart", "fresh", source="resume")
        self.assertEqual(state.phase, "disabled")
        self.assertIsNone(state.action)

    def test_background_work_never_clears(self):
        state = module.Rotation("claude")
        self.event(state, "SessionStart")
        self.event(state, "UserPromptSubmit", prompt="work")
        self.event(state, "Stop", background_tasks=[{"id": "running"}])
        self.assertEqual(state.phase, "disabled")

    def test_stop_hook_continuation_never_clears(self):
        state = module.Rotation("claude")
        self.event(state, "SessionStart")
        self.event(state, "UserPromptSubmit", prompt="work")
        self.event(state, "Stop", stop_hook_active=True)
        self.assertEqual(state.phase, "disabled")
        self.assertIsNone(state.action)

    def test_user_draft_and_missing_note(self):
        for draft in (False, True):
            state = module.Rotation("claude")
            self.event(state, "SessionStart")
            self.event(state, "UserPromptSubmit", prompt="work")
            if draft:
                state.user_input()
            with patch.object(module, "measurement", return_value=81000):
                self.event(state, "Stop")
                if draft:
                    self.assertEqual(state.phase, "watch")
                else:
                    self.event(state, "UserPromptSubmit", prompt=state.action)
                    self.event(state, "Stop")
                    self.assertEqual(state.phase, "disabled")
                    self.assertIsNone(state.action)

    def test_claude_usage_includes_cache_only_once(self):
        transcript = self.root / "transcript.jsonl"
        transcript.write_text(json.dumps({"type": "assistant", "message": {"usage": {
            "input_tokens": 100, "cache_creation_input_tokens": 200,
            "cache_read_input_tokens": 80000, "output_tokens": 500}}}) + "\n")
        self.assertEqual(module.measurement("claude", {"transcript_path": str(transcript)}), 80300)

    def test_claude_threshold_includes_cache(self):
        transcript = self.root / "transcript.jsonl"
        state = module.Rotation("claude")
        self.event(state, "SessionStart", source="startup")
        for cached, phase in ((34699, "watch"), (34700, "requested")):
            with self.subTest(cached=cached):
                transcript.write_text(json.dumps({"type": "assistant", "message": {"usage": {
                    "input_tokens": 100, "cache_creation_input_tokens": 200,
                    "cache_read_input_tokens": cached, "output_tokens": 500}}}) + "\n")
                self.event(state, "UserPromptSubmit", prompt="work")
                self.event(state, "Stop", transcript_path=str(transcript))
                self.assertEqual(state.phase, phase)

    def test_bob_uses_latest_context_not_cumulative_cost(self):
        home = self.root / ".bob"
        (home / "db").mkdir(parents=True)
        # No settings file is needed: cost limits do not control rotation.
        with sqlite3.connect(home / "db/bob.db") as db:
            db.executescript("CREATE TABLE tasks(id TEXT, costs TEXT, parent_id TEXT); CREATE TABLE messages(task_id TEXT, role TEXT, data TEXT, created_at INTEGER);")
            db.execute("INSERT INTO tasks VALUES ('old', ?, NULL)", (json.dumps({"cost": 1000}),))
        with patch.dict(os.environ, HOME=str(self.root)):
            for timestamp, tokens in enumerate((50001, 1000, 50000, 50001)):
                with self.subTest(tokens=tokens), sqlite3.connect(home / "db/bob.db") as db:
                    db.execute("INSERT INTO messages VALUES ('old', 'assistant', ?, ?)",
                               (json.dumps({"_meta": {"spend": {"contextTokens": tokens}}}), timestamp))
                self.assertEqual(module.measurement("bob", {"session_id": "old"}),
                                 module.core.LIMIT if tokens > 50000 else 0)


class TerminalTests(unittest.TestCase):
    def test_interactive_wrappers_require_explicit_opt_in(self):
        for agent in ("claude", "bob", "codex"):
            for explicit in (False, True):
                for args in ([], ["new"], ["chat", "--resume", "latest"] if agent == "bob" else ["resume"]):
                    with self.subTest(agent=agent, explicit=explicit, args=args), tempfile.TemporaryDirectory() as directory:
                        base = Path(directory)
                        (base / "bin").mkdir()
                        fake = base / "bin" / agent
                        fake.write_text('#!/bin/sh\necho NATIVE_CLI\nprintf "arg:%s\\n" "$@"\n')
                        fake.chmod(0o755)
                        # Observe routing without starting a real CLI or provider.
                        python = base / "bin/python3"
                        python.write_text('#!/bin/sh\ncase "$1" in */scripts/*auto-handoff) echo AUTO_HANDOFF; printf "arg:%s\\n" "$@"; exit 0;; esac\nexec '
                                          + sys.executable + ' "$@"\n')
                        python.chmod(0o755)
                        env = {**os.environ, "HOME": str(base / "home"), "CODEX_HOME": str(base / "codex"),
                               "XDG_CONFIG_HOME": str(base / "config"), "PATH": str(base / "bin") + ":/usr/bin:/bin"}
                        master, slave = pty.openpty()
                        command = ["bash", str(ROOT / "bin" / agent), *(["auto-handoff"] if explicit else []), *args]
                        child = subprocess.Popen(command, env=env, stdin=slave, stdout=slave, stderr=slave)
                        os.close(slave)
                        output = b""
                        try:
                            deadline = time.monotonic() + 15
                            while time.monotonic() < deadline:
                                if select.select([master], [], [], .1)[0]:
                                    try:
                                        output += os.read(master, 65536)
                                    except OSError:
                                        break
                                elif child.poll() is not None:
                                    break
                            self.assertEqual(child.wait(timeout=2), 0, output.decode(errors="replace"))
                            self.assertIn(b"AUTO_HANDOFF" if explicit else b"NATIVE_CLI", output)
                            self.assertNotIn(b"NATIVE_CLI" if explicit else b"AUTO_HANDOFF", output)
                            self.assertNotIn(b"arg:auto-handoff", output)
                            self.assertNotIn(b"arg:new", output)
                        finally:
                            if child.poll() is None:
                                child.kill()
                                child.wait()
                            os.close(master)

    def test_native_hook_relay_and_repeated_rotation(self):
        for agent in ("claude", "bob"):
            with self.subTest(agent=agent), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                subprocess.run(["git", "init", "-q", str(work)], check=True)
                fake = work / "fake-cli"
                fake.write_text('#!' + sys.executable + '\n' + FAKE)
                fake.chmod(0o755)
                home = work / "home"
                (home / ".bob/db").mkdir(parents=True)
                (home / ".bob/settings").mkdir()
                (home / ".bob/settings/settings.json").write_text('{"session":{"maxCost":20}}')
                with sqlite3.connect(home / ".bob/db/bob.db") as db:
                    db.executescript("CREATE TABLE tasks(id TEXT, costs TEXT, parent_id TEXT); CREATE TABLE messages(task_id TEXT, role TEXT, data TEXT, created_at INTEGER);")
                env = {**os.environ, "HOME": str(home), "FIXTURE_AGENT": agent,
                       "FIXTURE_RELAY": str(ROOT / "scripts/agent-handoff-event")}
                master, slave = pty.openpty()
                child = subprocess.Popen([sys.executable, str(ROOT / "scripts/agent-auto-handoff"), agent, str(fake)],
                                         cwd=work, env=env, stdin=slave, stdout=slave, stderr=slave)
                os.close(slave)
                output = b""
                try:
                    deadline = time.monotonic() + 20
                    while child.poll() is None and time.monotonic() < deadline:
                        if select.select([master], [], [], .1)[0]:
                            try:
                                output += os.read(master, 65536)
                            except OSError:
                                break
                    self.assertEqual(child.wait(timeout=2), 0, output.decode(errors="replace"))
                    self.assertIn(b"TWO ROTATIONS VERIFIED", output)
                finally:
                    if child.poll() is None:
                        child.kill()
                        child.wait()
                    os.close(master)


FAKE = r'''
import json, os, pathlib, re, sqlite3, subprocess, sys, tty
agent = os.environ['FIXTURE_AGENT']
if '--version' in sys.argv:
    print('2.1.319 (Claude Code)' if agent == 'claude' else '2.0.9')
    sys.exit()
root = pathlib.Path.cwd()
session = 'old'
transcript = root / 'transcript.jsonl'
new = True
rotations = 0

def event(name, **kw):
    value = dict(hook_event_name=name, session_id=session, cwd=str(root), transcript_path=str(transcript), **kw)
    result = subprocess.run([os.environ['FIXTURE_RELAY']], input=json.dumps(value), text=True, capture_output=True)
    if result.returncode:
        print(result.stderr, flush=True)
        sys.exit(4)

def usage(tokens):
    transcript.write_text(json.dumps({'type':'assistant','message':{'usage':{'input_tokens':tokens}}})+'\n')
    with sqlite3.connect(pathlib.Path.home()/'.bob/db/bob.db') as db:
        db.execute('DELETE FROM tasks')
        db.execute('DELETE FROM messages')
        db.execute('INSERT INTO tasks VALUES (?, ?, NULL)', (session, '{"cost":0}'))
        db.execute('INSERT INTO messages VALUES (?, ?, ?, 1)', (session, 'assistant', json.dumps({'_meta':{'spend':{'contextTokens':tokens}}})))

def prompt(text):
    global new
    if new:
        event('SessionStart', source='startup')
        new = False
    event('UserPromptSubmit', prompt=text)

tty.setraw(0)
prompt('work')
usage(81000)
event('Stop')
buffer = b''
while True:
    c = os.read(0, 1)
    if c != b'\r':
        buffer += c
        continue
    text = buffer.decode().replace('\x1b[200~','').replace('\x1b[201~','')
    buffer = b''
    if text == '/clear':
        rotations += 1
        session = 'fresh-' + str(rotations)
        new = True
        if agent == 'claude':
            event('SessionStart', source='clear')
            new = False
    elif 'Automatic handoff:' in text:
        prompt(text)
        marker = re.search(r'Automatic handoff: [a-f0-9]+', text).group()
        (root/'.agent-handoff.md').write_text('# Goal\nKeep working\n'+marker)
        usage(82000)
        event('Stop')
    elif 'Use the takeover skill' in text:
        prompt(text)
        usage(1000)
        event('Stop')
        if rotations == 2:
            print('TWO ROTATIONS VERIFIED', flush=True)
            sys.exit()
        prompt('more work')
        usage(81000)
        event('Stop')
    else:
        print('unexpected input: '+repr(text), flush=True)
        sys.exit(5)
'''

if __name__ == "__main__":
    unittest.main()
