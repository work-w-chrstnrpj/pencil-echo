# Workflow Adapter: investigation-to-rca

Generated from `.agents/workflows/investigation-to-rca.md`.

# Investigation to RCA

Multi-role workflow from diagnosis to formal reporting.

## Flow

```text
investigate-issue -> evidence review -> generate-rca only after findings exist -> docs/handoff
```

## Roles

- **Primary investigator**: `investigate-issue` for evidence and hypotheses.
- **Technical Documentation Specialist**: `generate-rca` when formal deliverable is needed.
- **Owning engineers**: implement fixes separately via bugfix delivery.

## Notes

- `investigate-issue` diagnoses; it does not write formal RCA.
- `generate-rca` formats completed findings into a report.
