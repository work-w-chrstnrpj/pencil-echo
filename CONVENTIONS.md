# Project Conventions

Generated summary for Aider. Canonical sources: `AGENTS.md` and `.agents/`.

## Operating Rules

- Exact source files are truth; maps and indexes are navigation only.
- Update canonical `.agents/` files first, then run `scripts/sync-ai-adapters.ps1`.
- Never claim verification passed unless it actually ran.
- Ask approval before destructive, production, secret, or migration operations.

## Canonical AI Structure

- Roles: `.agents/roles/`
- Skills: `.agents/skills/` (reusable workflows only)
- Overlays: `.agents/overlays/` (Mentor, Coach)
- Workflows: `.agents/workflows/`
- Tool policies: `.agents/tools/`

See `.agents/tools/verification-policy.md` and `.agents/tools/adapter-generation-policy.md`.
