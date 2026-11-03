# Workflow Adapter: chore-delivery

Generated from `.agents/workflows/chore-delivery.md`.

# Chore Delivery

Multi-role workflow for cleanup, config, dependency, and maintenance work.

## Flow

```text
plan-code-change for risky chores -> execute-code-change -> focused verification -> update docs/config notes if needed
```

## Roles

- **Owning engineer**: executes the chore.
- **DevOps Engineer**: when CI, deployment, or environment config is affected.
- **Technical Documentation Specialist**: when operator or setup docs change.

## Notes

- Use chore mode in `plan-code-change` for non-trivial maintenance.
- Report skipped verification with reason.
