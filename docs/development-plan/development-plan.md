# Development plan

Status: IN PROGRESS. PE-000 started with resolved toolchain facts (001) and the native scaffold (002); remaining feasibility gates are open; no target date. Dependencies are sequential unless a ticket explicitly establishes independence.

| ID | Milestone | Dependency | Acceptance and verification | Status |
|---|---|---|---|---|
| PE-000 | Feasibility and implementation contracts | None | Verify SDK/device OS; prototype PencilKit/object coordinates; define storage schema, limits, commands and license inventory | in progress (001/002 resolved; 004 simulator verified, device/review pending) |
| PE-001 | Local drawing and documents | PE-000 | Canvas/A4, Pencil-only drawing, lasso, undo, autosave/reopen; physical A16 verification | in progress (008 simulator verified, 009 library/editor integration verified; A16 pending) |
| PE-002 | Manual AI solving | PE-001 | Provider adapters for Qwen first, then the other nine selected providers; editable placed answer, undo, stale review, offline/manual retry; primary device gate | in progress (011 simulator verified; 013 native adapters fixture-verified; owner provider/hardware gates open) |
| PE-003 | Lasso AI, chat and diagrams | PE-002 | Scoped captures, conversation, direct node/connector edits and AI refinement; integration/device tests | in progress (021 implemented; native checks/builds verified; simulator runtime and A16/provider gates open) |
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
| [014 Auto Ask on pause and inline answers](../../tickets/014-auto-ask-on-pause-and-inline-answers.md) | PE-002 | Claude (simulator verified; owner A16 + real provider pending) | 010 |
| [015 Full PencilKit tool set](../../tickets/015-full-pencilkit-tool-set.md) | PE-001 | Claude (simulator verified; owner A16 pending) | 008 |
| [016 Visual answers: plots and drawings](../../tickets/016-visual-answers-plots-and-drawings.md) | PE-003 | Claude (fixture-tested, installed on A16; real provider pending) | 006, 010, 014 |
| [017 Pen gestures and context capture](../../tickets/017-pen-gestures-and-context-capture.md) | PE-003 | Claude (implemented and unit-tested; owner A16 + real provider pending) | 010, 014 |
| [018 Diagram drawing primitives](../../tickets/018-diagram-drawing-primitives.md) | PE-003 | Grok (fixture-tested on simulator; owner A16 + real provider pending) | 016 |
| [019 Precise ink on existing work](../../tickets/019-precise-ink-on-existing-work.md) | PE-003 | Grok (fixture-tested on simulator; owner A16 + real provider pending) | 016, 017 |
| [020 Editor top bar, AI toolbar and settings panel](../../tickets/020-editor-shell-and-ai-toolbar.md) | PE-002 | Codex (implemented; native checks/builds verified; simulator runtime and owner gates open) | 008, 010, 012, 014, 015 |
| [021 Agent chat panel](../../tickets/021-agent-chat-panel.md) | PE-003 | Codex (implemented after editor shell; native checks/builds verified; simulator runtime and owner live gates open) | 010, 016, 017, 020 |
| [022 Library navigation sidebar](../../tickets/022-library-navigation-sidebar.md) | PE-004 | OpenCode (open) | 009 |
| [023 LAN MCP for Claude Code](../../tickets/023-lan-mcp-for-claude-code.md) | PE-005 (moved earlier) | Claude (simulator end-to-end verified; owner A16 + Claude Code pending) | 017, 018, 019, 021 |


### Agent assignments for 017–022 (2026-11-04)

Assigned by fit with each agent's strengths. Claude reviews every PR before merge.

| Agent | Tickets | Why this fit |
|---|---|---|
| Codex | 020, then 021 | Largest multi-file Swift work across the editor, settings, all three provider adapters and UI tests. Codex already built the adapters (007, 013) and the rich-text editor (011). 021 builds on 020's panel, so one owner avoids conflicts. |
| Grok | 018, then 019 | Geometry and math heavy work: arcs, wave and zigzag expansion, arrowheads, coordinate mapping and validator limits, plus prompt rules for physics diagrams and maze paths. Mostly in `shared/CanvasCommands/` with clear fixture tests. |
| OpenCode | 022 | Self-contained library work that follows existing `LibraryView` and `DocumentStore` patterns, with clear UI-test acceptance and no AI or provider code. |
| Claude | 017, plus review of 018–022 | Ports the upstream gesture and context prompt rules (provenance per ticket 003) in the Ask AI code Claude wrote for 010, 014 and 016. 019 and 021 depend on it. |

**Order.** Start 017, 018, 020 and 022 at the same time. Start 019 after 017 merges, and 021 after 017 and 020 merge.

**Shared files.** Each agent works on its own branch; merge one PR at a time.

- `service/AI/CanvasCommandPrompt.swift`: 017 merges first; 018 rebases and adds only its draw-ink rules.
- `application/App/AskAI/`: 017 owns the capture code; 020 changes only `AskAIOverlay.swift` and the status hooks.
- `docs/database/document-schema-v1.md` and `shared/Document/`: 020 (grid flag), 022 (favorite, last opened) and 021 (chat history) each add separate optional fields; merge in that order and rebase.
- 022's favorite button in the editor top bar waits for 020; until then 022 ships the library context menu only.

Ticket 009's library now opens the native editor, preserves package bytes during atomic rename, guards metadata operations on open documents, refreshes thumbnails and has two isolated simulator UI journeys. [The library report](../testing/library-009.md) records final check results and screenshots. These results do not close PE-001's physical A16/Pencil/VoiceOver acceptance or ticket 004's hardware review.

Ticket 011 adds native editable Markdown/LaTeX objects and a live source editor. Its 30-expression corpus, persistence, undo/reflow and 4× zoom checks passed on simulator; the full hosted suite passed 167 tests. [Renderer evidence and limits](../testing/rich-text-011.md) retain the source-preserving fallback policy and separate physical acceptance gate.

Ticket 013 (2026-11-04) adds native Anthropic Messages and Gemini streaming adapters, selected through the existing settings and common Ask AI interface. The full hosted suite passed 181 tests in 14 suites; both providers remain **not verified** with owner keys. Current official contracts, protocol differences, synthetic fixture evidence and manual acceptance steps are in [providers.md](../api/providers.md#native-anthropic-and-gemini-adapters--ticket-013).

Tickets 018 and 019 (2026-11-05) add version 3 diagram strokes, labels, a magnified focus image and page-coordinate ink. Targeted simulator runs passed; the capture grid was not added. Real-provider and physical A16 acceptance remain open. Evidence is in [diagrams-018-019.md](../testing/diagrams-018-019.md).
