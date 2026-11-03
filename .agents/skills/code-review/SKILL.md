---
name: code-review
description: Review changed code for correctness, architecture, security, contracts, tests, and maintainability.
---

# Code Review

## Workflow

1. Read `AGENTS.md` and the current diff.
2. Inspect exact changed files and nearby source.
3. Check correctness, architecture boundaries, security, API/data contracts, type safety, error handling, tests, and maintainability.
4. Prioritize concrete bugs and risks over style preferences.
5. Report findings first, ordered by severity, with file and line references where possible.

## Boundaries

- Do not make changes unless explicitly asked.
- Do not flag speculative issues without a plausible failure scenario.
- Do not bury important findings under summaries.

## Output

- Relevant files or docs inspected.
- Work completed or plan produced.
- Tests or verification run or recommended.
- Docs updated or skipped with reason.
- Remaining risks, assumptions, and handoffs.
