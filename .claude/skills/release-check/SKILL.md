---
name: release-check
description: Prepare code for merge or release with verification, docs, environment, and deployment checks.
---

# Release Check

## Workflow

1. Confirm scope and unresolved work.
2. Review relevant lint, typecheck, test, build, and e2e commands from project docs.
3. Check docs, changelog, environment variables, deployment notes, and generated files.
4. Confirm no secrets, large generated outputs, or unrelated local files are included.
5. Summarize verification results and known risks.

## Boundaries

- Do not deploy to production without approval.
- Do not claim checks passed unless they ran or were reviewed from reliable output.
- Do not include generated graph or snapshot outputs unless intentionally reviewed.

## Output

- Relevant files or docs inspected.
- Work completed or plan produced.
- Tests or verification run or recommended.
- Docs updated or skipped with reason.
- Remaining risks, assumptions, and handoffs.
