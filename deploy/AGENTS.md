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
- Follow the repository's branching strategy and branch protection rules.
- Work on a development or feature branch for code changes.
- Commits and pushes to development and feature branches are permitted without additional approval.
- Never bypass branch protection or force-push without explicit approval.
- Do not merge into the default branch without explicit approval.
- Preserve unrelated working-tree changes.

## Verification
- Use the repository's existing verification commands.
- Never claim a check passed unless it was actually executed.
- Distinguish verified results from assumptions and untested behavior.

## Communication
- Be concise, direct, and technically precise.
- Explain consequential decisions and deviations from existing workflows.
- Summarize changes, verification results, and remaining limitations.
