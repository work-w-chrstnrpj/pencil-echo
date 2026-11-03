# 003 — Upstream reuse inventory and provenance format

Milestone: PE-000 · Status: Resolved (2026-11-03) · Owner: Claude · Depends on: none

## What

List which `inspiration/` files will be ported to Swift (or embedded as-is), map each to a target module, and define how copied code records provenance.

## Why

The owner approved copying from upstream for this private project (`docs/decisions.md`, 2026-11-03). An inventory stops Codex from porting arbitrary files and keeps the AGPL/MIT notices traceable if the project is ever shared.

## Baseline

`inspiration/` commit `341e34d6cf2965ac8f58d0d89cf33e285ace9b2d` (PenEcho 1.4.2).

## Candidate files to assess

| Upstream | Likely use |
|---|---|
| `src/providers/api-presets.js`, `src/server/api-config.js` | Provider presets, models, endpoints (ticket 007, 012, 013) |
| `src/server/api-stream.js` | Streaming/SSE request handling per provider (007, 012, 013) |
| `src/providers/reasoning-effort.js` | Per-model reasoning options (012) |
| `src/server/model-content.js` | Building image/text content blocks (007, 010) |
| `src/server/canvas-command-prompt.js` | System prompt for canvas answers (010) |
| `src/server/scene-contract.md`, `src/server/canvas-agent/document-schema.mjs` | Answer/command schema (006) |
| `src/server/typeset.js`, `public/mathjax-config.js` | Formula/Markdown rendering approach (011) |
| `src/client/app/canvas-documents.js`, `src/client/app/persistence.js` | Document structure ideas (005) |
| `src/architecture/`, `src/sequence/`, `src/workflow/` `schema.js` | Diagram schemas (PE-003, later) |

## Scope

- Create `docs/reuse-inventory.md`: upstream path, upstream license (AGPL-3.0 or vendored MIT/EPL/BSD per `inspiration/NOTICE`), target Swift file/module, port type (translate / embed / reference only), ticket.
- Define the provenance header for ported files, e.g.:

```swift
// Ported from PenEcho inspiration/src/server/api-stream.js @ 341e34d (AGPL-3.0-only).
```

- Add a rule to `AGENTS.md`: ported files carry the header and an inventory row.

## Exclusions

No porting work itself. No changes inside `inspiration/`.

## Acceptance

- [x] Inventory covers every file named in tickets 005–013.
- [x] Provenance header format and `AGENTS.md` rule added.

## Resolution notes

`docs/reuse-inventory.md` lists 14 upstream entries with license, contents, target module, port type and ticket. All candidate files exist at `341e34d`. The rule is in `AGENTS.md` under "Upstream Reuse Rules".

Some files are not what the candidate table above assumed. The inventory's "Mismatches found in the tickets" section covers each one:
- The answer schema is inline in `canvas-command-prompt.js`; `scene-contract.md` covers widget scenes (affects 006).
- `document-schema.mjs` is a JSON Schema subsetting helper, not a document schema (affects 005).
- `typeset.js` is a transcription prompt; formulas render with vendored MathJax 3.2.2 under Apache-2.0 (affects 011).
- Upstream has no Gemini stream path (affects 013).
