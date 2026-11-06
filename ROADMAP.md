# Roadmap

This roadmap describes documentation and tooling directions for agent-config.
It sets no deadlines; scope and sequencing can change as the tools evolve.

## Token efficiency and savings

Improve how we measure and reduce token use across supported agents, including
context growth, repeated prompt content, cache use, and tool output. Build on
`claude-stats`, `codex-stats`, and `bob-stats`, the RTK coverage notes, and the
existing compaction and handoff guidance.

Next steps:

- Establish comparable baselines from the existing usage reports, with clear
  notes on what each agent's data does and does not measure.
- Identify high-impact sources of repeated or unnecessary context and output;
  prioritize focused changes to prompts, hooks, or command output.
- Re-measure representative sessions and record the method and limitations for
  each claimed saving.

Success criteria: reports make meaningful before-and-after comparisons
possible, and each claimed reduction is supported by repeatable measurements
without hiding changes in task quality or work completed.

## Agent loops and loop engineering

Make bounded, repeatable agent runs easier to start, inspect, and improve.
Build on `bin/codex-ralph`, the experimental Bob Ralph installer, and the
autonomous-development skill.

Next steps:

- Document when to use a loop and how to define its task, check, iteration
  limit, and stop conditions.
- Compare the existing loop approaches and identify gaps in progress reporting,
  failure handling, and safe recovery.
- Evaluate representative tasks for completion rate, unnecessary iterations,
  and token use before expanding loop support.

Success criteria: a loop stops predictably at a clear completion condition or
limit, exposes enough information to diagnose a failed run, and demonstrates
reliable results on a defined set of tasks.

## Multi-agent orchestration

Extend delegation from launching one agent in a worktree and tmux window toward
an agent coordinating multiple agents and their results. Build on the existing
`agent-delegate`, `bob-delegate`, and `codex-delegate` launchers and the shared
rules for delegation.

Next steps:

- Define orchestration use cases and boundaries, including task assignment,
  independent work, result review, and conflict handling.
- Assess what current agent CLIs support for nested delegation and lifecycle
  control; keep any first step within those capabilities.
- Specify controls for concurrency, shared budgets, failure recovery, and the
  primary agent's responsibility for reviewing changes and Git operations.
- Prototype a narrowly scoped workflow and evaluate it against equivalent
  single-agent work.

Success criteria: delegated work has clear ownership and completion status,
failures and conflicting changes are visible to the coordinating agent, and
the workflow improves throughput or outcome quality without losing review and
budget control.
