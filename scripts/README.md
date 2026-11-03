# Scripts Placeholder

This folder is intended for project automation scripts.

Use scripts for repeatable development, verification, setup, maintenance, data processing, release, or operational tasks.

## Automation & Preset Engine

The primary cross-platform CLI engine is written in native Node.js (in `bin/create-preset.mjs` and `lib/`), requiring zero third-party dependencies:

- `node bin/create-preset.mjs <provider> [--profile <profile>] [--into <dir>]` — generate tailored provider presets.
- `node bin/create-preset.mjs sync [--target <provider|all>]` — regenerate tool adapters.
- `node bin/create-preset.mjs validate [--task <task>]` — validate structure, links, and context readiness.
- `node bin/create-preset.mjs measure` — benchmark role context tokens and rule scoping.

## PowerShell Scripts

For environments with PowerShell 7+ or Windows PowerShell:

| Script | Purpose |
| --- | --- |
| `sync-ai-adapters.ps1` | Target-aware sync for Claude, Codex, Cursor, Copilot, OpenCode, Aider, Cline, Kilo, Windsurf, Antigravity, and OpenHands adapters from canonical `.agents/` sources. |
| `generate-ai-adapters.ps1` | Compatibility wrapper that runs `sync-ai-adapters.ps1 -Target all`. |
| `validate-ai-template.ps1` | Validate canonical role metadata, skill frontmatter, generated adapter formatting, and absence of removed granular skills. |

## Validation

Run validation via Node or PowerShell:

```bash
node bin/create-preset.mjs validate
# or
npm run validate
```

The validation script checks:

1. Canonical role metadata is parseable (`- **Name:**`, `- **Role:**`, `- **Description:**` at line starts).
2. Role files have adequate line count (not compressed).
3. Role files use `## Reusable Skills` and `## Embedded Capability Playbooks` (no deprecated `## Allowed Skills`).
4. Exactly 13 curated standalone skills are present with no extras or missing folders.
5. Every `.agents/skills/*/SKILL.md` has valid multiline YAML frontmatter with `name:` and `description:`.
6. Removed granular skill folders are not present.
7. Overlay files (`mentor.md`, `coach.md`, `README.md`) are readable Markdown.
8. Generated adapter files in `.claude/`, `.cursor/`, `.github/`, `.opencode/`, `.windsurf/` use multiline frontmatter (no `--- name:` on one line).
9. Generated agent/rule files contain source-of-truth notices pointing back to `.agents/`.
10. OpenCode overlay files (coach, mentor) deny edit permission.
11. `AGENTS.md` has adequate line count and heading structure.
12. Script files have adequate line count (not compressed).

## Adapter Sync

After canonical changes pass validation, regenerate adapters:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-ai-adapters.ps1 -Target all
```

Then validate again:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-ai-template.ps1
```

## Suggested Sections To Fill

- Script purpose.
- Required inputs.
- Expected outputs.
- Safe usage examples.
- Failure modes.
- Whether the script can change production, secrets, data, or tracked files.

Do not add destructive scripts without clear safeguards and documentation.
