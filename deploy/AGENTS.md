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

## Verification
- Use the repository's existing verification commands.
- Iterate through implementation, testing, diagnosis, and fixes while making meaningful progress, until relevant tests pass.
- Run only the checks relevant to the change, in a quiet mode that shows failures rather than full logs.
- Do not delegate executable checks to the user when the agent can run them, except slow or costly ones; hand those over as copy-paste commands with the expected results.
- Stop and consult the user when permissions, credentials, environment restrictions, or external dependencies prevent further progress.
- Do not retry an unchanged failing operation without a concrete reason to expect a different result.
- Investigate reasonable alternatives without bypassing security controls or exceeding granted permissions.
- When blocked, report the evidence, attempted remedies, and the specific user action needed.
- Do not elevate privileges or weaken security controls solely to pass tests without authorization.
- Never claim a check passed unless it was actually executed.
- Distinguish verified results from assumptions and untested behavior.

## Engineering
These apply to coding and maintenance tasks.
- Read the relevant code, interfaces, tests, and conventions before making changes; do not guess about behavior that can be verified from the repository or a command.
- For ambiguous requirements with meaningful consequences, clarify the assumption; otherwise state it briefly and proceed.
- Prefer the smallest change that fully solves the requested problem. Avoid speculative abstractions, broad refactoring, unnecessary dependencies, and premature generalization.
- Reuse existing patterns and utilities where appropriate, without forcing reuse when it makes the code harder to understand.
- When the same multi-step command sequence recurs, propose a script for it, so later runs cost one call instead of rebuilding the steps.
- Do not add compatibility paths, fallbacks, or configuration options without a concrete need.
- Handle errors at the correct boundary; do not silently swallow failures.
- Preserve existing behavior outside the requested scope.
- Use descriptive names, straightforward control flow, and comments explaining *why* when necessary.
- Treat edge cases in proportion to their likelihood and impact.
- Define how to verify success before or while implementing the change, and inspect the final diff for unintended edits and unnecessary complexity.

## Handoff
- Keep work state in the repository (commits, plan files), not only in the conversation, so another agent or session can continue without the transcript.
- Write a handoff note with the `handoff` skill when the user asks for one or accepts a suggested handoff, and before stopping with work unfinished (a nearly full context, or the user ending the session). A warning that you are approaching a turn or cost limit means the task is about to stop: write the note first, then wrap up.
- When continuing earlier work in a repository, read `.agent-handoff.md` at the root of the working tree first if it exists. Delete it once the work it describes is complete.

## Communication
- Be direct and technically precise; avoid unnecessary explanations and verbosity.
- Explain consequential decisions and deviations from existing workflows.
- Summarize changes, verification results, and remaining limitations.
