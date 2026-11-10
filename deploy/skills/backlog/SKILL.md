---
name: backlog
description: Save, list, or remove future repository tasks shared by Bob, Claude Code and Codex across worktrees. Use when the user asks to defer work or consult the backlog; current-task resumption is a separate workflow.
---

# Shared Backlog

Use the installed `agent-backlog` CLI from any directory inside the repository.
`agent-backlog path` resolves the original working-tree root from Git common
directory/worktree metadata; never derive it from the current checkout path.

- `agent-backlog list` reads the shared `.backlog.md` (empty if absent).
- `agent-backlog add 'Task with enough context to resume later'` saves a future
  task; an identical task is not duplicated.
- `agent-backlog remove 'Exact task text'` removes one matching task after it is
  completed or the user asks to discard it. Do not remove tasks merely on read.

Only save work the user has asked to defer or authorized recording. Reading the
backlog does not authorize executing its tasks. Preserve existing prose and
entries; do not edit the file directly or run a read/overwrite sequence. The CLI
locks shared writes, preserves existing contents, and appends `/.backlog.md` to
the common `info/exclude`. It refuses writes when any registered worktree tracks
the file; report this and request an explicit migration decision, never untrack
it automatically. Do not change tracked `.gitignore`.

If a write is blocked, use the agent's normal tool approval workflow. If approval
is unavailable or denied, report the blocker and leave the task unsaved; never
write a worktree-local `.backlog.md`. The CLI does not grant permissions itself.

Keep `.agent-handoff.md` in the current worktree for its active task. Use
`handoff`/`takeover` for resumption; the shared backlog is independent of branch
and is not a substitute for that note. Invocation: `/backlog` in Claude Code,
`$backlog` in Bob Shell and Codex.
