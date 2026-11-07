"""Isolated integration checks against an explicitly selected real Codex CLI.

Usage: python3 tests/codex_worktree_trust_test.py /absolute/path/to/codex
No model sessions, credentials, or user settings are used.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
cli = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="codex-trust-test-") as temporary:
    base = Path(temporary)
    home = base / "home"
    home.mkdir()
    tools = base / "bin"
    tools.mkdir()
    (tools / "codex").symlink_to(cli)
    env = dict(os.environ, HOME=str(home), PATH=str(tools) + os.pathsep + os.environ['PATH'])
    env.pop('CODEX_HOME', None)
    invoke = ('import runpy,sys; runpy.run_path(sys.argv[1])["trust_worktree"](sys.argv[2])')

    def register(directory, extra=None, ok=True):
        directory.mkdir(exist_ok=True)
        result = subprocess.run([sys.executable, '-c', invoke, str(root / 'bin/codex-delegate'), str(directory)],
                                cwd=base, env=env | (extra or {}), text=True, capture_output=True, timeout=35)
        assert (result.returncode == 0) == ok, (result.stdout, result.stderr)
        return result

    # Missing default config, literal path punctuation/Unicode, and idempotence.
    directory = base / 'work.tree "quoted" \\ 日本語'
    register(directory)
    default = home / '.codex/config.toml'
    initial = default.read_bytes()
    register(directory)
    assert default.read_bytes() == initial

    # Custom CODEX_HOME; preserve comments, policies, other projects and keys.
    custom = base / 'custom codex'
    custom.mkdir()
    config = custom / 'config.toml'
    prefix = '# Keep this comment\nsandbox_mode = "workspace-write"\napproval_policy = "on-request"\n'
    prefix += '[projects."/existing"]\ntrust_level = "untrusted" # Keep this too\n'
    config.write_text(prefix)
    extra = {'CODEX_HOME': str(custom)}
    register(directory, extra)
    assert config.read_text().startswith(prefix)
    assert default.read_bytes() == initial
    updated = config.read_bytes()
    register(directory, extra)
    assert config.read_bytes() == updated
    config.write_text(config.read_text().replace('trust_level = "trusted"', 'trust_level = "untrusted"'))
    register(directory, extra)
    assert config.read_bytes() == updated

    # Delegates sharing a config must not lose each other's entries.
    directories = [base / ('parallel.' + str(i)) for i in range(3)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(lambda path: register(path, extra), directories))
    text = config.read_text()
    for path in directories:
        assert '[projects.' + json.dumps(str(path)) + ']' in text
    assert text.startswith(prefix)

    # Malformed user config is retained and produces a visible failure.
    config.write_text('invalid = [\n')
    result = register(base / 'invalid', extra, ok=False)
    assert 'trust' in result.stderr
    assert config.read_text() == 'invalid = [\n'
print('PASS: real Codex trust writer, default/custom home, punctuation, preservation, idempotence, concurrency and invalid config')
