#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export HOME="$tmp/home"
unset CODEX_HOME
mkdir -p "$HOME"

python3 - "$root/bin/agent-backlog" "$tmp" <<'PY'
import concurrent.futures
import os
from pathlib import Path
import subprocess
import sys

cli = sys.argv[1]
base = Path(sys.argv[2])

def run(*args, cwd, ok=True):
    result = subprocess.run(args, cwd=cwd, capture_output=True)
    assert (result.returncode == 0) == ok, (args, result.returncode, result.stderr)
    return result.stdout

def git(cwd, *args):
    return run('git', *args, cwd=cwd)

def backlog(cwd, *args, ok=True):
    return run(cli, *args, cwd=cwd, ok=ok)

def fixture(name, separate=False):
    primary = base / name
    primary.mkdir()
    args = ['init', '-q', '-b', 'main']
    if separate:
        args += ['--separate-git-dir', str(base / (name + ' metadata'))]
    git(primary, *args)
    git(primary, '-c', 'user.name=Test', '-c', 'user.email=test@example.com', 'commit', '-qm', 'initial', '--allow-empty')
    linked = base / (name + ' linked')
    git(primary, 'worktree', 'add', '-qb', 'feature', str(linked))
    return primary, linked

for separate in (False, True):
    primary, linked = fixture('original with spaces ' + str(separate), separate)
    if separate:
        # Git reports the metadata directory as the primary worktree for this
        # layout. Refuse it rather than storing a backlog in the Git directory.
        for cwd in (primary, linked):
            backlog(cwd, 'add', 'Unknown original root', ok=False)
        assert not (primary / '.backlog.md').exists()
        assert not (linked / '.backlog.md').exists()
        assert not (base / (primary.name + ' metadata') / '.backlog.md').exists()
        continue
    nested = linked / 'nested directory'
    nested.mkdir()
    path = primary / '.backlog.md'
    common = Path(os.fsdecode(git(primary, 'rev-parse', '--path-format=absolute', '--git-common-dir')).strip())
    for cwd in (primary, linked, nested):
        assert backlog(cwd, 'path').decode().strip() == str(path)
        assert backlog(cwd, 'list') == b''
    assert not path.exists() and not (common / 'agent-backlog.lock').exists()
    original = b'# Existing future tasks\r\n\r\nLegacy text without newline'
    path.write_bytes(original)
    exclude = common / 'info/exclude'
    exclusions = b'# custom exclusions\n/private\n/.backlog.md\n!/.backlog.md'
    exclude.write_bytes(exclusions)
    (primary / '.agent-handoff.md').write_text('primary task')
    (linked / '.agent-handoff.md').write_text('linked task')
    backlog(nested, 'add', 'First task')
    assert path.read_bytes() == original + b'\n- [ ] First task\n'
    assert exclude.read_bytes() == exclusions + b'\n/.backlog.md\n'
    assert git(primary, 'check-ignore', '.backlog.md').strip() == b'.backlog.md'
    assert git(linked, 'check-ignore', '.backlog.md').strip() == b'.backlog.md'
    assert not (linked / '.backlog.md').exists()
    assert not (primary / '.gitignore').exists()
    assert not git(primary, 'ls-files', '--', '.backlog.md')
    assert backlog(primary, 'list') == backlog(linked, 'list')
    assert (primary / '.agent-handoff.md').read_text() == 'primary task'
    assert (linked / '.agent-handoff.md').read_text() == 'linked task'
    saved = path.read_bytes()
    backlog(linked, 'add', 'First task')
    assert path.read_bytes() == saved
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        futures = [pool.submit(backlog, primary if i % 2 else linked, 'add', f'Concurrent {i}') for i in range(40)]
        for future in futures:
            future.result()
    lines = path.read_bytes().splitlines()
    for i in range(40):
        assert lines.count(f'- [ ] Concurrent {i}'.encode()) == 1
    assert path.read_bytes().startswith(saved)
    assert exclude.read_bytes() == exclusions + b'\n/.backlog.md\n'
    backlog(linked, 'remove', 'First task')
    assert b'- [ ] First task' not in path.read_bytes()
    saved = path.read_bytes()
    backlog(primary, 'remove', 'Missing', ok=False)
    backlog(primary, 'add', 'two\nlines', ok=False)
    assert path.read_bytes() == saved
    # Branch changes do not change shared storage.
    git(linked, 'switch', '-qc', 'another')
    assert backlog(linked, 'list') == saved
    # A tracked file in either worktree blocks mutations without untracking.
    git(primary, 'add', '-f', '.backlog.md')
    backlog(linked, 'add', 'Must fail', ok=False)
    assert path.read_bytes() == saved
    assert git(primary, 'ls-files', '--', '.backlog.md')
    git(primary, 'reset', '-q', '--', '.backlog.md')
    (linked / '.backlog.md').write_text('tracked linked content')
    git(linked, 'add', '-f', '.backlog.md')
    backlog(primary, 'remove', 'Concurrent 0', ok=False)
    assert path.read_bytes() == saved
    assert git(linked, 'ls-files', '--', '.backlog.md')
    git(linked, 'reset', '-q', '--', '.backlog.md')
    (linked / '.backlog.md').unlink()
    # Ordinary filesystem denial is not a live Codex sandbox approval test.
    assert os.geteuid() != 0, 'permission fixture requires an unprivileged user'
    primary.chmod(0o555)
    try:
        backlog(linked, 'add', 'Denied root write', ok=False)
        assert path.read_bytes() == saved and not (linked / '.backlog.md').exists()
    finally:
        primary.chmod(0o755)
    (common / 'agent-backlog.lock').chmod(0o400)
    try:
        backlog(linked, 'add', 'Denied common write', ok=False)
        assert path.read_bytes() == saved and not (linked / '.backlog.md').exists()
    finally:
        (common / 'agent-backlog.lock').chmod(0o600)

# First-time creation and exclusion are serialized too.
primary, linked = fixture('fresh concurrent')
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
    futures = [pool.submit(backlog, primary if i % 2 else linked, 'add', f'New {i}') for i in range(20)]
    for future in futures:
        future.result()
assert len(backlog(primary, 'list').splitlines()) == 20
assert (primary / '.git/info/exclude').read_bytes().splitlines().count(b'/.backlog.md') == 1
assert not (linked / '.backlog.md').exists()

bare = base / 'bare.git'
git(base, 'init', '--bare', '-q', str(bare))
backlog(bare, 'add', 'No primary', ok=False)
backlog(base, 'path', ok=False)
PY

# Run the real installer/distribution in an isolated package and HOME. Stub
# only unrelated settings/network installers; do not touch installed user data.
python3 "$root/scripts/render-codex-instructions" --check
package="$tmp/package with spaces"
mkdir -p "$package/scripts" "$package/bin" "$package/lib"
cp "$root/install" "$package/install"
cp -R "$root/deploy" "$package/deploy"
cp "$root/scripts/install-skill" "$package/scripts/"
cp "$root/scripts/render-codex-instructions" "$package/scripts/"
cp "$root/lib/skill_metadata.py" "$package/lib/"
cp "$root/bin/agent-backlog" "$package/bin/"
# A stale rendered file fails the check without rewriting it; regeneration
# updates only the repository artifact, with no agent startup hook involved.
printf '\nFixture instruction.\n' >> "$package/deploy/AGENTS.md"
python3 "$package/scripts/render-codex-instructions" --check > /dev/null 2>&1 && {
  echo 'stale Codex instructions accepted' >&2; exit 1;
}
cmp "$root/deploy/codex/AGENTS.md" "$package/deploy/codex/AGENTS.md"
python3 "$package/scripts/render-codex-instructions"
python3 "$package/scripts/render-codex-instructions" --check
grep -q '^Fixture instruction\.$' "$package/deploy/codex/AGENTS.md"
cp "$root/deploy/AGENTS.md" "$package/deploy/AGENTS.md"
cp "$root/deploy/codex/AGENTS.md" "$package/deploy/codex/AGENTS.md"
for script in install-rtk install-claude-settings install-bob-theme install-codex-theme \
  install-codex-compaction install-codex-subagent-model install-bob-settings \
  install-agent-hooks install-tools install-nix-tools install-claude-plugins; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$package/scripts/$script"
done
# An existing managed shared Codex link migrates to the Codex-specific file.
mkdir -p "$HOME/.codex"
ln -s "$package/deploy/AGENTS.md" "$HOME/.codex/AGENTS.md"
bash "$package/install" > /dev/null
bash "$package/install" > /dev/null
for agent in .bob .claude .codex; do
  cmp "$root/deploy/skills/backlog/SKILL.md" "$HOME/$agent/skills/backlog/SKILL.md"
  [[ -f "$HOME/$agent/skills/backlog/.agent-config-managed" ]]
done
cmp "$root/deploy/AGENTS.md" "$HOME/.bob/rules/agent-config.md"
cmp "$root/deploy/AGENTS.md" "$HOME/.claude/CLAUDE.md"
cmp "$root/deploy/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
[[ $(readlink "$HOME/.codex/AGENTS.md") == "$package/deploy/codex/AGENTS.md" ]]
# Every mandatory reference resolves through the installed HOME path from
# arbitrary repositories and linked worktrees, independently of agent/CWD.
python3 - "$HOME" "$root" "$tmp/original with spaces False" "$tmp/original with spaces False linked" <<'PY'
import os, pathlib, re, sys
home, root, *repositories = map(pathlib.Path, sys.argv[1:])
for repository in repositories:
    os.chdir(repository)
    for global_path in ('.bob/rules/agent-config.md', '.claude/CLAUDE.md', '.codex/AGENTS.md'):
        text = (home / global_path).read_text()
        references = re.findall(r'`\$HOME/([^`]+\.md)`', text)
        codex = global_path.startswith('.codex/')
        assert len(references) == (3 if codex else 1), references
        shared = (root / 'deploy/AGENTS.md').read_text()
        if codex:
            assert text.startswith(shared.rstrip() + '\n\n')
            assert 'only a user message exactly `approved`' in text
            assert 'codex-deleted-worktree.md' in text
        else:
            assert text == shared
            assert '## Codex' not in text
            assert 'codex-git.md' not in text
            assert 'codex-deleted-worktree.md' not in text
        for reference in references:
            installed = home / reference
            assert installed.read_bytes() == (root / 'deploy/operations' / installed.name).read_bytes()
    assert not (repository / '.local/share/agent-config/operations').exists()
PY
# Unknown Codex instruction links remain untouched, including broken links.
codex_global="$HOME/.codex/AGENTS.md"
rm "$codex_global"
ln -s "$tmp/foreign-codex" "$codex_global"
bash "$package/install" > /dev/null 2>&1 && { echo 'foreign Codex global link overwritten' >&2; exit 1; }
[[ $(readlink "$codex_global") == "$tmp/foreign-codex" ]]
rm "$codex_global"
ln -s "$package/deploy/codex/AGENTS.md" "$codex_global"
# Refuse to take over an existing reference installation from another source.
references="$HOME/.local/share/agent-config/operations"
rm "$references"
ln -s "$tmp/foreign" "$references"
bash "$package/install" > /dev/null 2>&1 && { echo 'foreign reference symlink overwritten' >&2; exit 1; }
[[ $(readlink "$references") == "$tmp/foreign" ]]
rm "$references"
mkdir "$references"
bash "$package/install" > /dev/null 2>&1 && { echo 'foreign reference directory overwritten' >&2; exit 1; }
[[ -d "$references" && ! -L "$references" ]]
[[ -x "$HOME/.local/bin/agent-backlog" ]]
(cd "$tmp/original with spaces False linked" && PATH="$HOME/.local/bin:$PATH" agent-backlog add 'Installed CLI task')
[[ $(tail -1 "$tmp/original with spaces False/.backlog.md") == '- [ ] Installed CLI task' ]]
echo 'PASS: shared backlog CLI and Bob/Claude/Codex distribution (not live agent end-to-end)'
