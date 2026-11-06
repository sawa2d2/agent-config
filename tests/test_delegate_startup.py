#!/usr/bin/env python3
"""Deterministic failure boundaries plus real interactive-shell serialization."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('startup', Path(__file__).resolve().parents[1] / 'lib/delegate_startup.py')
startup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(startup)


class StartupTests(unittest.TestCase):
    def test_literal_submission_in_interactive_shell(self):
        # Execute physical input lines separately: bash -c alone would miss the
        # original bug where readline interprets embedded newlines as Enter.
        values = ["first\nsecond\r\t\x1b\x7f ' $(touch injected) `touch injected2` \\ end", '日本語', '']
        import json
        import os
        import pty
        import select
        import shutil
        import time
        for shell in ('bash', 'zsh'):
            if not shutil.which(shell):
                continue
            with self.subTest(shell=shell), tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / 'result.json'
                code = 'import json,sys;open(sys.argv[1],"w").write(json.dumps(sys.argv[2:]))'
                command = startup.shell_command(['python3', '-c', code, str(target), *values])
                self.assertFalse(any(ord(c) < 32 or ord(c) == 127 for c in command))
                pid, fd = pty.fork()
                if pid == 0:
                    os.chdir(directory)
                    os.environ['PS1'] = 'DELEGATE_READY> '
                    os.execvp(shell, [shell, '-f' if shell == 'zsh' else '--norc', '-i'])
                try:
                    # Wait for an actual interactive prompt before typing.
                    deadline = time.monotonic() + 5
                    output = b''
                    while time.monotonic() < deadline:
                        if select.select([fd], [], [], .1)[0]:
                            output += os.read(fd, 65536)
                            if b'DELEGATE_READY> ' in output:
                                break
                    self.assertIn(b'DELEGATE_READY> ', output)
                    deadline = time.monotonic() + 5
                    os.write(fd, command.encode() + b'\n')
                    while not target.exists() and time.monotonic() < deadline:
                        if select.select([fd], [], [], .1)[0]:
                            os.read(fd, 65536)
                    self.assertTrue(target.exists(), output)
                    self.assertEqual(json.loads(target.read_text()), values)
                    self.assertFalse(list(Path(directory).glob('injected*')))
                finally:
                    os.close(fd)
                    import signal
                    os.kill(pid, signal.SIGHUP)
                    os.waitpid(pid, 0)

    def test_codex_requires_explicit_report(self):
        from contextlib import nullcontext, redirect_stdout
        from importlib.machinery import SourceFileLoader
        import argparse
        import io
        import json
        loader = SourceFileLoader('codex_delegate', str(Path(__file__).resolve().parents[1] / 'bin/codex-delegate'))
        module_spec = importlib.util.spec_from_loader(loader.name, loader)
        codex = importlib.util.module_from_spec(module_spec)
        loader.exec_module(codex)
        for state in (None, 'running', 'completed', 'failed', 'needs-input'):
            with self.subTest(state=state), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                store = root / '.codex-tasks'
                store.mkdir()
                updates = []

                def run(*args):
                    if args[0] == 'gwt-path':
                        return directory
                    return '%9' if args[1] == 'new-window' else '123'

                def wait(check, seconds, description):
                    self.assertEqual(seconds, 90)
                    path = next(store.glob('*.json'))
                    data = json.loads(path.read_text())
                    if state:
                        data['report'] = dict(state=state, summary='Concrete fixture action')
                        path.write_text(json.dumps(data))
                    if not check():
                        raise startup.StartupError('report timeout')

                with patch.dict('os.environ', {'TMUX': 'fixture'}), \
                     patch.object(codex.shutil, 'which', return_value='fixture'), \
                     patch.object(codex, 'git', return_value=directory), \
                     patch.object(codex, 'run', side_effect=run), \
                     patch.object(codex, 'writing', side_effect=lambda *args: nullcontext(store)), \
                     patch.object(codex, 'update', side_effect=lambda *args, **fields: updates.append(fields)), \
                     patch.object(codex, 'submit') as submit, \
                     patch.object(codex, 'pane_alive'), \
                     patch.object(codex, 'wait_for', side_effect=wait), redirect_stdout(io.StringIO()):
                    args = argparse.Namespace(branch='fixture', prompt='Task', model=None)
                    if state in ('running', 'completed'):
                        codex.launch(args, (root, root, []))
                        self.assertEqual(updates[-1]['launch'], 'verified')
                    else:
                        with self.assertRaisesRegex(ValueError, 'No automatic retry'):
                            codex.launch(args, (root, root, []))
                        self.assertEqual(updates[-1]['launch'], 'failed')
                    submit.assert_called_once()
                    self.assertIn({'launch': 'sent'}, updates)

    def test_deadline_and_no_retry(self):
        clock = iter([0, 0, 10])
        with patch.object(startup.time, 'monotonic', side_effect=lambda: next(clock)), \
             patch.object(startup.time, 'sleep'), \
             patch.object(startup, 'tmux', return_value='0') as tmux:
            with self.assertRaisesRegex(startup.StartupError, 'shell acknowledgement'):
                startup.submit('%9', ['codex', 'new', 'task'])
        sends = [c.args for c in tmux.call_args_list if c.args[0] == 'send-keys']
        self.assertEqual(len(sends), 2)  # only the readiness probe, no agent

    def test_send_error_is_not_success(self):
        with patch.object(startup.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'tmux', stderr='permission denied')):
            with self.assertRaisesRegex(startup.StartupError, 'inaccessible.*permission denied'):
                startup.submit('%9', ['codex'])

    def test_submission_failure_never_resends(self):
        for failure in range(1, 5):
            sent = []

            def tmux(*args):
                sent.append(args)
                if len(sent) == failure:
                    raise startup.StartupError('fixture send failed')
                return ''
            with self.subTest(failure=failure), patch.object(startup, 'wait_for'), \
                 patch.object(startup, 'tmux', side_effect=tmux):
                with self.assertRaises(startup.StartupError):
                    startup.submit('%9', ['codex', 'new', 'task'])
                self.assertEqual(len(sent), failure)

    def test_bob_failed_paste_never_submits(self):
        def tmux(*args, **kwargs):
            if args[0] == 'paste-buffer':
                raise startup.StartupError('paste failed')
            return '0'
        with patch.object(startup, 'wait_for'), patch.object(startup, 'tmux', side_effect=tmux) as calls:
            with self.assertRaisesRegex(startup.StartupError, 'paste failed'):
                startup.bob_prompt('%9', 'task')
        self.assertEqual([call.args[0] for call in calls.call_args_list],
                         ['load-buffer', 'paste-buffer', 'delete-buffer'])

    def test_bob_timeout_never_pastes(self):
        with patch.object(startup, 'wait_for', side_effect=startup.StartupError('timeout')), \
             patch.object(startup, 'tmux') as tmux:
            with self.assertRaises(startup.StartupError):
                startup.bob_prompt('%9', 'task\nsecond line')
            tmux.assert_not_called()

    def test_bob_bracketed_literal_paste(self):
        with patch.object(startup, 'wait_for'), patch.object(startup, 'tmux', return_value='0') as tmux:
            startup.bob_prompt('%9', 'task\nsecond line')
        calls = tmux.call_args_list
        self.assertEqual(calls[0].args[0], 'load-buffer')
        self.assertEqual(calls[0].kwargs['input'], 'task\nsecond line')
        self.assertEqual(calls[1].args[:2], ('paste-buffer', '-p'))
        self.assertEqual(calls[2].args[0], 'delete-buffer')
        self.assertEqual(calls[3].args, ('send-keys', '-t', '%9', 'Enter'))

    def test_process_evidence_excludes_wrappers_and_prompt_arguments(self):
        with patch.object(startup, 'tmux', side_effect=['0', '100']), \
             patch.object(startup.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0,
                 '100 1 bash bash\n101 100 bash bash /bin/codex\n102 100 sleep sleep codex\n103 1 codex codex\n')):
            self.assertIsNone(startup.agent_process('%9', 'codex'))
        with patch.object(startup, 'tmux', side_effect=['0', '100']), \
             patch.object(startup.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0,
                 '100 1 bash bash\n101 100 node node /cli/bob.js quote\"unbalanced\n')):
            self.assertEqual(startup.agent_process('%9', 'bob'), 101)


if __name__ == '__main__':
    unittest.main()
