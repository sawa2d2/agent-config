---
name: takeover
description: Continue earlier work from a saved session note. Use when the user asks to take over, resume or continue from that note, or to read it and continue the work it describes.
---

# Takeover

The note belongs to this worktree's active task. The original-root `.backlog.md`
is a separate shared list of future tasks (see `backlog`); it is not a fallback
handoff note and does not authorize starting other work.

1. Read `.agent-handoff.md` at the root of the working tree
   (`git rev-parse --show-toplevel`). If it is absent, say so and stop.
2. Check the recorded state against the repository: current branch, last
   commit, `git status` and uncommitted changes. Report any discrepancy before
   acting, and ask how to proceed if it changes what the next steps mean.
3. Summarize the goal and next steps for the user in a few lines.
4. Continue with the next steps, following the Git and verification rules;
   the note's open problems and decisions still apply.
5. Delete the note once the work it describes is complete; while work
   remains, keep it current with the handoff skill instead.
