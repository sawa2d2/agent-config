# Global Agent Instructions

## Scope
- Treat these instructions as global defaults.
- Respect repository-specific instructions, conventions, and workflows.
- Inspect the repository before assuming its build, test, or deployment procedures.

## Repository Safety
- Preserve unrelated changes and untracked files.
- Never discard user changes or perform destructive operations without explicit approval.
- Avoid modifying files outside the requested scope.

## Git Workflow
- Follow repository-specific branching rules; for new code changes, create a development branch before editing.
- The primary agent owns Git operations. Subagents must not create branches, commit, or push unless explicitly delegated by the primary agent.
- Never commit directly to the default branch or force-push without explicit approval.
- Do not merge into the default branch without explicit user approval.
- Preserve unrelated working-tree changes.

## Verification
- Use the repository's existing verification commands.
- Iterate through implementation, testing, diagnosis, and fixes while making meaningful progress, until relevant tests pass.
- Do not delegate executable checks to the user when the agent can run them.
- Stop and consult the user when permissions, credentials, environment restrictions, or external dependencies prevent further progress.
- Do not retry an unchanged failing operation without a concrete reason to expect a different result.
- Investigate reasonable alternatives without bypassing security controls or exceeding granted permissions.
- When blocked, report the evidence, attempted remedies, and the specific user action needed.
- Do not elevate privileges or weaken security controls solely to pass tests without authorization.
- Never claim a check passed unless it was actually executed.
- Distinguish verified results from assumptions and untested behavior.

## Handoff
- Keep work state in the repository (commits, plan files), not only in the conversation, so another agent or session can continue without the transcript.
- Before stopping with work unfinished (a turn or cost limit warning, a nearly full context, or the user ending the session), write a handoff note to the path printed by `git rev-parse --path-format=absolute --git-path agent-handoff.md`, replacing any earlier note. It lives in the Git directory, so it is never committed.
- Keep the note under about 60 lines: the goal, the current state (branch, last commit, what is done and verified), decisions with their reasons, open problems, and the next steps. Point to commits and files instead of copying their content.
- When continuing earlier work in a repository, read the handoff note first if it exists. Delete it once the work it describes is complete.

## Communication
- Be direct and technically precise; avoid unnecessary explanations and verbosity.
- Explain consequential decisions and deviations from existing workflows.
- Summarize changes, verification results, and remaining limitations.
