# Workflow Adapter: feature-delivery

Generated from `.agents/workflows/feature-delivery.md`.

# Feature Delivery

Multi-role workflow for adding new behavior.

## Flow

```text
Product intent -> Architect when needed -> plan-code-change -> execute-code-change -> tests -> update-docs -> release-check
```

## Roles

- **Product & Planning Manager**: clarify intent, acceptance criteria, and scope.
- **System Architect**: design cross-module boundaries when needed.
- **Implementation roles**: execute via `execute-code-change`.
- **SQA Engineer**: automated and manual verification.
- **Technical Documentation Specialist**: docs via `update-docs`.
- **Any owner**: `release-check` before merge.

## Notes

- Use `plan-code-change` in feature mode before large or unclear work.
- Keep changes small and source-grounded.
