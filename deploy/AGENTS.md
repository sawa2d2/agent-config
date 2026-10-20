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

## Communication
- Be direct and technically precise; avoid unnecessary explanations and verbosity.
- Explain consequential decisions and deviations from existing workflows.
- Summarize changes, verification results, and remaining limitations.
