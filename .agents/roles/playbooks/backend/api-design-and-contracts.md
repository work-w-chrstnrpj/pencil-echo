# Backend Playbook: API Design and Contracts

## Capability: API Design

Use when:
- Designing new endpoints, request/response shapes, status codes, pagination, filtering, or error contracts.

Procedure:
1. Inspect existing API style, versioning, naming, serialization, auth middleware, and documented contracts.
2. Identify consumers, trust boundaries, and compatibility constraints for the proposed surface.
3. Define request validation, response shape, error model, and auth requirements consistent with existing APIs.
4. Coordinate breaking changes with Frontend UI/UX Developer and Technical Documentation Specialist.
5. Document contract notes and add API or contract tests for the new or changed surface.

Guardrails:
- Do not invent endpoint paths, field names, or status conventions without checking project contracts.
- Do not expose internal models directly when the project uses DTO or schema layers.
- Escalate public or sensitive API expansions to Security Engineer when auth scope changes.

Output:
- Endpoint or handler design aligned with project conventions.
- Validation and error-handling rules.
- API contract notes and test coverage plan.

---

## Capability: API Contract Compatibility

Use when:
- Changing existing endpoints, payloads, enums, error codes, or client-facing behavior.

Procedure:
1. Read current contracts, OpenAPI or schema docs, client usage, and existing compatibility tests.
2. Classify the change as additive, backward compatible, or breaking; list affected consumers.
3. Prefer additive changes; use versioning, feature flags, or deprecation paths when breaking change is unavoidable.
4. Coordinate client updates and documentation with owning roles before merge.
5. Add contract or regression tests that lock expected request/response behavior.

Guardrails:
- Do not silently break clients or remove fields without a migration or deprecation plan.
- Do not change auth requirements without explicit coordination and review.
- Escalate breaking public API changes to Product & Planning Manager and Security Engineer when scope or risk is unclear.

Output:
- Compatibility assessment and chosen migration approach.
- Updated handlers, schemas, or adapters with preserved or migrated behavior.
- Contract tests and updated API notes.

---

## Capability: API Testing Coordination

Use when:
- Backend changes need API, integration, or contract test coverage beyond unit tests.

Procedure:
1. Read existing API test patterns, fixtures, auth setup, and verification commands in the repo.
2. Identify endpoints, status codes, validation failures, auth cases, and edge inputs that must be covered.
3. Implement or extend automated API or integration tests using project conventions.
4. Coordinate with SQA Engineer on manual cases, regression scope, or environments when needed.
5. Run relevant test commands and report gaps, flakes, or environment blockers.

Guardrails:
- Do not claim API behavior is verified without running or reliably reporting tests.
- Do not hardcode secrets, production URLs, or unstable external dependencies in tests.
- Escalate missing test infrastructure or environment setup to DevOps Engineer.

Output:
- Automated API or integration tests for critical paths and failures.
- Test checklist or handoff notes for SQA when manual coverage is needed.
- Verification results for executed commands.
