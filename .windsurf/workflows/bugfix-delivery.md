# Workflow Adapter: bugfix-delivery

Generated from `.agents/workflows/bugfix-delivery.md`.

# Bugfix Delivery

Multi-role workflow for correcting broken behavior.

## Flow

```text
investigate-issue -> plan-code-change if non-trivial -> execute-code-change -> regression tests -> update-docs if needed -> release-check
```

## Roles

- **Primary investigator** (from evidence): leads diagnosis via `investigate-issue`.
- **Owning engineer**: minimal fix via `execute-code-change`.
- **SQA Engineer**: regression verification.
- **Technical Documentation Specialist**: docs only when behavior or operator guidance changes.

## Notes

- Do not auto-fix during investigation.
- Use `generate-rca` only after investigation findings exist and a formal RCA is requested.
