# Backend Playbook: Database Schema and Migrations

## Capability: Database Schema Design

Use when:
- Designing new tables, collections, models, indexes, constraints, or relationships.

Procedure:
1. Read existing schema definitions, ORM or migration patterns, naming conventions, and query usage.
2. Identify access patterns, cardinality, integrity rules, retention needs, and cross-service ownership.
3. Design schema elements that match project style; define keys, indexes, constraints, and nullable rules explicitly.
4. Coordinate with System Architect on boundaries and with DevOps Engineer on deployment or storage implications when needed.
5. Add migration or model changes with tests or verification for critical queries and constraints.

Guardrails:
- Do not invent table, column, or index names without aligning to existing naming and migration tooling.
- Do not weaken integrity or authorization boundaries for convenience.
- Escalate large or cross-service schema changes to System Architect.

Output:
- Schema or model design consistent with project patterns.
- Migration or definition artifacts when applicable.
- Index and constraint rationale plus test or verification notes.

---

## Capability: Database Changes and Migrations

Use when:
- Applying migrations, backfills, renames, data transforms, or operational database updates.

Procedure:
1. Read current schema version, migration history, rollback support, and data-access code affected by the change.
2. Assess backward compatibility, lock risk, downtime, and data volume for the proposed change.
3. Write reversible or staged migrations when the project supports them; separate schema changes from heavy backfills when needed.
4. Coordinate destructive, long-running, or production-impacting operations with explicit approval and DevOps Engineer.
5. Verify migrations locally or in CI, update repositories and tests, and document rollout or rollback steps.

Guardrails:
- Do not run destructive data operations without explicit approval.
- Do not ship migrations that assume undeployed code or skip compatibility windows.
- Escalate production data changes and backup/recovery needs to DevOps Engineer.

Output:
- Safe migration scripts or equivalent change artifacts.
- Updated models, repositories, and tests.
- Rollout, rollback, or backfill notes when risk is non-trivial.

---

## Capability: Data Access Performance

Use when:
- Investigating slow queries, N+1 query patterns, indexing strategies, or data lock contention.

Procedure:
1. Read existing queries, query execution plans, indexes, connection pools, and caching mechanisms.
2. Profile the slow query to find root causes (missing index, full table scan, unnecessary joins, excessive payload).
3. Apply targeted optimizations (composite index, selective column projection, query batching).
4. Verify execution plan improvements and test against representative datasets.

Guardrails:
- Do not add indexes indiscriminately without evaluating write overhead.
- Do not bypass transactions when consistency is required.
