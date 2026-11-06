#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
export CODEX_HOME="$HOME/.codex"
mkdir -p "$HOME"

python3 - "$root/install" "$tmp" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys

installer, base = map(Path, sys.argv[1:])
home = Path(os.environ['HOME'])
primary = base / 'repo with spaces'
linked = base / 'linked with spaces'
links = {
    '.local/share/agent-config/operations': 'deploy/operations',
    '.bob/rules/agent-config.md': 'deploy/AGENTS.md',
    '.claude/CLAUDE.md': 'deploy/AGENTS.md',
    '.codex/AGENTS.md': 'deploy/codex/AGENTS.md',
    '.codex/rules/agent-config.rules': 'deploy/codex/rules/agent-config.rules',
    **{f'.local/bin/{name}': f'bin/{name}' for name in (
        'agent-delegate', 'bob-delegate', 'codex-delegate', 'codex-ralph', 'agent-backlog')},
}


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True)
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    return result.stdout


def git(*args):
    return run('git', '-C', str(primary), *args)


def install(checkout=primary, refused=None):
    result = subprocess.run(['bash', str(checkout / 'install')], text=True, capture_output=True)
    if refused is None:
        assert result.returncode == 0, (result.stdout, result.stderr)
        assert 'stub: install-claude-plugins' in result.stdout, 'installer did not finish'
        for dest, source in links.items():
            assert (home / dest).readlink() == checkout / source, dest
    else:
        assert result.returncode != 0, 'custom path accepted'
        assert f'Refusing to replace existing {refused}' in result.stderr, result.stderr


primary.mkdir()
run('git', 'init', '-q', str(primary))
shutil.copyfile(installer, primary / 'install')
for source in set(links.values()):
    path = primary / source
    if source == 'deploy/operations':
        path.mkdir(parents=True)
        path /= 'reference.md'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('fixture\n')
# Stub every unrelated subinstaller: no package downloads, settings or hooks.
for name in (
    'install-rtk', 'install-claude-settings', 'install-bob-theme',
    'install-codex-theme', 'install-codex-compaction', 'install-codex-subagent-model',
    'install-bob-settings', 'install-agent-hooks', 'install-tools',
    'install-nix-tools', 'install-claude-plugins',
):
    path = primary / 'scripts' / name
    path.parent.mkdir(exist_ok=True)
    path.write_text(f"printf 'stub: {name}\\n'\n")
git('add', '.')
git('-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'fixture')
git('worktree', 'add', '-qb', 'linked', str(linked))

# Fresh install, idempotence, both checkout directions, paths containing spaces.
install()
install()
install(linked)
install()

# Both former shared Codex links are migrated, including another checkout's.
for checkout in (primary, linked):
    dest = home / '.codex/AGENTS.md'
    dest.unlink()
    dest.symlink_to(checkout / 'deploy/AGENTS.md')
    install()

# A clone with identical contents is still a different repository.
foreign = base / 'foreign'
run('git', 'clone', '-q', str(primary), str(foreign))
for dest, source in links.items():
    path = home / dest
    for target in (foreign / source, primary / 'custom' / source,
                   base / 'unregistered' / source, Path('relative-custom-target')):
        path.unlink()
        path.symlink_to(target)
        install(refused='symlink: ' + str(path))
        assert path.readlink() == target, path
        path.unlink()
        path.symlink_to(primary / source)
    # Files and directories are preserved, including globals and CLI paths.
    path.unlink()
    path.write_text('user content\n')
    install(refused='path: ' + str(path))
    assert path.read_text() == 'user content\n', path
    path.unlink()
    path.mkdir()
    (path / 'custom').write_text('keep\n')
    install(refused='path: ' + str(path))
    assert (path / 'custom').read_text() == 'keep\n', path
    shutil.rmtree(path)
    path.symlink_to(primary / source)

# Deleted but registered worktrees retain enough provenance for safe repair.
install(linked)
shutil.rmtree(linked)
install()

# Once registration is removed, dangling targets cannot be safely attributed.
git('worktree', 'prune', '--expire=now')
for dest, source in links.items():
    path = home / dest
    path.unlink()
    path.symlink_to(linked / source)
    install(refused='symlink: ' + str(path))
    assert path.readlink() == linked / source, path
    path.unlink()
    path.symlink_to(primary / source)

# Without Git metadata, exact-current-source installs still work.
archive = base / 'archive'
shutil.copytree(primary, archive, ignore=shutil.ignore_patterns('.git'))
shutil.rmtree(home)
home.mkdir()
install(archive)
install(archive)
print('PASS: install worktree links')
PY
