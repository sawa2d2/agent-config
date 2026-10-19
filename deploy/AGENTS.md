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
- Work directly in the repository; do not create Git worktrees.
- The primary agent owns Git operations. Subagents must not create branches, commit, or push unless explicitly delegated by the primary agent.
- Implement, verify, and fix failures autonomously. Commit and push completed changes to the development branch without asking for approval.
- Never commit directly to the default branch, force-push without explicit approval, create pull requests, or merge branches.
- Preserve unrelated working-tree changes.

### Finalization
- When the user says `approved`, output one concise commit message summarizing the entire development branch.
- Do not perform any Git operations in response to `approved`.
- Leave squash merging, branch deletion, and other finalization operations to the user.

## Verification
- Use the repository's existing verification commands.
- Never claim a check passed unless it was actually executed.
- Distinguish verified results from assumptions and untested behavior.

## Communication
- Be concise, direct, and technically precise.
- Explain consequential decisions and deviations from existing workflows.
- Summarize changes, verification results, and remaining limitations.
