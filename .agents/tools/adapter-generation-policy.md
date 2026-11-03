# Adapter Generation Policy

## Canonical Sources

- `AGENTS.md`
- `.agents/roles/`
- `.agents/skills/`
- `.agents/overlays/`
- `.agents/workflows/`
- `.agents/tools/`

Tool-specific folders are generated adapters, not source of truth.

## Generation Rules

- Generated files should include a source note pointing to canonical files.
- Stale generated skill folders must be cleaned after pruning skills.
- Do not hand-edit generated adapters unless explicitly instructed.
- If a target tool's exact format is uncertain, generate conservative markdown or rule files and document the assumption.

## Preferred Command

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/sync-ai-adapters.ps1 -Target all
```

Compatibility wrapper:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/generate-ai-adapters.ps1
```
