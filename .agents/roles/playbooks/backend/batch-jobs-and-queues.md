# Backend Playbook: Batch Jobs and Queues

## Capability: Queue Worker Design

Use when:
- Implementing consumers, workers, dead-letter handling, or background processing off a queue.

Procedure:
1. Read existing queue clients, worker bootstrap, message formats, retry/backoff settings, and observability hooks.
2. Identify message schema, side effects, concurrency limits, and idempotency requirements.
3. Implement workers that validate input, process safely, acknowledge or nack correctly, and surface failures observably.
4. Coordinate queue names, broker settings, scaling, and runtime deployment with DevOps Engineer.
5. Add tests for happy path, retryable failure, permanent failure, and malformed messages.

Guardrails:
- Do not invent queue or dead-letter names without project configuration.
- Do not perform non-idempotent side effects without deduplication or safeguards.
- Escalate broker or runtime changes to DevOps Engineer.

Output:
- Queue worker implementation with retry and failure handling.
- Tests for processing, retry, and poison-message behavior.
- Operations handoff notes for monitoring and replay.

---

## Capability: Batch Job Design

Use when:
- Implementing one-off or recurring batch programs that process records, files, or external data in bulk.

Procedure:
1. Read existing batch entrypoints, chunking patterns, checkpointing, logging, and failure recovery in the project.
2. Define input sources, batch size, ordering, idempotency, and partial-failure behavior.
3. Implement job logic with validation, safe writes, progress reporting, and exit codes consistent with project style.
4. Coordinate schedules, resource limits, and runtime execution with DevOps Engineer.
5. Add tests for normal batches, empty input, malformed records, and recoverable failures.

Guardrails:
- Do not invent job names, schedules, or input paths without checking project conventions.
- Do not perform destructive bulk updates without explicit approval and rollback planning.
- Escalate long-running or production batch deployments to DevOps Engineer.

Output:
- Batch job implementation with checkpointing or recovery behavior where needed.
- Tests for core and failure scenarios.
- Runtime and scheduling coordination notes.

---

## Capability: CLI Tool Development

Use when:
- Building or updating command-line tools for operations, migrations, imports, or developer workflows.

Procedure:
1. Read existing CLI frameworks, command naming, config loading, exit codes, and help text patterns.
2. Define commands, arguments, environment assumptions, and side effects with least-privilege defaults.
3. Implement commands with input validation, dry-run or confirmation flags when destructive, and clear error output.
4. Coordinate distribution, secrets, and runtime packaging with DevOps Engineer when needed.
5. Add tests for command parsing, success paths, and failure cases; document usage examples.
