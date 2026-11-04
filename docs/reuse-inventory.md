# Upstream reuse inventory

Status: ACTIVE. Updated: 2026-11-03 (ticket 003).

Upstream: `inspiration/` at commit `341e34d6cf2965ac8f58d0d89cf33e285ace9b2d` (PenEcho 1.4.2). Copying is approved for this private project (`docs/decisions.md`, gate 7). AGPL-3.0 and trademark obligations apply again if the project or a build is ever shared.

Only files listed here may be ported. To port something new, add a row first.

## Port types

- **translate**: rewrite the logic in Swift and keep the behavior. The Swift file carries the provenance header.
- **embed**: ship the upstream file unchanged as a bundle resource. Keep its license file next to it.
- **reference**: read it for design ideas only. Nothing is copied, so no header is needed. Add a "Design reference" line to the spec instead.

## Licenses

From `inspiration/NOTICE` and `inspiration/LICENSE`:

- PenEcho's own code, prompts and docs: **AGPL-3.0-only**. None of the files below carry a per-file header; the repository license applies.
- Vendored third-party code keeps its own license: Archify helpers (MIT), elkjs worker (EPL-2.0), DeepSeek Harness backports in `src/server/canvas-agent/vendor/` (MIT), MathJax 3.2.2 in `public/vendor/mathjax-3.2.2/` (Apache-2.0), AntV Infographic, anime.js, matter-js, Zdog, three.js, eventsource-parser (all MIT).
- The PenEcho name, wordmark and logo are trademarks and are not licensed. Never copy brand assets or user-facing "PenEcho" strings. Use "Pencil Echo".

## Inventory

| Upstream path | License | Contents (checked 2026-11-03) | Target Swift module / file | Port type | Ticket |
|---|---|---|---|---|---|
| `src/providers/api-presets.js` | AGPL-3.0-only | OpenAI-format preset table: id, label, base URL. Includes `qwen-china`, `qwen-global` (Singapore) and `qwen-us`, plus Groq, Mistral and OpenRouter. | `Services/Providers/ProviderPresets.swift` | translate | 007, 012 |
| `src/server/api-config.js` | AGPL-3.0-only | Base URL validation and normalization, picks `openai` or `anthropic` format from the URL path, max-token defaults. | `Services/Providers/ProviderEndpoint.swift` | translate | 007, 012, 013 |
| `src/server/api-stream.js` | AGPL-3.0-only (uses MIT `eventsource-parser`) | SSE reading and final-text extraction for three formats: OpenAI Chat Completions, OpenAI Responses and Anthropic Messages. **No Gemini path.** | `Services/Providers/ProviderStream.swift` | translate (write our own SSE parser; do not port `eventsource-parser`) | 007, 012, 013 |
| `src/providers/reasoning-effort.js` | AGPL-3.0-only | Per-model reasoning-effort options and how each provider expects them. | `Services/Providers/ReasoningEffort.swift` | translate | 012, 013 |
| `src/server/model-content.js` | AGPL-3.0-only | Parses PNG/WebP data URLs, and recovers complete top-level JSON objects from streamed text. | `Services/AI/ModelContent.swift` | translate | 007, 010 |
| `src/server/canvas-command-prompt.js` | AGPL-3.0-only | 747-line system prompt plus command post-processing. The `JSON_RESPONSE_SCHEMA_PROMPT` constant (line 137) holds the **authoritative response schema**: `intent` enum, `observedText`, `message`, and 1–16 `commands`, each with a `tool`. Layout rules for `write_text` and `draw_formula` start around line 530. | `service/AI/CanvasCommandPrompt.swift` (ported 2026-11-03, trimmed to v1 tools; header present); schema in 006. Ticket 017 (2026-11-04) adds the spatial editing rules (line 127) and the `latestInput`/`captureRect` focus contract (line 720) as `focusFrame`/`captureFrame`. Ticket 018 adds the `draw` encoding at line 148 (`arc`, `closed`, `fill`, `arrows`) as `draw_ink` strokes. Ticket 019 adds the `focusInset` note at line 123 as a second magnified image. | translate (trimmed) | 006, 010, 017, 018, 019 |
| `src/server/scene-contract.md` | AGPL-3.0-only | Widget **motion/physics/3D scene** contract for `html_widget`. It is **not** the answer schema. | none for now | reference | PE-006 (not 006) |
| `src/server/typeset.js` | AGPL-3.0-only | `NORMALIZE_TYPESET_POLICY` prompt: transcribe a lasso selection into clean text and formulas. It is **not** a renderer. | `Services/AI/TypesetPolicy.swift` | translate | 010 (later "clean up" action); reference for 011 |
| `public/mathjax-config.js` | AGPL-3.0-only | Two-line MathJax config: SVG output, no font cache. | Only if 011 falls back to WKWebView | reference | 011 |
| `public/vendor/mathjax-3.2.2/` | Apache-2.0 | Vendored MathJax `tex-svg.js`, with `LICENSE` and `SOURCE.json`. | `App/Resources/MathJax/` (fallback only) | embed (with `LICENSE`) | 011 |
| `src/server/canvas-agent/document-schema.mjs` | AGPL-3.0-only | Helper that reduces a JSON Schema to the subset the Harness SDK accepts. It is **not** a document schema. | none | reference | 006 (schema subsetting idea for provider structured output) |
| `src/client/app/canvas-documents.js` | AGPL-3.0-only | Multi-document workspace on IndexedDB: 64-document limit, image assets keyed by SHA-256 (`penecho-asset:<hash>`, 64 assets, 16 MB each), bundle V2. | none | reference | 005 |
| `src/client/app/persistence.js` | AGPL-3.0-only | 4,200-line browser persistence layer (IndexedDB snapshots). | none | reference | 005 |
| `src/architecture/schema.js`, `src/sequence/schema.js`, `src/workflow/schema.js` | AGPL-3.0-only (renderers use MIT Archify and EPL-2.0 elkjs) | Diagram validation and HTML rendering. | later diagram module | reference until PE-003 | PE-003 |

## Mismatches found in the tickets

The upstream files differ from what some tickets assume. Specs written from these tickets must use the facts above.

- **006:** take the answer shape from `JSON_RESPONSE_SCHEMA_PROMPT` in `canvas-command-prompt.js`, not from `scene-contract.md`. Upstream only validates `tool` and leaves the rest open (`additionalProperties: true`). The v1 schema must define each tool's fields.
- **005:** `document-schema.mjs` has no document schema, and upstream uses IndexedDB in the browser. Use it as design input only: a document limit, hash-keyed assets with size limits, and a versioned bundle.
- **011:** `typeset.js` is a prompt policy, not a renderer. Upstream renders formulas with vendored MathJax 3.2.2 (Apache-2.0), which is the fallback if SwiftMath fails.
- **013:** upstream has an Anthropic stream path but no Gemini path. The Gemini adapter is new work, built from Google's official docs.

## Provenance header

Every Swift file that translates upstream code starts with one line per source file:

```swift
// Ported from PenEcho inspiration/src/server/api-stream.js @ 341e34d (AGPL-3.0-only).
```

- Use the short commit `341e34d` and the path relative to the repository root.
- Use the upstream file's license, as listed in the table above.
- If the Swift file is later changed beyond the port, keep the header.
- An embedded file keeps its upstream name, and its license file goes in the same folder.
- If the upstream baseline moves to a new commit, update this document's baseline and the header of each file you re-port.

## Ticket 007 implementation record — 2026-11-03

Approved material is implemented at `service/Providers/ProviderPresets.swift` (region presets), `service/Providers/ProviderStream.swift` and `OpenAICompatibleProvider.swift` (stream accumulation/orchestration), and `service/AI/ModelContent.swift` (PNG data URL boundary). Each derived file carries its upstream path, short commit and AGPL-3.0-only header. The SSE framer was written in Swift; no eventsource-parser code was copied. Keychain, URLSession transport, Debug UI, synthetic PNG and protocol fixtures are new code/assets. Provider contract changes were independently checked against current official documentation (`docs/api/providers.md`). No upstream files were modified.

## Ticket 013 implementation record — 2026-11-04

`service/Providers/AnthropicProvider.swift` ports the `acceptAnthropic` text/usage/event extraction from the already inventoried `src/server/api-stream.js @ 341e34d` (AGPL-3.0-only), with a provenance header and additional ordering/terminal/error/size checks. Native request builders and common bounded transport integration are written in Swift. `GeminiProvider.swift` is original work against Google's official API, because the inventoried upstream has no Gemini path. No upstream file was modified. Current contract sources and real-provider limitations are in `docs/api/providers.md`.
