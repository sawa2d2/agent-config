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
- Iterate through implementation, testing, diagnosis, and fixes while making meaningful progress, until relevant tests pass.
- Do not delegate executable checks to the user when the agent can run them.
- Stop and consult the user when permissions, credentials, environment restrictions, or external dependencies prevent further progress.
- Do not retry an unchanged failing operation without a concrete reason to expect a different result.
- Investigate reasonable alternatives without bypassing security controls or exceeding granted permissions.
- When blocked, report the evidence, attempted remedies, and the specific user action needed.
- Do not elevate privileges or weaken security controls solely to pass tests without authorization.
- Never claim a check passed unless it was actually executed.
- Distinguish verified results from assumptions and untested behavior.
- When the user requests test cases or verification steps, provide copy-paste-ready shell commands, preferably one command per test on a single line.
- Include an explicit command to switch to the relevant development branch when branch context matters.
- Prefer noninteractive CLI checks over manual UI steps; for Vim/Neovim, use headless commands where practical.
- State expected results briefly, and use multiline commands only when a one-liner would be unsafe or materially less clear.

## Language
- Write source code, code comments, identifiers, commit messages, and project documentation in English.
- Keep user-facing conversation in concise Japanese plain form (常体).
- Preserve existing external interfaces and required literal strings; do not translate user-provided text or localization content unless requested.

## Communication
- Respond in concise Japanese using plain form (常体), not polite です・ます form.
- Be direct and technically precise; avoid unnecessary explanations and verbosity.
- Explain consequential decisions and deviations from existing workflows.
- Summarize changes, verification results, and remaining limitations.
