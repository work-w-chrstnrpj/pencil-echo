# Cursor Adapters

Cursor-compatible adapters are generated from canonical files in `.agents/`.

- Rules: `.cursor/rules/*.mdc`
- Skills: `.cursor/skills/<skill>/SKILL.md`

Edit `.agents/roles/` or `.agents/skills/`, then run `node bin/create-preset.mjs sync` (or `scripts/sync-ai-adapters.ps1`). Rules point back to `AGENTS.md`, `docs/`, and `.agents/`.
