---
name: autonomous-development
description: Use when the user hands over a development objective to be carried through autonomously across several work units, branches or sessions ("do this end to end", "keep going until done"), rather than one small requested change.
---

# Autonomous Development

Carry an objective to completion with as few interruptions as possible. The
global instructions (repository safety, Git workflow, verification) and the
user's personal workflow still apply; this skill adds only the loop.

## 1. Investigate

- Read the repository, Git status, instructions, tests and the runtime state
  that the objective touches before planning.
- Record verified facts, assumptions and open questions separately. Do not
  trust earlier conclusions, including a previous agent's, without checking.

## 2. Plan

- Split the objective into work units that can each be verified and merged on
  their own. For each, note scope, acceptance check, and whether it needs the
  user (approval, credentials, or a check only the user can run).
- Show the plan briefly, then start immediately. Wait only when the plan
  itself contains a decision only the user can make.

## 3. Branches: independent first, stacked when needed

- A unit that does not depend on unmerged work branches from the default
  branch. Prefer these while earlier units wait for the user.
- A unit that needs an unmerged unit branches from that unit's branch. Record
  the parent branch and the commit it branched from in the progress file.
- Keep stacked branches local until their parent is merged, so that rebasing
  them never needs a force-push. Push a stacked branch earlier only when the
  user must check it; its later rebase then needs force-push approval.
- After the parent is squash-merged, rebase the child:
  `git rebase --onto <default> <recorded-commit> <child>`. Plain
  `git merge <default>` conflicts with the squashed copy of the parent.
  Stop and report if the rebase conflicts.
- Ask for merges in dependency order (parent before child) and say which
  branch each request is for. More than three unmerged units means the
  queue is too long: stop starting new units and report what waits.

## 4. Execute

- Implement, test, fix and commit each unit without asking between steps.
- Re-plan when new facts contradict the plan, and note the change.
- Move to the next unit as soon as one is committed and pushed; do not wait
  for its merge unless the next unit truly needs it and no independent unit
  is left.

## 5. When to stop and ask

Ask only when an action:

- may destroy or irreversibly change data, infrastructure or another
  machine's state (for example the user's local databases or settings) —
  offer the backup and restore commands with the request;
- may interrupt services or network access;
- needs credentials, sign-in, or a decision only the user can make;
- is a material design tradeoff the requirements do not settle.

Also stop when the same failure repeats after two different approaches, or
when no unit can progress without the user. Report the evidence and the exact
user action needed, then keep working on whatever remains unblocked.

## 6. Checks the agent cannot run

- When a check needs an environment the agent cannot reach (another machine,
  real credentials, a GUI), collect such checks per branch and hand them over
  in one message: the branch-switch command, one command per check, and the
  expected result of each, numbered so the user can reply "1 ok, 2 <output>".
- Continue other units while waiting.

## 7. Progress file

- Keep the state in `$(git rev-parse --git-path agent-progress.md)`: inside
  the Git directory, so it is never committed, and outside chat history, so a
  new session or another agent can resume from it.
- Record the objective, the plan with each unit's status and branch, stacked
  parents and recorded commits, decisions, blockers and checks waiting for
  the user. Update it after every unit and before the session may end or be
  compacted.
- When resuming, read it first and verify it against Git before continuing.

## 8. Reporting

Report each unit's state with one of these words, never stronger than the
evidence: implemented, tested (where and how), verified by the user, merged.
Keep reports short: what changed, what was checked, what waits for whom.
