# Global Agent Instructions

Global defaults; repository-specific instructions, conventions, and workflows take precedence.

## Core Engineering Principles (Karpathy-inspired)
These govern all coding and maintenance work and override the process any skill, plugin, or workflow prescribes: when a skill (e.g. brainstorming, TDD, plan writing) would add process, artifacts, or code beyond what the task needs, scale it to the task.

### Think before coding
- Read the relevant code, interfaces, tests, and conventions first; verify behavior from the repository or a command instead of guessing.
- Clarify ambiguous requirements with meaningful consequences; otherwise state the assumption briefly and proceed.

### Simplicity first
- Make the smallest change that fully solves the problem: no speculative abstractions, broad refactoring, unnecessary dependencies, or premature generalization.
- Reuse existing patterns and utilities where they fit, but not at the cost of clarity.
- Add compatibility paths, fallbacks, or configuration options only for a concrete need.

### Surgical changes
- Preserve existing behavior and files outside the requested scope.
- Handle errors at the correct boundary; never silently swallow failures.
- Use descriptive names and straightforward control flow; comment *why* when necessary.
- Treat edge cases in proportion to their likelihood and impact.

### Goal-driven execution
- Define how to verify success before or while implementing; inspect the final diff for unintended edits and unnecessary complexity.

## Repository and Git Safety
- Preserve unrelated changes and untracked files; never discard user changes, run destructive operations, commit directly to the default branch, force-push, or merge into the default branch without explicit user approval.
- Follow repository-specific branching rules. For new code changes, when `$TMUX` is set, never create the branch here (no `git checkout -b`, `git switch -c`, or `git worktree add`); instead run your delegate command, `agent-delegate` (Claude Code), `bob-delegate` (Bob Shell), or `codex-delegate` (Codex), as `<cmd> <new-branch> "<task and context>"`: it creates the branch in a new worktree and starts the agent, which does the work, in a new tmux window without moving focus. Tell the user the window and branch. Claude and Bob then stop working on that task; Codex follows the coordination rule below. Only outside tmux, create a development branch here before editing.
- Codex: the originating agent remains the coordinator in its original checkout, including on the default branch. For user-requested orchestration, use `codex-delegate --list` and `--status <id>` on demand, review explicit worker summaries/checks/commits, and verify Git results before accepting completion. Management does not authorize editing worker files from the parent or committing to the default branch. Workers implement in their assigned worktrees and may commit/push their branch only when the parent explicitly delegates those Git operations (the launch prompt does so unless the task overrides it). Do not manage other agent types, inject follow-up input, or merge automatically. Shared `.codex-tasks/` writes may require supported `require_escalated` approval after a sandbox denial; never weaken sandbox/auto-approval controls or use a local fallback.
- Codex: only a user message exactly `approved` authorizes squash-merging the current development branch. That same approval covers resolving conflicts with main/the default branch on the development branch, preserving both intended changes, delegating relevant verification, committing the resolution, and rerunning `gfinish -y -m "<concise branch summary>"` once the working tree is clean and verified. Inspect the actual gfinish implementation and approval-marker lifecycle first. Where supported, detect conflicts before gfinish consumes approval (e.g. `git merge-tree --write-tree <default-ref> HEAD`); merge the current default ref into the development branch to recover, never resolve in the default checkout or rebase a published branch. Let gfinish handle remote synchronization; unpushed commits alone must not block execution or require a separate push. Ask first if the repository/branch or conflict semantics are ambiguous. Stop and report unrelated failures, permission/credential errors, failed verification, or lack of progress; never force-push. Retry only a diagnosed default-branch conflict after recovery makes progress, with clean verified state and valid approval. Never fabricate, refresh, restore or bypass an approval marker: the current external gfinish consumes it before conflict detection and requires a fresh `approved` if consumed/expired; changing that externally managed implementation or installed user settings requires separate approval.
- Delegation: input sent is not verified startup. Require the delegate's bounded startup check to succeed; Codex waits for the worker's concrete starting report. On timeout, delivery failure or inaccessible tmux, report the uncertainty and inspect retained task/pane/worktree state before retrying. Never blindly resend or launch a duplicate. An access denial does not prove a pane is missing. Workers must report their actual first action, replacing example summary/check text, and request supported escalation if the authorized report write is denied.
- Always delegate to the originating agent (Claude to Claude, Bob to Bob, Codex to Codex), even if another agent's command is available.
- For routine, low-reasoning Claude work (merge waits, branch cleanup, mechanical edits), pass `-m sonnet` to `agent-delegate`; otherwise keep the default model.
- The Codex parent must explicitly select `-m gpt-6.1-sol` for ordinary tasks or `-m gpt-6-astra` for heavy tasks when running `codex-delegate`. Judge complexity, uncertainty, and impact rather than changed line count.
- The primary agent owns Git operations; subagents must not create branches, commit, or push unless it explicitly delegates that.
- Codex: the workspace-write sandbox keeps `.git`, a linked worktree's shared Git metadata and the network read-only. Request `require_escalated` for an already authorized Git mutation (add, commit, fetch, push, branch or worktree changes) once the sandbox blocks it, and for gfinish from the start to avoid a preventable sandbox failure. Escalation only passes automatic review: it never replaces the user's authorization, the exact `approved` merge requirement or a valid approval marker; never weaken sandbox settings or bypass review, and stop and report if review denies it.
- Codex: only after operation results establish successful authorized deletion of the active session worktree (`gfinish` or explicit branch/worktree discard), treat subsequent `Hook failed: No such file or directory (os error 2)` as the known missing-session-cwd hook launch failure. This message alone requires no extra checks: do not investigate or retry deletion/merge, recreate the directory, or change/disable hooks because of it. Handle actual failed Git commands, unrelated hook errors, errors before deletion, and remaining explicitly authorized cleanup normally; run required remaining commands with an existing original-root workdir.

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
- For user-authorized future tasks, use the `backlog` skill and `agent-backlog` CLI. `.backlog.md` is untracked at the original repository root, shared across branches and linked worktrees through Git common metadata; never use a worktree-local fallback. The CLI serializes writes and adds the common `info/exclude` entry without changing tracked `.gitignore`. For sandbox-blocked writes, Codex must request `require_escalated` for the authorized command; Bob and Claude Code use their normal approval workflows. Never weaken permissions or silently untrack an existing file.
- Keep `.agent-handoff.md` local to the current worktree for active-task resumption; reading the shared backlog does not authorize starting its tasks.
- Every turn resends the whole conversation: when a task is finished and the next request is unrelated, suggest a new session.
- Keep work state in the repository (commits, plan files) so another agent or session can continue without the transcript.
- Write a handoff note with the `handoff` skill when the user asks for or accepts one, and before stopping with work unfinished (nearly full context, user ending the session, turn or cost limit warning): note first, then wrap up.
- When continuing earlier work, first read `.agent-handoff.md` at the working-tree root if present; delete it once that work is complete.

## Communication
- Be direct and technically precise; avoid unnecessary explanation.
- Explain consequential decisions and deviations from existing workflows.
- Summarize changes, verification results, and remaining limitations.
