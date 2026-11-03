# Backend Playbook: Integrations and Webhooks

## Capability: Integration Design

Use when:
- Designing connections to third-party APIs, internal services, SDKs, or shared integration boundaries.

Procedure:
1. Read existing integration clients, retry policies, configuration patterns, and documented external contracts.
2. Define request/response mapping, timeouts, idempotency keys, error translation, and observability hooks.
3. Implement adapters that follow project structure; validate outbound payloads and inbound responses at boundaries.
4. Coordinate credentials, webhooks, rate limits, and environment config with DevOps Engineer and Security Engineer.
5. Add integration tests or contract stubs and document failure handling and operational expectations.

Guardrails:
- Do not invent external endpoints, credentials handling, or message formats without verified documentation.
- Do not leak secrets in logs, errors, or tests.
- Escalate new third-party data flows or PII handling to Security Engineer.

Output:
- Integration client, adapter, or boundary design.
- Error, retry, and idempotency behavior notes.
- Tests or stubs and coordination notes for operations or security review.

---

## Capability: Webhook Processing

Use when:
- Receiving, verifying, routing, or persisting inbound webhook events from external systems.

Procedure:
1. Read existing webhook routes, signature verification, payload schemas, and idempotency handling in the project.
2. Identify event types, ordering assumptions, replay risk, and downstream side effects.
3. Implement verification, validation, deduplication, and structured error responses using established patterns.
4. Coordinate exposed URLs, secrets rotation, and delivery retries with DevOps Engineer and Security Engineer.
5. Add tests for valid, invalid, duplicate, and malformed payloads; document expected retry behavior.

Guardrails:
- Do not invent webhook paths, headers, or signature schemes without checking provider and project docs.
- Do not process unverified or unvalidated payloads when verification is required.
- Escalate new inbound public endpoints to Security Engineer.

Output:
- Webhook handler with verification, validation, and idempotency behavior.
- Tests for success, rejection, and duplicate delivery cases.
- Operational notes on retries, dead letters, or alerting handoffs.

---

## Capability: Auth Implementation

Use when:
- Implementing or changing authentication, authorization, sessions, tokens, roles, or permission checks.

Procedure:
1. Read existing auth middleware, identity providers, session or token storage, and permission models in the codebase.
2. Identify protected resources, trust boundaries, and failure modes for unauthorized or malformed credentials.
3. Implement checks using established patterns; validate inputs and fail closed at boundaries.
4. Coordinate sensitive scope, OAuth, or policy changes with Security Engineer before approval.
5. Add tests for allowed, denied, expired, and malformed auth cases; avoid logging secrets.

Guardrails:
- Do not invent auth schemes, role names, or token formats without project alignment.
- Do not store secrets in code, logs, or tests.
- Do not approve security-sensitive auth flows without Security Engineer review.
