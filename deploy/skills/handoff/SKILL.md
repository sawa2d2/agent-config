---
name: handoff
description: Write a handoff note so a new session or another agent can continue the work without the transcript. Use when the user asks for a handoff or accepts a suggested one, and before stopping with work unfinished.
---

# Handoff

1. Commit and push finished work first, following the Git rules; the note
   records state, it does not replace commits.
2. Write `.agent-handoff.md` at the root of the working tree
   (`git rev-parse --show-toplevel`), replacing any earlier note. It stays
   inside the workspace, where every agent can read and write it (Codex cannot
   write the Git directory); never commit it or add it to the repository's
   `.gitignore`.
3. Keep it under about 60 lines, with these sections:
   - Goal: the objective and any constraints the user gave.
   - State: branch, last commit, what is done and how it was verified, and
     uncommitted changes.
   - Decisions: choices made and why, including approaches rejected.
   - Open problems: failures, blockers and unanswered questions.
   - Next steps: the concrete actions, in order.
   Point to commits and files instead of copying their content, and leave out
   what Git already records.
4. Tell the user in one or two lines that the note is ready and how to
   continue: a new session in this repository started with the `takeover`
   skill (`/takeover` in Claude Code, `$takeover` in Bob Shell and Codex); in
   Bob Shell, `bobtask handoff` also works, even without a note.
