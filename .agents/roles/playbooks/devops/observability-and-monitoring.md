# DevOps Playbook: Observability and Monitoring

## Capability: Observability

Use when:
- Adding or improving logs, metrics, traces, health endpoints, or alert signals.
- Making runtime behavior easier to diagnose across services, jobs, or edge components.

Procedure:
1. Inspect current logging, metrics, tracing, and health-check conventions in exact source and ops files.
2. Identify the failure modes and operator questions the system must answer quickly.
3. Add structured, actionable signals without logging sensitive data or excessive noise.
4. Connect health checks and service signals to deployment and orchestration expectations.
5. Document what to inspect during incidents and which alerts indicate real action items.

Guardrails:
- Do not log secrets, tokens, credentials, or private user data.
- Do not add high-cardinality or noisy telemetry that obscures real failures.
- Do not treat observability setup as complete without a verification path.

---

## Capability: Runtime Monitoring and Alerting

Use when:
- Operating live systems, reviewing alerts, investigating runtime degradation, or validating service health after change.
- Setting up dashboards or alert routing for ongoing operations.

Procedure:
1. Inspect existing monitoring stack, alert rules, dashboards, and on-call or escalation conventions.
2. Map critical services, jobs, queues, and dependencies to measurable health signals.
3. Configure alerts for actionable conditions with clear severity and runbook pointers.
4. Verify monitoring after deployment or infrastructure changes.
5. Coordinate incident findings with owning engineers and document recurring operational gaps.

Guardrails:
- Do not create alert storms from untuned thresholds.
- Do not treat absence of alerts as proof of system health without spot checks.
- Do not perform production remediation beyond approved operational scope.
