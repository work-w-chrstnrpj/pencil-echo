# Changelog

All notable changes to this project template are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] — Template Initialization

### Added

-   Canonical 8-role AI agent structure in `.agents/roles/`.
-   Reusable standalone skills in `.agents/skills/` (13 curated skills).
-   Mentor and Coach overlays in `.agents/overlays/`.
-   Multi-role workflow documents in `.agents/workflows/`.
-   Tool policies (context, verification, adapter generation, MCP) in `.agents/tools/`.
-   Adapter generation to Claude, Cursor, Copilot, Codex, OpenCode, Aider, Cline, Kilo, Windsurf, Antigravity, OpenHands, and Gemini.
-   Validation script (`scripts/validate-ai-template.ps1`) for metadata, frontmatter, and generated adapter formatting.
-   Context routing, agent maps, and prompt recipes in `.ai/`.
-   Wiki placeholders for TDD, product specification, project structure, API spec, data model, testing, deployment, diagrams, and development plan.
-   Template application, service, shared, and tests directory structure with READMEs.

### Changed

-   `opencode.json` and `kilo.jsonc` now use clean 2-space indentation with `$schema` first.
-   `generate-ai-adapters.ps1` documented as a backward-compatability wrapper around `sync-ai-adapters.ps1`.

### Fixed

-   Initial template hygiene: `.gitignore`, `LICENSE`, root `README.md`, and `CHANGELOG.md` added.
