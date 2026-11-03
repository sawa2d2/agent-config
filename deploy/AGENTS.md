# Global Agent Instructions

## Scope
- These are global defaults; repository-specific instructions, conventions, and workflows take precedence.

## Core Engineering Principles (Karpathy-inspired)
These principles govern all coding and maintenance work and take precedence over the process any skill, plugin, or workflow prescribes. When a skill (e.g. brainstorming, test-driven development, plan writing) would add process, artifacts, or code beyond what the task needs, scale the process to the size of the task.

### Think before coding
- Read the relevant code, interfaces, tests, and conventions first; verify behavior from the repository or a command instead of guessing.
- For ambiguous requirements with meaningful consequences, clarify the assumption; otherwise state it briefly and proceed.

### Simplicity first
- Make the smallest change that fully solves the problem: no speculative abstractions, broad refactoring, unnecessary dependencies, or premature generalization.
- Reuse existing patterns and utilities where they fit, without forcing reuse that hurts clarity.
- Do not add compatibility paths, fallbacks, or configuration options without a concrete need.

### Surgical changes
- Preserve existing behavior and files outside the requested scope.
- Handle errors at the correct boundary; do not silently swallow failures.
- Use descriptive names and straightforward control flow; comment *why* when necessary.
- Treat edge cases in proportion to their likelihood and impact.

### Goal-driven execution
- Define how to verify success before or while implementing, and inspect the final diff for unintended edits and unnecessary complexity.

## Repository Safety
- Preserve unrelated changes and untracked files; never discard user changes or run destructive operations without explicit approval.

## Git Workflow
- Follow repository-specific branching rules; for new code changes, create a development branch before editing.
- To start a new development branch inside tmux, run `agent-delegate <new-branch> "<task and context>"` (Claude Code), `bob-delegate <new-branch> "<task and context>"` (Bob Shell), or `codex-delegate <new-branch> "<task and context>"` (Codex) instead of creating the branch here: it creates the branch in a new worktree and starts the agent in one new tmux window per branch without moving focus, which does the work. Then tell the user the window and branch, and stop working on that task in this session.
- For routine, low-reasoning delegated work (merge waits, branch cleanup, mechanical edits), pass `-m sonnet` to `agent-delegate` or `-m gpt-6-luna` to `codex-delegate`; otherwise keep the default model.
- Always preserve the originating agent when delegating: Claude to Claude, Bob to Bob, and Codex to Codex. Never substitute another agent because its delegation command is available.
- The primary agent owns Git operations. Subagents must not create branches, commit, or push unless explicitly delegated by the primary agent.
- Never commit directly to the default branch or force-push without explicit approval.
- Do not merge into the default branch without explicit user approval.

## Verification
- Use the repository's existing verification commands, running only the relevant checks in a quiet mode that shows failures rather than full logs.
- Delegate each test run to a subagent: use Bob's `spawn_subagent`, a Claude Code subagent, or a Codex subagent via `spawn_agent`, as available in that agent's environment. The assigned subagent executes the checks directly rather than delegating them again.
- The parent defines the exact commands, working directory, and test scope, reviews the child's exit statuses and failure evidence, and handles fixes and Git operations. The child reports what actually ran and its results without modifying source files or Git state; reruns after fixes also go to a child.
- If the required child mechanism is unavailable or delegation fails, report the blocker and any unrun checks; never treat delegation failure or missing results as a passing test.
- Iterate through implementation, testing, diagnosis, and fixes while making meaningful progress, until relevant tests pass.
- Do not delegate executable checks to the user when you can run them, except slow or costly ones; hand those over as copy-paste commands with the expected results.
- Do not retry an unchanged failing operation without a concrete reason to expect a different result.
- Try reasonable alternatives, but never bypass security controls or exceed granted permissions; do not elevate privileges or weaken security controls solely to pass tests without authorization.
- When permissions, credentials, environment restrictions, or external dependencies block progress, stop and report the evidence, attempted remedies, and the specific user action needed.
- Never claim a check passed unless it was executed; distinguish verified results from assumptions and untested behavior.

## Efficiency
- For broad searches across many files, delegate to a read-only exploration subagent when available and keep only its conclusion in the main context.
- When the same multi-step command sequence recurs, propose a script for it so later runs cost one call.

## Handoff
- Every turn resends the whole conversation, so when a task is finished and the next request is unrelated, suggest starting a new session.
- Keep work state in the repository (commits, plan files), not only in the conversation, so another agent or session can continue without the transcript.
- Write a handoff note with the `handoff` skill when the user asks for or accepts one, and before stopping with work unfinished (nearly full context, the user ending the session, or a turn or cost limit warning: write the note first, then wrap up).
- When continuing earlier work, first read `.agent-handoff.md` at the working-tree root if it exists; delete it once that work is complete.

## Communication
- Be direct and technically precise; avoid unnecessary explanation and verbosity.
- Explain consequential decisions and deviations from existing workflows.
- Summarize changes, verification results, and remaining limitations.
