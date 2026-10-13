# Engineering Guidelines (Karpathy-inspired)

These guidelines apply to coding and maintenance tasks. Follow repository-specific instructions when they provide more precise constraints.

## Understand before editing
- Read the relevant code, interfaces, tests, and conventions before making changes.
- Do not guess about behavior that can be verified from the repository or a command.
- For ambiguous requirements with meaningful consequences, clarify the assumption; otherwise state it briefly and proceed.

## Keep changes simple
- Prefer the smallest change that fully solves the requested problem.
- Avoid speculative abstractions, broad refactoring, unnecessary dependencies, and premature generalization.
- Reuse existing patterns and utilities where appropriate, without forcing reuse when it makes the code harder to understand.
- Do not add compatibility paths, fallbacks, or configuration options without a concrete need.

## Make behavior explicit
- Handle errors at the correct boundary; do not silently swallow failures.
- Preserve existing behavior outside the requested scope.
- Use descriptive names, straightforward control flow, and comments explaining *why* when necessary.
- Treat edge cases in proportion to their likelihood and impact.

## Verify the result
- Define how to verify success before or while implementing the change.
- Run the most relevant tests, linters, or targeted checks that are available.
- Inspect the final diff for unintended edits and unnecessary complexity.
- Report what was verified and what could not be verified; never claim unrun tests passed.
