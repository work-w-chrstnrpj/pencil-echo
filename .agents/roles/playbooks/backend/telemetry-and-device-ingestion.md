# Backend Playbook: Telemetry and Device Ingestion

## Capability: Device Data Ingestion

Use when:
- Accepting device or edge uploads via API, queue, file drop, MQTT, or similar ingestion entrypoints.

Procedure:
1. Read existing ingestion endpoints, authentication for devices, payload limits, and storage write paths.
2. Define admission checks, schema validation, rate limits, idempotency, and acknowledgment semantics.
3. Implement ingestion handlers that authenticate devices, validate payloads, and persist or enqueue safely.
4. Coordinate certificates, keys, network exposure, and scaling with DevOps Engineer and Security Engineer.
5. Add tests for authorized, unauthorized, oversized, duplicate, and malformed ingestion requests.

Guardrails:
- Do not invent device auth schemes or ingestion routes without project and security alignment.
- Do not accept unauthenticated or unbounded payloads at trust boundaries.
- Escalate new device-facing public surfaces to Security Engineer.

---

## Capability: Telemetry and Time-Series Ingestion

Use when:
- Normalizing, aggregating, validating, or storing telemetry or sensor readings in backend code.

Procedure:
1. Read existing telemetry models, unit conversions, sampling rules, deduplication, and downstream storage patterns.
2. Define valid ranges, timestamps, device identity fields, and malformed reading handling.
3. Implement processing pipelines that reject or quarantine bad data and preserve traceability.
4. Coordinate retention, privacy, and ingestion limits with Security Engineer when sensitive data is involved.
5. Add tests for valid samples, out-of-range values, missing fields, and duplicate readings.

Guardrails:
- Do not invent sensor fields, units, or device identifiers without project contracts or device specs.
- Do not silently coerce invalid readings into production aggregates.
- Escalate PII or safety-related telemetry handling to Security Engineer.

---

## Capability: MQTT & Serial Integration

Use when:
- Publishing or subscribing to MQTT topics or integrating serial ports/UART protocols in backend services.

Procedure:
1. Read existing broker or serial configuration, topic conventions, baud settings, and reconnect behavior.
2. Define framing, checksums, authentication, and idempotent handling of duplicate delivery.
3. Implement clients or handlers using project patterns; validate payloads and handle disconnects safely.
4. Coordinate hardware or network access with DevOps Engineer.
