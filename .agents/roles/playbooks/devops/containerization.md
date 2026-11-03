# DevOps Playbook: Containerization and Infrastructure

## Capability: Containerization

Use when:
- Creating or updating container images, compose setups, runtime images, or container deployment wiring.
- Fixing image build failures, size problems, or runtime permission issues.

Procedure:
1. Inspect existing Dockerfiles, compose files, image build steps, and runtime entrypoints.
2. Align base images, build stages, and runtime users with project security and deployment conventions.
3. Keep images reproducible, minimally privileged, and aligned with actual build artifacts.
4. Verify container startup, health checks, and required environment configuration.
5. Coordinate with deployment targets so image tags and rollout steps remain consistent.

Guardrails:
- Do not bake secrets into images or layers.
- Do not run containers as unnecessary root without justification.
- Do not introduce base-image or tooling changes that break reproducible builds silently.

---

## Capability: Infrastructure-as-Code

Use when:
- Defining or updating infrastructure resources, modules, state boundaries, or environment provisioning.
- Reviewing IaC changes for safety, repeatability, and environment drift.

Procedure:
1. Inspect existing IaC modules, state management, environment separation, and naming conventions.
2. Model the smallest infrastructure change needed with clear inputs, outputs, and dependencies.
3. Keep environments isolated appropriately and avoid hidden manual steps outside IaC.
4. Plan apply order, rollback considerations, and verification after provisioning changes.
5. Coordinate with Security Engineer for IAM, network exposure, or secrets-related infrastructure.

Guardrails:
- Do not apply production infrastructure changes without explicit approval.
- Do not store secrets in plain IaC source.
- Do not create unaudited one-off infrastructure outside the project's IaC pattern.
