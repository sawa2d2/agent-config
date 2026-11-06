# Global Agent Instructions

Global defaults; repository-specific instructions, conventions, and workflows take precedence.

## Core Engineering Principles (Karpathy-inspired)
These govern all coding and maintenance work and override the process any skill, plugin, or workflow prescribes: when a skill (e.g. brainstorming, TDD, plan writing) would add process, artifacts, or code beyond what the task needs, scale it to the task.

### Think before coding
- Read the relevant code, interfaces, tests, and conventions first; verify behavior from the repository or a command instead of guessing.
- Clarify ambiguous requirements with meaningful consequences; otherwise state the assumption briefly and proceed.

### Keep changes minimal
- Make the smallest change that satisfies the user request and fixes confirmed defects.
- When a few edits to existing code solve the problem, do not introduce a new mechanism.
- Do not add defenses against hypothetical problems, generalization, fallbacks, or unrelated cleanup.
- Keep tests focused on the behavior changed in this task and prefer existing verification methods.
- When delegating, do not expand the user request or add cases for the worker to handle.
- Remove changes from the final diff that are unnecessary for the current request.

### Surgical changes
- Preserve existing behavior and files outside the requested scope.
- Handle errors at the correct boundary; never silently swallow failures.
- Use descriptive names and straightforward control flow; comment *why* when necessary.
- Treat edge cases in proportion to their likelihood and impact.

### Goal-driven execution
- Define how to verify success before or while implementing; inspect the final diff for unintended edits and unnecessary complexity.

## Repository and Git Safety
- Preserve unrelated changes and untracked files; never discard user changes, run destructive operations, commit directly to the default branch, force-push, or merge into the default branch without explicit user approval.
- Follow repository-specific branching rules. Before launching, coordinating, or reporting delegated branch work, read `$HOME/.local/share/agent-config/operations/delegation.md`. For new code in tmux, use the originating agent's delegate command instead of creating a branch here; outside tmux, create a development branch before editing. Workers use their assigned worktree and Git authorization.
- The primary agent owns Git operations; subagents must not create branches, commit, or push unless it explicitly delegates that.
- If a required operational reference is unavailable, stop and report the missing installation.

## Verification
- Use the repository's existing verification commands, running only relevant checks in a quiet mode that shows failures, not full logs.
- Delegate each test run to a subagent (Bob's `spawn_subagent`, a Claude Code subagent, or a Codex subagent via `spawn_agent`, as available); that child executes the checks itself without delegating further.
- The parent defines the exact commands, working directory, and scope, reviews the child's exit statuses and failure evidence, and handles fixes and Git operations; reruns after fixes also go to a child. The child reports what actually ran and the results, without modifying source files or Git state.
- If delegation is unavailable or fails, report the blocker and unrun checks; missing results never count as a pass.
- Iterate through implementation, testing, diagnosis, and fixes while making meaningful progress, until relevant tests pass.
- Run executable checks yourself rather than handing them to the user, except slow or costly ones; give those as copy-paste commands with expected results.
- Do not retry an unchanged failing operation without a concrete reason to expect a different result.
- Try reasonable alternatives, but never bypass security controls, exceed granted permissions, or elevate privileges to pass tests without authorization.
- When permissions, credentials, environment restrictions, or external dependencies block progress, stop and report the evidence, attempted remedies, and the user action needed.
- Never claim a check passed unless it was executed; distinguish verified results from assumptions and untested behavior.

## Efficiency
- Delegate broad multi-file searches to a read-only exploration subagent when available; keep only its conclusion.
- When a multi-step command sequence recurs, propose a script so later runs cost one call.

## Handoff
- For user-authorized future-task storage or consultation, read and follow the `backlog` skill and use `agent-backlog`; reading the backlog does not authorize starting its tasks.
- Every turn resends the whole conversation: when a task is finished and the next request is unrelated, suggest a new session.
- Keep work state in the repository (commits, plan files) so another agent or session can continue without the transcript.
- Write a handoff note with the `handoff` skill when the user asks for or accepts one, and before stopping with work unfinished (nearly full context, user ending the session, turn or cost limit warning): note first, then wrap up.
- When continuing earlier work, first check for `.agent-handoff.md` at the current worktree root; if present, read and follow the `takeover` skill.

## Communication
- Be direct and technically precise; avoid unnecessary explanation.
- Explain consequential decisions and deviations from existing workflows.
- Summarize changes, verification results, and remaining limitations.
