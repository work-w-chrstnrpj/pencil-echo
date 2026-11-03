# DevOps Playbook: CI/CD Pipelines and Automation

## Capability: CI/CD

Use when:
- Creating or updating build, test, lint, package, or delivery pipelines.
- Fixing flaky CI, slow pipelines, or missing verification gates.

Procedure:
1. Inspect existing CI/CD definitions, build commands, branch policies, and verification commands in exact source files.
2. Identify the smallest pipeline change that enforces the project's actual build and test workflow.
3. Align jobs with documented verification commands and artifact outputs used by the project.
4. Add clear failure signals, caching only where safe, and reproducible steps across environments.
5. Coordinate with owning engineers when pipeline changes affect application packaging or test assumptions.

Guardrails:
- Do not hardcode secrets in workflow files.
- Do not disable checks to make CI pass without explicit approval.
- Do not invent build commands that are not supported by project docs or source configuration.

Output:
- CI/CD workflow updates.
- Notes on required checks and artifacts.
- Verification steps for pipeline changes.

---

## Capability: Automation Scripts

Use when:
- Creating scripts for build helpers, maintenance tasks, operational checks, or repeatable local and CI actions.
- Replacing fragile manual steps with scripted workflows.

Procedure:
1. Inspect existing script conventions, shell or task runners, and safety checks used by the project.
2. Define inputs, outputs, failure behavior, and idempotency expectations for the automation.
3. Implement scripts that are readable, minimally privileged, and safe to rerun where intended.
4. Add usage notes and integrate scripts into CI or deployment flows when appropriate.
5. Coordinate with Security Engineer when scripts touch credentials, external systems, or destructive actions.

Guardrails:
- Do not embed secrets in scripts or checked-in config.
- Do not create destructive automation without explicit approval and guardrails.
- Do not hide critical side effects inside implicit script behavior.
