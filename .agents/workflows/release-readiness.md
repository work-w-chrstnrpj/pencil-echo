# Release Readiness

Multi-role workflow for merge or release preparation.

## Flow

```text
release-check -> verify tests/build/docs/env/migrations/security/rollback -> summarize readiness and blockers
```

## Roles

- **Owning engineer**: runs `release-check` and addresses blockers.
- **DevOps Engineer**: deployment, env, and rollback readiness.
- **Security Engineer**: sensitive-flow review when applicable.
- **SQA Engineer**: verification evidence.

## Notes

- Never mark ready without actual verification evidence.
- Summarize blockers explicitly.
