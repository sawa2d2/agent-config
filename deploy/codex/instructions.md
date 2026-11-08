## Codex

- After branch delegation, remain the coordinator in the original checkout and follow the delegation procedure; workers use their assigned worktrees and Git authorization.
- Codex: only a user message exactly `approved` authorizes squash-merging the current development branch. Before finalization, read `$HOME/.local/share/agent-config/operations/codex-git.md`. Preserve approval-marker requirements; never bypass approval.
- Codex: after confirmed authorized deletion of the active session worktree, read `$HOME/.local/share/agent-config/operations/codex-deleted-worktree.md` if a hook reports `Hook failed: No such file or directory (os error 2)`; do not infer deletion from the hook error alone.
