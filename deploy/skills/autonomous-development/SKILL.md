---
name: autonomous-development
description: Carry a development objective through autonomously across several work units, branches or sessions. Use only when the user invokes this skill by name.
disable-model-invocation: true
---

# Autonomous Development

Carry the objective to completion with as few interruptions as possible. The
global and personal instructions still apply and take precedence over this
skill and the tools below: when a tool's steps conflict with them (for example
worktrees, pull requests or merge choices), skip those steps.

## Choose the workflow

| Objective | Use |
| --- | --- |
| Unclear requirements or design | superpowers `brainstorming` first (asks questions until the design is settled); `grill-me` to stress-test a proposal |
| Settled design, several steps | superpowers `writing-plans`, then `executing-plans` (or `subagent-driven-development` where subagents exist) |
| Large feature whose specification should be kept as documents | Spec Kit: `specify init` in the repository, then `/speckit.specify`, `/speckit.clarify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.implement` |
| Mechanically checkable end state (all tests pass, lint clean) | `ralph-loop` (Claude Code only) with an explicit completion condition and an iteration limit |
| Before claiming any unit is done | superpowers `verification-before-completion` |

Ask about unclear requirements before planning. When a tool is not installed
in this agent, carry out its idea inline: clarify, plan in verifiable units,
execute, verify.

## Branches: independent first, stacked when needed

- A unit that does not depend on unmerged work branches from the default
  branch. Prefer these while earlier units wait for the user's merge approval.
- A unit that needs an unmerged unit branches from that unit's branch. Record
  the parent branch and the commit it branched from in the progress file.
- Keep stacked branches local until their parent is merged, so that rebasing
  them never needs a force-push. Push one earlier only when the user must
  check it; its later rebase then needs force-push approval.
- After the parent is squash-merged, rebase the child with
  `git rebase --onto <default> <recorded-commit> <child>`; `git merge
  <default>` conflicts with the squashed copy. Stop and report if the rebase
  conflicts.
- Ask for merges in dependency order and name the branch each request is for.
  With more than three units waiting, stop starting new ones and report the
  queue.

## Progress file

- Keep the state in `$(git rev-parse --git-path agent-progress.md)`: inside
  the Git directory, so it is never committed, and outside chat history, so a
  new session can resume.
- Record the objective, each unit's status and branch, stacked parents and
  recorded commits, decisions, blockers, and checks waiting for the user.
  Update it after every unit and before the session may end or be compacted.
- When resuming, read it first and verify it against Git.

## Stopping

- Stop when the same failure repeats after two different approaches, or when
  no unit can progress without the user. Report the evidence and the exact
  user action needed, and keep working on whatever remains unblocked.

## Checks only the user can run

- Collect checks that need another machine, real credentials or a GUI per
  branch, and hand them over in one numbered message (branch-switch command,
  one command per check, expected result) so the user can reply
  "1 ok, 2 <output>". Continue other units while waiting.

## Reporting

- Report each unit's state with one of: implemented, tested (where and how),
  verified by the user, merged. Never use a stronger word than the evidence
  supports.
