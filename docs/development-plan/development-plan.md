# Development plan

Status: IN PROGRESS. PE-000 started with resolved toolchain facts (001) and the native scaffold (002); remaining feasibility gates are open; no target date. Dependencies are sequential unless a ticket explicitly establishes independence.

| ID | Milestone | Dependency | Acceptance and verification | Status |
|---|---|---|---|---|
| PE-000 | Feasibility and implementation contracts | None | Verify SDK/device OS; prototype PencilKit/object coordinates; define storage schema, limits, commands and license inventory | in progress (001/002 resolved; 004 simulator verified, device/review pending) |
| PE-001 | Local drawing and documents | PE-000 | Canvas/A4, Pencil-only drawing, lasso, undo, autosave/reopen; physical A16 verification | in progress (008 simulator verified, 009 library/editor integration verified; A16 pending) |
| PE-002 | Manual AI solving | PE-001 | Provider adapters for Qwen first, then the other nine selected providers; editable placed answer, undo, stale review, offline/manual retry; primary device gate | in progress (011 simulator verified; 013 native adapters fixture-verified; owner provider/hardware gates open) |
| PE-003 | Lasso AI, chat and diagrams | PE-002 | Scoped captures, conversation, direct node/connector edits and AI refinement; integration/device tests | pending |
| PE-004 | Library and portability | PE-003 | Folders/tags/search/bookmarks/cards, PDF/image import, exports, trash/history and archive restore; failure/recovery checks | pending |
| PE-005 | Automatic modes and MCP | PE-004 | Opt-in tapped suggestions, later auto solve; paired foreground LAN; separate Codex/Claude Code/Cursor evidence | pending |
| PE-006 | Widgets and simulations | PE-005 | Offline contained widgets/quizzes/simulations, permissions, lifecycle/resource/accessibility tests | pending |
| PE-007 | Optional 3D and deferred portability | PE-006 | Passing A16 prototype before 3D; SVG/Markdown fidelity and optional Files backups separately scoped | pending |

Suggestion popups are confirmed product scope; delivery is in PE-005 so the initial manual solving loop can be accepted first. Each milestone must include accessibility, persistence and regressions relevant to the behavior it adds.

Before coding, split milestones into tickets with exact scope/exclusions, affected areas, dependencies, acceptance, automated checks, device/provider gates and stop conditions. Roles are owners of work, not authorization to spawn parallel agents. Do not mark a milestone done from a build alone.

## Tickets

Ticket 002 is resolved (2026-11-03): simulator build, three placeholder tests and visual launch check passed. It establishes the native shell and placeholder tests only. It does not complete PE-000 or establish drawing, persistence, provider or owner acceptance.

Ticket 004 has an implemented Debug-only prototype with 14 passing tests, three zoom screenshots and a simulator stress observation. Physical A16/Pencil checks and Owner + Claude review remain pending; ticket 004 and gate 2 stay open. See `docs/spikes/004-ink-object-layer.md`.

Ticket 007 has an implemented generic provider and Qwen Debug screen. The full simulator suite passed 83 tests and Debug/Release builds passed. Owner real Qwen vision acceptance remains pending; ticket 007 and provider gate 4 stay open. See `docs/api/providers.md`.

Ticket files live in `tickets/`. Owner decisions: signing with a free Apple ID Personal Team and bundle ID `com.chrixcrusher.pencilecho` (001, resolved 2026-11-03); first AI provider Qwen (007).

| Ticket | Milestone | Owner | Depends on |
|---|---|---|---|
| [001 Record toolchain, device and signing](../../tickets/001-record-toolchain-and-device.md) | PE-000 | Owner + Claude | — |
| [002 Xcode project scaffold](../../tickets/002-xcode-project-scaffold.md) | PE-000 | Codex | 001 |
| [003 Upstream reuse inventory](../../tickets/003-upstream-reuse-inventory.md) | PE-000 | Claude | — |
| [004 Ink + object layer spike](../../tickets/004-ink-object-layer-spike.md) | PE-000 | Codex, reviewed | 002 |
| [005 Document package schema v1](../../tickets/005-document-package-schema-v1.md) | PE-000 | Claude (spec + implementation; resolved) | 002 |
| [006 AI command schema v1](../../tickets/006-ai-command-schema-v1.md) | PE-000 | Claude (spec + implementation; resolved) | 003 |
| [007 OpenAI-compatible adapter, Qwen first](../../tickets/007-first-provider-adapter-spike.md) | PE-000 | Codex | 002, 006 |
| [008 Canvas and A4 notebook editors](../../tickets/008-canvas-and-a4-notebook-documents.md) | PE-001 | Claude (simulator verified; A16 pending) | 004, 005 |
| [009 Basic document library](../../tickets/009-basic-document-library.md) | PE-001 | Claude (initial library), Codex (integration/verification); resolved on simulator | 005; 008 editor handoff |
| [010 Ask AI flow](../../tickets/010-ask-ai-flow.md) | PE-002 | Claude (in progress: owner A16 + real provider pending) | 004, 006, 007, 008 |
| [011 Markdown and LaTeX objects](../../tickets/011-editable-markdown-and-latex-objects.md) | PE-002 | Codex (resolved on simulator; physical acceptance pending) | 004; 008 integration |
| [012 OpenAI-compatible presets and settings](../../tickets/012-openai-compatible-providers-and-settings.md) | PE-002 | Claude (in progress: owner real-provider runs pending) | 007 |
| [013 Anthropic and Gemini native adapters](../../tickets/013-anthropic-and-gemini-native-adapters.md) | PE-002 | Codex (implemented and fixture-verified; owner live acceptance pending) | 007, 012 |

Ticket 009's library now opens the native editor, preserves package bytes during atomic rename, guards metadata operations on open documents, refreshes thumbnails and has two isolated simulator UI journeys. [The library report](../testing/library-009.md) records final check results and screenshots. These results do not close PE-001's physical A16/Pencil/VoiceOver acceptance or ticket 004's hardware review.

Ticket 011 adds native editable Markdown/LaTeX objects and a live source editor. Its 30-expression corpus, persistence, undo/reflow and 4× zoom checks passed on simulator; the full hosted suite passed 167 tests. [Renderer evidence and limits](../testing/rich-text-011.md) retain the source-preserving fallback policy and separate physical acceptance gate.

Ticket 013 (2026-11-04) adds native Anthropic Messages and Gemini streaming adapters, selected through the existing settings and common Ask AI interface. The full hosted suite passed 181 tests in 14 suites; both providers remain **not verified** with owner keys. Current official contracts, protocol differences, synthetic fixture evidence and manual acceptance steps are in [providers.md](../api/providers.md#native-anthropic-and-gemini-adapters--ticket-013).
