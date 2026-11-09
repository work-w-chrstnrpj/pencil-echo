# Changelog

All notable changes to Pencil Echo are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [0.1.1] — 2026-11-09

### Added

- **Qwen free quota fallback:** with Qwen · Singapore selected, Ask AI can move to the next vision model when Alibaba reports that a model's free quota is used up (`AllocationQuota.FreeTierOnly`). It retries the same request with the same key, remembers which models are used up, and never retries after an answer has started. Turn it on in AI Settings → Free quota. It's off by default and needs **Free Quota Only** turned on for all models in the Model Studio console, so a used-up model is never billed.
- **More Qwen vision models** in the suggestions: the `qwen3-vl-plus`, `qwen3-vl-flash`, `qwen-vl-max` and `qwen-vl-plus` snapshots and aliases, and the open-weight `qwen3-vl-*-instruct` models (18 in total).

### Changed

- OpenAI-compatible providers now read Alibaba's used-up free quota code from HTTP 400, 403 and 429 error bodies. Other 403 and 429 responses are reported as before, with no provider text shown.

## [0.1.0] — 2026-11-05

First public release. An early preview: simulator-tested, with hands-on Apple Pencil, VoiceOver and real-provider checks still open (see "Known limitations").

### Added

- **Documents:** canvas and A4 notebook documents saved locally as `.pencilecho` packages, every PencilKit tool, page styles, autosave, undo/redo (tickets 005, 008, 015).
- **Library:** Recent, Favorites, Canvases and Notebooks with counts, title search, sort, grid and list, rename and delete (009, 022, 025).
- **Ask AI:** capture of the newest ink or a selection, validated answers placed beside the work, review when the page changed, manual retry (006, 010).
- **Auto answer** after a pause you choose (1–10 s), answering the newest ink directly (014).
- **Editable answers:** text in a handwriting style, Markdown, LaTeX (SwiftMath), function plots and native ink drawings (011, 016).
- **Pen gestures and context:** circle, box and arrow gestures, "why?"-style labels, and earlier work around the newest ink sent as context (017).
- **Diagram strokes:** arcs, rectangles, wavy and zigzag lines, arrowheads, fills and labels (018). **Precise overlays** in page coordinates with a magnified focus image, for maze paths and marks on existing work (019).
- **Agent chat** in an inspector, using a selection or the visible page, with drafts you accept or discard (021).
- **Providers:** Qwen first; OpenAI, Anthropic, OpenRouter, Gemini, Cerebras, Groq, Hugging Face, Mistral, NVIDIA and custom OpenAI-compatible endpoints; native Anthropic and Gemini adapters; reasoning levels for supported models; keys in the Keychain (007, 012, 013, 020).
- **Claude Code on the Mac** (`pencilecho-mcp`): an MCP bridge over TLS-PSK on the local network with pairing, foreground-only sharing and validated draft placement (023).
- **Design:** one Liquid Glass navigation bar with title menu, Select / Insert / View, Ask AI and answer mode; floating selection bar; inspectors; glass cards; restyled Settings, Chat and Claude Code popover; HIG style guide; Liquid Glass app icon made with Icon Composer (024–027).

### Fixed

- Draft ink from chat and Claude Code was invisible on the canvas (PencilKit doesn't draw strokes dated before 1970); draft markers are now positive.
- Panel titles and Done buttons leaked into the editor's navigation bar.
- Renaming from the editor's title menu didn't apply.

### Known limitations

- Not yet verified on a physical iPad with Apple Pencil, VoiceOver, Split View, or real AI providers and Claude Code; simulator and fixture tests only (258 unit tests, 9 UI journeys).
- Builds signed with a free Apple ID expire after 7 days.
- Interactive widgets, simulations and 3D are not included.

### License

- Licensed under **AGPL-3.0-only**, because Pencil Echo includes code ported from PenEcho (AGPL-3.0-only). The template's MIT placeholder is replaced; see `NOTICE`.

## [0.0.0] — Template initialization

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
