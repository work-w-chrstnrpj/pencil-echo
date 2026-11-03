# DevOps Playbook: Edge Deployment and Message Brokers

## Capability: Queue Operations

Use when:
- Operating message queues, workers, dead-letter handling, backlog recovery, or consumer scaling.
- Troubleshooting stuck messages, poison payloads, or worker instability.

Procedure:
1. Inspect queue names, worker configuration, retry policies, and dead-letter conventions in exact source and ops files.
2. Identify producer and consumer ownership, throughput needs, and failure handling expectations.
3. Configure observability for queue depth, consumer health, retries, and dead-letter volume.
4. Document safe replay, purge, or drain procedures for operators.
5. Coordinate with Backend & Database Engineer for message-format or handler defects.

---

## Capability: Edge Deployment

Use when:
- Deploying or operating software on edge devices, gateways, constrained hosts, or offline-capable environments.
- Managing remote updates, health checks, or configuration sync for edge runtimes.

Procedure:
1. Inspect edge packaging, update mechanics, device constraints, and current deployment conventions.
2. Define rollout, rollback, and health-validation steps suitable for limited connectivity or remote hosts.
3. Keep edge configuration separable from core cloud defaults and document environment differences.
4. Add observability or heartbeat signals appropriate to edge operational needs.
5. Coordinate with Backend & Database Engineer for edge API, telemetry, or data-sync dependencies.

---

## Capability: MQTT Broker Operations

Use when:
- Operating MQTT brokers, topics, authentication, bridges, or broker-side reliability settings.
- Troubleshooting connection churn, ACL issues, or broker resource limits.

Procedure:
1. Inspect broker configuration, topic conventions, authentication, TLS settings, and client connection patterns.
2. Identify ownership boundaries between broker operations and application-level MQTT integration.
3. Configure durable settings, access controls, monitoring, and restart behavior appropriate to the deployment.
4. Document safe operational changes, topic hygiene, and escalation paths for client-side defects.
