# DevOps Playbook: Deployment, Rollouts, and Releases

## Capability: Deployment

Use when:
- Setting up or changing deployment targets, release flows, hosting configuration, or rollout procedures.
- Preparing staging or production deployment steps.

Procedure:
1. Inspect current deployment scripts, hosting configuration, environment separation, and rollback patterns.
2. Define the deployment sequence, prerequisites, health checks, and approval gates.
3. Keep deployment steps reproducible, idempotent where possible, and documented for operators.
4. Validate that build artifacts, migrations, and runtime config align with the target environment.
5. Record rollback steps and post-deploy verification before any production rollout.

Guardrails:
- Do not deploy to production without explicit approval.
- Do not change application business logic except for operational wiring with owner coordination.
- Do not rely on manual steps that cannot be repeated or audited.

Output:
- Deployment workflow or configuration changes.
- Deployment and rollback instructions.
- Post-deploy verification checklist.

---

## Capability: Environment Configuration

Use when:
- Managing environment variables, runtime settings, secrets references, or per-environment overrides.
- Documenting configuration required for local, staging, or production operation.

Procedure:
1. Inspect existing environment examples, config loaders, deployment manifests, and secrets handling patterns.
2. Identify required variables, defaults, validation rules, and environment-specific differences.
3. Use secure secret references rather than committed credentials and keep examples sanitized.
4. Align variable names and semantics across app, CI, and deployment tooling.
5. Update operational docs or coordinate `update-docs` when configuration behavior changes.

Guardrails:
- Do not commit secrets, tokens, private keys, or production credentials.
- Do not expose sensitive values in logs, docs, or pipeline output.
- Do not create undeclared config dependencies that break local or CI workflows silently.

---

## Capability: Release Management

Use when:
- Planning version cuts, release branches, changelogs, rollout sequencing, or promotion between environments.
- Coordinating release readiness across engineering roles.

Procedure:
1. Inspect current release conventions, versioning scheme, tags, artifacts, and approval gates.
2. Identify changes in scope, migration needs, config updates, and verification requirements for the release.
3. Use `release-check` to confirm merge and release readiness before promotion.
4. Sequence rollout steps, feature flags, migrations, and rollback options where applicable.
5. Coordinate changelog and operator documentation updates before or during release.
