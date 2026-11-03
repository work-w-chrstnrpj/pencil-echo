# Pencil Echo feasibility assessment

Status: ASSESSMENT — 2026-11-03. Based on the docs in `docs/`, the reference clone in `inspiration/` (commit `076c1ad`) and a read-only inspection of the local toolchain. No code was written or built.

## Verdict

**Feasible, with conditions.** The core loop is buildable with public Apple APIs on the owner's A16: handwrite a problem, send it to an AI provider, and place an editable answer beside it. The docs are well gated. The risks are mostly about **scope and licensing**, not missing platform capability.

Conditions:

1. ~~Resolve the name and license before publishing.~~ **Owner decision 2026-11-03:** project stays private and experimental; copying from `inspiration/` is approved. Name/license only matter again if it is ever shared.
2. Treat the **PencilKit + editable object layer** as the main technical risk. Prototype it first in PE-000.
3. Accept that the full plan (PE-000 to PE-007) is a multi-quarter effort for a single developer working with an AI coding agent. Commit only to PE-000 to PE-002 as the first release.

## Gate 1 — toolchain and device (mostly resolved)

| Item | Finding |
|---|---|
| Xcode | 27.0 (27A266a) at `/Applications/Xcode.app`; the shell still points at CommandLineTools, so use `DEVELOPER_DIR` per command or have the owner run `xcode-select` |
| SDKs | `iphoneos27.0` and `iphonesimulator27.0` are installed |
| Simulator | "iPad (A16)" iOS 27.0 simulator is available |
| Physical device | "iPad ni Paj", iPadOS **27.0.1**, has been paired before (currently offline). Chip ID 8120 matches A16 |
| Compatibility | The 27.0 SDK can build for and deploy to a 27.0.1 device |
| Open | Signing team. A free Apple ID gives 7-day provisioning and limits some entitlements; a paid developer account gives one year. Bundle ID and deployment target are still to choose |

Recommendation: set the deployment target to **iPadOS 27.0**. Since the app is personal-install only, there's no reason to support older OS versions, and this unlocks the newest PencilKit and SwiftUI APIs.

## Blockers (non-technical)

### 1. Name / trademark — high

Upstream `TRADEMARKS.md` requires forks to use a "distinct product name and visual identity" and forbids "a confusingly similar variation". **"Pencil Echo" / "penecho-ipados" is arguably confusingly similar to "PenEcho".** That's fine for private use, but it's a real risk once the source or a build is public. Pick a distinct name before you publish (the docs already require "distinct Pencil Echo branding", which doesn't solve this).

### 2. License — high

Upstream is **AGPL-3.0-only** (with an optional commercial license). Porting its logic to Swift, including prompts, scene contracts, diagram schemas or layout code, creates a derivative work. Choose one path:

- **A. AGPL-3.0 for Pencil Echo.** This is simple and compatible with an open-source personal app. Note that AGPL/GPL software is widely considered incompatible with App Store terms, which matters only if you later distribute through the App Store or TestFlight.
- **B. Clean-room / ideas only.** Use upstream as product inspiration only, copy no code, prompts or schemas, and pick any license. This needs discipline: Codex must not translate files from `inspiration/`.

The MIT-licensed vendored pieces upstream (Archify helpers, anime.js, matter-js, Zdog, three.js) and the EPL-2.0 elkjs can be reused under their own terms on either path.

**Recommendation:** decide now. Make it an explicit instruction to Codex, because "port X from inspiration/" is the default thing an agent will do.

## Technical feasibility by capability

| Capability | Feasibility | Notes / risk |
|---|---|---|
| Pencil-only ink, eraser | High | `PKCanvasView.drawingPolicy = .pencilOnly`; the USB-C Pencil has no pressure, but PencilKit handles that |
| Canvas + multipage A4 notebook | High / Medium | A4 is easy as one `PKCanvasView` per page or a paged layout. An infinite canvas needs tiling/segmentation, and memory has to be measured on the A16 |
| Editable object layer (text, LaTeX, images, plots, diagrams) synced with ink zoom/pan | **Medium — main risk** | PencilKit has no object layer. You must overlay UIKit views on the canvas's scroll view, keep their transforms in sync, and decide z-order (ink above or below objects). Prototype this first |
| Mixed lasso (ink + objects) | Medium-Low | `PKLassoTool` selects strokes only. Mixed selection needs a custom lasso: hit-test `PKStroke` paths and object frames yourself, then move both together |
| Unified undo | Medium | `PKCanvasView` registers on its own `undoManager`. Route ink and object changes through one document-level transaction manager. Grouping an AI insert as one step is doable |
| Custom tools in the tool picker | High | `PKToolPickerCustomItem` is in the iOS 27 SDK (good for an "Ask AI" lasso tool) |
| Handwriting to AI | High | Render the lasso region to PNG and send it to a vision model. No on-device math OCR is needed |
| Handwriting search | Medium | No public PencilKit text-recognition API. Use Vision `VNRecognizeTextRequest` on rendered tiles. English handwriting quality is acceptable but imperfect, which matches the docs' "not fully searchable" caveat |
| On-device suggestions | **Low on A16** | `FoundationModels` (Apple Intelligence) is in the SDK, but Apple Intelligence requires A17 Pro / M-series. **The A16 iPad can't run it.** So suggestions need either a paid provider call, which needs the consent/cost spec the product spec already asks for, or cheap heuristics such as idle time and stroke count |
| 10 providers (Qwen first; OpenAI, Anthropic, OpenRouter, Gemini, Cerebras, Groq, Hugging Face, Mistral, NVIDIA) | High | Plain `URLSession` + SSE. Eight are OpenAI-compatible, so one adapter + presets; Anthropic and Gemini get native adapters. Vision support varies per model, so gate handwriting requests on a vision-capable model. Structured output differs by provider (JSON schema, tool use, `responseSchema`), so keep one validator with per-provider adapters, as planned. Custom endpoint: OpenAI-compatible only at first |
| Keychain storage of keys | High | Standard |
| Formula rendering | High | Native LaTeX rendering (e.g. SwiftMath, MIT) or KaTeX in a `WKWebView` snapshot. Native is better for performance and editing |
| Editable architecture/sequence/workflow diagrams | Medium | Upstream uses elkjs for layout. On iOS you can run elkjs in `JavaScriptCore` (EPL-2.0) or write a simpler native layered layout. Node/connector editing is custom UI work and a sizable chunk |
| Local versioned documents, autosave, history, trash, backup | High | `UIDocument`/`FileWrapper` package with JSON + `PKDrawing.dataRepresentation()` + assets. SwiftData is fine for the derived library index only |
| Multi-window same-document edits | Medium | Needs the revision-based coordination in the TDD. Consider one writable window per document for v1 |
| PDF import as notebook background, PDF/PNG export | High | PDFKit + `PKDrawing.image(from:scale:)` |
| LAN MCP server (foreground) | Medium | `Network.framework` `NWListener` + MCP Streamable HTTP + Bonjour + local-network permission all work while the app is in the foreground. Hard part: secure transport. TLS with a self-signed cert is awkward for Codex/Claude Code/Cursor clients, and a bearer token over plain HTTP on the LAN is the realistic v1 (pairing code → token). iPadOS will suspend the server when the app is backgrounded or the screen locks, as the docs already state |
| Sandboxed widgets | High / Medium | `WKWebView` + `WKContentRuleList` to block network + a narrow `WKScriptMessageHandler` bridge. Resource limits per runtime need testing |
| 3D | Medium | Three.js in a WebView on the A16 is OK for small scenes. Keep it gated, as planned |
| Accessibility (VoiceOver, Dynamic Type) on a canvas | Medium | The object layer can be accessible. Ink needs accessible summaries. This is real work, usually underestimated |

## Scope and effort (rough, solo + AI agent)

| Milestone | Relative size | Comment |
|---|---|---|
| PE-000 Feasibility prototypes and contracts | S–M | Highest-value step. The ink/object/lasso/undo prototype decides the architecture |
| PE-001 Drawing and documents | M | |
| PE-002 Manual AI solving (10 providers) | M | Start with **one** provider end to end, then add the others |
| PE-003 Lasso AI, chat, diagrams | L | Diagram editing is the big item |
| PE-004 Library and portability | L | Many small features: search, cards, trash, history, backup |
| PE-005 Suggestions and MCP | M–L | Three-client verification |
| PE-006 / PE-007 Widgets, 3D | L | |

The upstream reference is about 80k lines of JS. Matching its feature set natively is a large project. A realistic first usable release is **PE-000 to PE-002**.

## Doc gaps to fix before coding

1. Gate 1 can now be recorded: Xcode 27.0, SDK 27.0, device 27.0.1, A16 simulator available.
2. Make the **license path (A or B)** and the **product name** owner decisions in `docs/decisions.md`.
3. Note that A16 can't run Apple Intelligence / FoundationModels, then decide how suggestions are generated and paid for.
4. ~~Pick a first provider.~~ Owner decision 2026-11-03: Qwen first.
5. Specify the MCP v1 auth model (pairing code → bearer token over LAN HTTP, or TLS) as an explicit security decision.
6. Decide z-order and the lasso model for mixed ink/objects as a PE-000 prototype acceptance criterion.
7. Choose single-writer vs. multi-writer windows for v1.

## Working with Codex (mid-level developer)

Codex is good at well-specified tickets. It's weaker at open-ended architecture on platform APIs where behaviour has to be measured on hardware. Suggested split:

- **Owner + Claude:** PE-000 decisions, schemas, ticket breakdown, review of the ink/object prototype, security-sensitive design (Keychain, MCP pairing, widget sandbox).
- **Codex:** implement tickets with explicit scope, exclusions, files and acceptance, e.g. "provider adapter for Anthropic Messages API with SSE parsing + unit tests against fixtures", "document package read/write with atomic save + tests".
- **Rules to give Codex:** don't translate code from `inspiration/` unless the license decision allows it. Don't change global `xcode-select`. Build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... -destination 'platform=iOS Simulator,name=iPad (A16)'`. Never claim device acceptance.

## Recommended next step

Split PE-000 into 4–5 tickets:

1. Xcode project scaffold.
2. Ink/object layer spike with mixed lasso and unified undo, measured on the A16.
3. Document package schema v1.
4. One provider adapter spike.
5. License/name decision record.

Then hand tickets 1, 3 and 4 to Codex while the spike (ticket 2) is reviewed closely.
