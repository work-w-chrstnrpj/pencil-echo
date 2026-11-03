# Refactor Delivery

Multi-role workflow for structural changes without intended behavior change.

## Flow

```text
ask-repo-question or plan-code-change -> execute-code-change -> behavior-preserving tests -> code-review -> release-check
```

## Roles

- **Any owner**: understand current structure before changing it.
- **Implementation role**: narrow refactor via `execute-code-change`.
- **SQA Engineer**: behavior-preserving verification.
- **Reviewer**: `code-review` when risk is non-trivial.

## Notes

- Use refactor mode in `plan-code-change` to document preservation rules.
- Prefer the smallest safe refactor slice.
