# Pencil Echo technical design

Status: Native local editors/library and editable rich objects implemented; physical and live-provider acceptance gates remain open.

## Scaffold baseline

`application/PencilEcho.xcodeproj` contains the SwiftUI PencilEcho app and hosted PencilEchoTests target. App, DocumentModel (`shared/`) and Services (`service/`) are logical Xcode groups in one module; no project generator is required. Ticket 011 adds the exact-version SwiftMath 1.7.3 package for native math rendering. App, DocumentModel and Services now contain runtime Swift sources; target boundaries remain logical groups. The shell enables multiple windows, iPad-only deployment on iPadOS 27.0 and portrait/landscape orientations. Its home screen is the local document library with New Canvas and New Notebook actions. The canvas and notebook editors (008) are described below; document packages/validation (005/006) and the fixture-verified provider service (007) now have native implementations. A Debug-only ink/object prototype is described below. Scaffold placeholders establish discovery only; see the testing document for native verification evidence.

## Ink/object spike baseline (004)

`application/App/Spike/` contains a Debug-only 4,000 × 4,000 point experiment, reachable from the home Debug menu. It synchronizes a sibling UIKit object layer with PKCanvasView zoom/offset using public APIs, supports whole-stroke/object polygon selection and grouped movement, shares an UndoManager for custom transactions and PencilKit tool sessions, and monitors synthetic-load footprint/display-link cadence. Ink above objects is the provisional z-order recommendation. No persistence or AI is included.

The simulator build, 14 tests and seeded three-zoom render checks passed. Physical touch/Pencil undo, continuous alignment, A16 memory/latency and Owner + Claude review remain open. Ticket 008 builds on this approach before the device review; see [the spike report](../spikes/004-ink-object-layer.md).

## Editor baseline (008)

`application/App/Editor/` holds one editor for both types. One `PKCanvasView` scrolls and zooms; page backgrounds, objects and the selection overlay follow its zoom and offset. Notebook A4 pages stack vertically in one document space (32 pt gap), and ink is split back into page-relative files on save. The canvas grows right/down in 1,000 pt steps up to 20,000 pt. `EditorSession` owns content, the shared `UndoManager` (PencilKit strokes natively, everything else as inverse snapshots), revision and 2-second autosave through `DocumentStore`. A document open in another window opens read-only. See [ticket 008](../../tickets/008-canvas-and-a4-notebook-documents.md) for decisions and pending A16 checks.

## Provider spike baseline (007)

`service/Providers/` contains the Sendable provider/request/event contracts, generic OpenAI-compatible Chat Completions adapter, model/preset quirks, bounded SSE parser, cancellable URLSession delegate transport and HTTPS endpoint-scoped Keychain store. `service/AI/ModelContent.swift` validates and encodes PNG data URLs. `application/App/ProviderDebug/` provides a Debug-only Qwen region/model/key/streaming screen using the bundled equation and command schema. The UI validates the completed answer but does not mutate a document.

Capability/size checks precede credential access and networking. The transport rejects redirects, avoids cache/cookie/URL credential storage, closes on DONE/cancellation, and never retries or fails over automatically. Errors contain no provider message/body. Source files derived from approved upstream material carry provenance headers. See [provider evidence](../api/providers.md); the owner's live Qwen check remains open.

## Architecture intent

SwiftUI navigation/library/settings/chat; UIKit and PencilKit ink surface; separate document object layer for editable text, equations, images, plots and diagrams. Use a common document coordinate system for ink, objects, selection, capture and export. Canvas and A4 notebook share services but retain distinct layout behavior.

Application services run in Swift on the iPad: document repositories, capture, context assembly, AI orchestration, validation, history and exports. No separate backend is required for normal use. Provider inference runs remotely using user credentials. Do not port the reference's Node/Electron server wholesale or require desktop CLI tools.

## Boundaries

- Document model owns IDs, revisions, geometry and source content.
- Ink engine owns PencilKit input/serialization and coordinates with document-level transactions.
- Renderer owns content presentation; web renderer only for approved complex content.
- AI adapter layer owns provider-specific authentication, image encoding, streaming and errors.
- Command validator owns bounded schema checks and explicit mutation authorization.
- MCP shares the same scoped command boundary as internal AI; no privileged bypass.
- Storage owns atomic save, recovery, indexes, history, trash and archives.

## Request lifecycle

Capture immutable request context and target revision → send to selected provider → validate response → check revision → apply one undoable transaction or hold for review. Keep drawing responsive while waiting. Invalid commands produce an actionable error with no partial mutation. Cancellation invalidates later responses. Preserve retry intent on network failure, with manual retry and no silent provider switch. Define request IDs and duplicate suppression before implementation.

## Ink and objects

Use PKCanvasView/PKDrawing for ink; do not flatten editable AI content into ink bitmaps. Prototype shared pan/zoom and lasso across both layers. Large-canvas culling, drawing segmentation, memory limits and stroke selection semantics require measured prototypes. Do not claim unlimited canvas capacity. USB-C Pencil lacks pressure sensitivity; never make pressure required for drawing usability.

## Data and concurrency

Local, versioned editable document packages plus rebuildable library/search indexes; specific storage implementation remains to be selected. Save transactionally and recover interrupted writes. Coordinate multiwindow writes by document revision; never silently overwrite a newer window. Content revision used for AI staleness excludes irrelevant navigation changes. See data model for contracts to finalize.

## Widgets and MCP

Contained WKWebView runtime, default-denied network/native access, narrow validated bridge, no injected credentials, bounded content and active runtime count. Persist widget source and a static fallback; resource/accessibility limits precede implementation. 3D follows physical performance evidence.

Optional paired foreground LAN MCP. Local-network permission and secure authenticated transport must be designed and tested. App backgrounding/locking ends any availability guarantee; clients must reconnect and revalidate sessions. External agents see opted-in documents only. No unrestricted filesystem or command execution.

## Security and evidence

Credentials in Keychain, excluded from document/backup/export/logs. Bound images, archives, object counts and incoming commands. Never execute generated Swift/shell code. Treat generated HTML and imported content as untrusted. Do not log prompts, provider bodies or user drawings by default.

Reference baseline, owner decisions, SDK gate and license/provenance gate: see ../decisions.md. SDK/device compatibility was verified in ticket 001; the deployment minimum is iPadOS 27.0. Tests, native builds, physical acceptance and provider acceptance are separate evidence categories.

## Local library baseline (009)

`application/App/Library/` presents a manifest-backed grid, creates Canvas/Notebook packages, opens the native editor, renames titles and confirms permanent deletion. Library and editors share `AppDocuments.store`; metadata actions and editor loading coordinate through the in-process open-document claim. Closing an editor refreshes the list and derived previews. List rebuilds remain manifest-only; deeper corruption is surfaced on opening.

Rename atomically replaces a cloned package with only its manifest changed, preserving all non-manifest bytes. Thumbnails are derived at editor content-save time from first-page ink/objects and bounded image assets. Dynamic Type uses an adaptive grid, and cards expose combined accessibility labels and Rename/Delete actions. See [library behavior, tests and evidence](../testing/library-009.md). Physical/device and live-provider acceptance remain independent.

A `NavigationSplitView` sidebar adds Recent, Favorites, All Documents, Canvases and Notebooks; AI Settings sits at the sidebar bottom. Favorites and `lastOpenedAt` are optional v1 manifest keys changed through the same atomic package clone as rename, so content revision and edited date stay untouched, and packages without them remain valid. Recent is the last 30 days sorted newest opened first. Search matches titles only; sort keys are last modified, last opened, title and created; list/grid layout and sort are remembered in UserDefaults. See [library navigation verification](../testing/library-022.md).

## Rich answer objects (011)

`application/App/RichText/` owns the Markdown/math splitter, Foundation attributed-text mapping, bounded SwiftMath renderer, zoom-aware object view and multiline source sheet. Markdown and LaTeX retain editable schema-v1 source; Save measures height at the object's width and commits source/frame/revision as one undo action. Width resize reflows content. Rendering errors expose raw source with a warning, and accessibility labels contain complete source. Formula attachments are rebuilt at screen scale × zoom after zoom ends. Thumbnail and AI-region capture paths use the same renderer; AI additions measure height before placement. No render-time network, web content execution or provider call is involved. See [renderer decision, limits, corpus and verification](../testing/rich-text-011.md).

## Native AI protocols (013)

`ProviderFactory` dispatches the settings-resolved preset to OpenAI Chat Completions, Anthropic Messages or Gemini streamGenerateContent. Ask AI and Test connection consume the same `AIProvider` events and fixed errors. The native adapters own their authentication, image blocks, structured-output projection and stream terminal checks; they share the bounded SSE parser and cancellable no-redirect transport. Only successful completed JSON reaches the existing command validator; thinking, blocked, truncated or malformed responses cannot apply an answer. Keys remain bound to preset plus exact effective HTTPS base URL. Native suggested models are static; unknown-model vision is opt-in, and unknown structured output uses prompt-only JSON. See [verified contracts, bounds and live acceptance status](../api/providers.md#native-anthropic-and-gemini-adapters--ticket-013).

## Editor shell (020)

`AskAIEditorContainer` owns the navigation top bar, a scrollable edge-movable AI toolbar and a mutually exclusive trailing panel area. Regular width embeds AI Settings beside the canvas; compact width presents the same settings as a sheet. The top bar reads observable session save state and AI lifecycle status. Apple PKToolPicker remains the drawing tool UI. Fullscreen hides app bars, and Hand mode disables PencilKit drawing while retaining scroll/zoom. Settings retain provider/model connections, AI answer font/color, Auto Ask delay and thinking indicator preferences. PNG sharing uses a native activity sheet. See [verification](../testing/editor-shell-and-chat-020-021.md).

## Typed agent chat (021)

`AgentChatController` captures current selection/viewport using AskAIController's page clipping and fingerprints. It sends bounded text-only history plus one current PNG to the common provider interface. `AgentChatView` streams only the top-level reply message. The completed response passes CommandValidator, staleness and additive-only checks before AnswerApplier generates one draft snapshot. Object flags and per-batch PencilKit path markers support editable dashed drafts and unified accept/discard undo. Local optional `chat.json` retains 10 turns; current images and raw reasoning remain transient. Chat and settings occupy the same adaptive panel. Auto Ask pauses while the chat panel/request is active, and manual request paths cannot overlap. Physical incline-diagram quality and real-provider follow-up acceptance remain owner gates.
