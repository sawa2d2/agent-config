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
git('branch', '-M', 'main')
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
remote = base / 'remote.git'
run('git', 'init', '--bare', '-q', str(remote))
git('remote', 'add', 'origin', str(remote))
git('push', '-qu', 'origin', 'main')
git('worktree', 'add', '-qb', 'linked', str(linked))
run('git', '-C', str(linked), 'push', '-qu', 'origin', 'linked')

# Fresh install and idempotence from the persistent original checkout.
install()
install()
# A development installer must stop before pull or any HOME mutation.
run('git', '-C', str(linked), 'branch', '--unset-upstream')
result = subprocess.run(['bash', str(linked / 'install')], text=True, capture_output=True)
assert result.returncode != 0
assert 'Refusing global installation from a linked worktree' in result.stderr
assert 'There is no tracking information' not in result.stderr
for dest, source in links.items():
    assert (home / dest).readlink() == primary / source


def seed_old_worktree_links():
    # Reproduce links created by installers predating the original-checkout guard.
    for dest, source in links.items():
        path = home / dest
        path.unlink()
        path.symlink_to(linked / source)

# Retire only rule symlinks owned by registered checkouts, including dangling links.
rule = home / '.codex/rules/agent-config.rules'
rule.parent.mkdir(parents=True, exist_ok=True)
for checkout in (primary, linked):
    rule.symlink_to(checkout / 'deploy/codex/rules/agent-config.rules')
    install()
    assert not rule.is_symlink()
rule.symlink_to(base / 'custom.rules')
install()
assert rule.readlink() == base / 'custom.rules'
rule.unlink()
rule.write_text('user rules\n')
install()
assert rule.read_text() == 'user rules\n'
rule.unlink()

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
        # Unrelated targets are protected while they exist.
        resolved = path.parent / target
        if not resolved.exists():
            resolved.mkdir(parents=True)
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
seed_old_worktree_links()
shutil.rmtree(linked)
install()

# Removing a worktree also removes its registration; dangling links are repaired.
git('worktree', 'prune', '--expire=now')
git('worktree', 'add', '-q', str(linked), 'linked')
seed_old_worktree_links()

# A failed pull stops before the installer changes HOME.
git('branch', '--unset-upstream')
shutil.rmtree(home)
home.mkdir()
result = subprocess.run(['bash', str(primary / 'install')], text=True, capture_output=True)
assert result.returncode != 0, 'installer continued after pull failed'
assert 'There is no tracking information' in result.stderr, result.stderr
assert not (home / '.local/share/agent-config/operations').exists()

git('branch', '--set-upstream-to=origin/main', 'main')
git('worktree', 'remove', str(linked))
assert str(linked) not in git('worktree', 'list', '--porcelain')
install()
print('PASS: install worktree links')
PY
