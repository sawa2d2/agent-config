"""Deterministic protocol safety tests; no credentials or real user settings."""
import importlib.machinery
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

module = importlib.machinery.SourceFileLoader(
    "handoff", str(Path(__file__).resolve().parents[1] / "scripts/codex-auto-handoff")).load_module()


class RotationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.state = module.Rotation()
        self.start()
        self.state.client({"method": "turn/start", "params": {"threadId": "old"}})
        self.event("turn/started", turn={"id": "task"})

    def start(self, thread="old", method="thread/start", cwd=None):
        self.state.client({"id": 1, "method": method})
        self.state.server({"id": 1, "result": {"thread": {"id": thread}, "cwd": cwd or str(self.root)}})

    def event(self, method, **params):
        self.state.server({"method": method, "params": {"threadId": self.state.thread, **params}})

    def usage(self, value=81000, window=200000):
        self.event("thread/tokenUsage/updated", tokenUsage={
            "last": {"inputTokens": value, "cachedInputTokens": value, "totalTokens": value + 100},
            "total": {"inputTokens": 99999999}, "modelContextWindow": window})

    def complete(self, turn="task", status="completed"):
        self.event("turn/completed", turn={"id": turn, "status": status})

    def handoff(self):
        self.usage()
        self.complete()
        self.assertEqual(self.state.phase, "requested")
        self.state.client({"method": "turn/start", "params": {"threadId": "old", "input": [{"text": self.state.action}]}})
        self.event("turn/started", turn={"id": "handoff"})

    def test_sequence(self):
        self.handoff()
        note = self.root / ".agent-handoff.md"
        note.write_text("# Goal\nContinue\n" + self.state.marker)
        self.complete("wrong")
        self.assertEqual(self.state.phase, "handoff")
        self.complete("handoff")
        self.assertEqual(self.state.action, "/clear")
        self.start("fresh")
        self.assertEqual(self.state.action, module.TAKEOVER_PROMPT)
        self.assertEqual(self.state.phase, "takeover")
        previous_marker = self.state.marker
        self.state.client({"method": "turn/start", "params": {
            "threadId": "fresh", "input": [{"text": module.TAKEOVER_PROMPT}]}})
        self.event("turn/started", turn={"id": "takeover"})
        self.usage(1000)
        self.complete("takeover")
        self.state.client({"method": "turn/start", "params": {"threadId": "fresh"}})
        self.event("turn/started", turn={"id": "later"})
        self.usage()
        self.complete("later")
        self.assertEqual(self.state.phase, "requested")
        self.assertNotEqual(self.state.marker, previous_marker)

    def test_takeover_cannot_loop_immediately(self):
        self.handoff()
        (self.root / ".agent-handoff.md").write_text(self.state.marker)
        self.complete("handoff")
        self.start("fresh")
        self.state.client({"method": "turn/start", "params": {
            "threadId": "fresh", "input": [{"text": module.TAKEOVER_PROMPT}]}})
        self.event("turn/started", turn={"id": "takeover"})
        self.usage()
        self.complete("takeover")
        self.assertEqual(self.state.phase, "disabled")

    def test_only_interactive_commands_are_eligible(self):
        for args in (["exec", "hello"], ["-m", "model", "review"], ["--help"], ["resume", "--help"]):
            self.assertFalse(module.eligible(args))
        for args in ([], ["resume", "--last"], ["-m", "exec", "hello"], ["--", "exec"]):
            self.assertTrue(module.eligible(args))

    def test_total_and_cached_are_not_added(self):
        self.usage(34999)
        self.complete()
        self.assertEqual(self.state.phase, "watch")

    def test_absolute_threshold_without_window(self):
        self.usage(34999, None)
        self.complete()
        self.assertEqual(self.state.phase, "watch")
        self.event("turn/started", turn={"id": "task"})
        self.usage(35000, None)
        self.complete()
        self.assertEqual(self.state.phase, "requested")

    def test_absolute_threshold_with_larger_window(self):
        self.usage(35000)
        self.complete()
        self.assertEqual(self.state.phase, "requested")

    def test_window_threshold_and_compaction(self):
        self.usage(31999, 40000)
        self.complete()
        self.assertEqual(self.state.phase, "watch")
        self.event("turn/started", turn={"id": "task"})
        self.usage(32000, 40000)
        self.complete()
        self.assertEqual(self.state.phase, "requested")

    def test_latest_usage_wins(self):
        self.usage()
        self.usage(1000)
        self.complete()
        self.assertEqual(self.state.phase, "watch")

    def test_user_draft_prevents_rotation(self):
        self.usage()
        self.state.user_input()
        self.complete()
        self.assertEqual(self.state.phase, "watch")

    def test_interruption_prevents_clear(self):
        self.handoff()
        self.state.user_input()
        self.complete("handoff")
        self.assertEqual(self.state.phase, "disabled")
        self.assertIsNone(self.state.action)

    def test_missing_stale_and_symlink_notes(self):
        self.handoff()
        self.complete("handoff")
        self.assertEqual(self.state.phase, "disabled")

    def test_old_note_is_insufficient(self):
        (self.root / ".agent-handoff.md").write_text("Old note")
        self.handoff()
        self.complete("handoff")
        self.assertEqual(self.state.phase, "disabled")

    def test_failed_turn_never_clears(self):
        self.handoff()
        (self.root / ".agent-handoff.md").write_text(self.state.marker)
        self.complete("handoff", "failed")
        self.assertEqual(self.state.phase, "disabled")

    def test_symlink_is_rejected(self):
        (self.root / "other").write_text("old")
        (self.root / ".agent-handoff.md").symlink_to(self.root / "other")
        self.usage()
        self.complete()
        self.assertEqual(self.state.phase, "disabled")

    def test_wrong_worktree_does_not_take_over(self):
        self.handoff()
        (self.root / ".agent-handoff.md").write_text(self.state.marker)
        self.complete("handoff")
        self.start("fresh", cwd="/different")
        self.assertEqual(self.state.phase, "disabled")
        self.assertIsNone(self.state.action)

    def test_foreign_usage_does_not_trigger(self):
        self.state.server({"method": "thread/tokenUsage/updated", "params": {
            "threadId": "foreign", "tokenUsage": {"last": {"inputTokens": 999999}}}})
        self.complete()
        self.assertEqual(self.state.phase, "watch")

    def test_unchanged_marker_note_is_rejected(self):
        (self.root / ".agent-handoff.md").write_text(self.state.marker)
        self.handoff()
        self.complete("handoff")
        self.assertEqual(self.state.phase, "disabled")

    def test_ephemeral_title_threads_do_not_change_active_chat(self):
        self.handoff()
        self.state.client({"id": 9, "method": "thread/start", "params": {"ephemeral": True}})
        self.state.server({"id": 9, "result": {"thread": {"id": "title"}, "cwd": str(self.root)}})
        self.assertEqual(self.state.thread, "old")
        self.assertEqual(self.state.phase, "handoff")

    def test_settings_forwarded(self):
        self.assertEqual(module.server_options(["-c", "sandbox_mode='read-only'", "--enable", "foo", "-a", "never"]),
                         ["-c", "sandbox_mode='read-only'", "--enable", "foo"])
        with self.assertRaises(ValueError):
            module.server_options(["--profile", "personal"])


class TransportTests(unittest.TestCase):
    def test_remote_tui_defaults_to_explicit_local_cwd(self):
        for args in ([], ["resume", "--last"], ["fork", "--last"],
                     ["--", "--cd=prompt-text"], ["-m", "-Cmodel", "resume"]):
            with self.subTest(args=args):
                self.assertEqual(module.tui_arguments(args), ["--cd", os.getcwd(), *args])

    def test_remote_tui_preserves_explicit_cwd(self):
        for args in (["-C", "/chosen", "resume"], ["--cd", "/chosen", "resume"],
                     ["--cd=/chosen", "resume"], ["-C/chosen", "resume"],
                     ["resume", "--last", "--cd", "/chosen"]):
            with self.subTest(args=args):
                self.assertEqual(module.tui_arguments(args), args)

    def test_masked_partial_and_fragmented_frames(self):
        observer = module.WebSocketObserver()
        self.assertEqual(observer.feed(b"GET /rpc HTTP/1.1\r\n"), [])
        self.assertEqual(observer.feed(b"\r\n"), [])
        payload = b'{"method":"turn/completed"}'
        key = b"abcd"
        masked = bytes(value ^ key[index % 4] for index, value in enumerate(payload))
        frame = bytes([0x81, 0x80 | len(payload)]) + key + masked
        self.assertEqual(observer.feed(frame[:7]), [])
        self.assertEqual(observer.feed(frame[7:]), [json.loads(payload)])
        self.assertEqual(observer.feed(b'\x01\x01{' + b'\x89\x00' + b'\x80\x01}'), [{}])

    def test_extended_frame_lengths(self):
        for size in (200, 70000):
            observer = module.WebSocketObserver()
            payload = json.dumps({"text": "x" * size}).encode()
            width, code = (2, 126) if len(payload) < 65536 else (8, 127)
            data = b"HTTP/1.1 101 Switching Protocols\r\n\r\n"
            data += bytes([0x81, code]) + len(payload).to_bytes(width, "big") + payload
            self.assertEqual(observer.feed(data), [json.loads(payload)])


if __name__ == "__main__":
    unittest.main()
