# Project structure

Status: Native scaffold, local package/validator services and the Debug 004/007 prototypes implemented; physical spike and live-provider acceptance remain pending.

| Path | Responsibility |
|---|---|
| application/PencilEcho.xcodeproj/ | Checked-in native project and shared PencilEcho / PencilEchoLibraryUI schemes; app, hosted PencilEchoTests and PencilEchoUITests targets |
| application/App/ | SwiftUI entry point, library HomeView and Info.plist scene/orientation configuration |
| application/App/Editor/ | Canvas and A4 notebook editor (ticket 008): `EditorLayout` page geometry and lasso hit-testing, `EditorSession` content/undo/revision/autosave, `PageBackgroundView`, `DocumentEditorController` and the SwiftUI `DocumentEditorScreen` |
| application/App/RichText/ | Markdown/math splitter, native attributed-text/SwiftMath rendering, zoom-aware views and editable source sheet (011) |
| application/App/Settings/ | AI provider settings screen (012), native protocol selection/Test connection (013) |
| application/App/AskAI/ | Ask AI controller, capture, placement/apply and editor overlay (ticket 010) |
| application/App/Library/ | Document grid/native editor handoff, `LibraryModel` and bounded `ThumbnailRenderer` (009) |
| application/App/Spike/ | Debug-only PencilKit/UIView experiment: geometry, synthetic fixtures/history, controller/SwiftUI bridge and memory/frame monitor |
| service/ | Services logical group; in-process persistence/orchestration/provider code |
| application/App/ProviderDebug/ | Debug-only Qwen region/model, masked key entry, bundled-image streaming and v1 validation |
| application/App/Resources/ | Synthetic handwritten equation PNG and bundled third-party MIT notice; the project also bundles shared/schemas/canvas-commands-v1.json |
| service/Providers/ | OpenAI-compatible plus native Anthropic/Gemini adapters, ProviderFactory/shared native validation and runner, preset/capability data, bounded SSE, URLSession transport and Keychain store |
| service/AI/ | PNG image validation/data URL encoding |
| service/Persistence/ | `DocumentStore`: atomic package save, read-only load, list, create, delete (ticket 005) |
| shared/ | DocumentModel logical group; future IDs/geometry/schema types |
| shared/Document/ | Document package v1 `Codable` types and `DocumentMigrator` (ticket 005) |
| shared/CanvasCommands/ | AI answer types and pure `CommandValidator` (ticket 006) |
| shared/schemas/ | `canvas-commands-v1.json`, the provider JSON Schema for AI answers (ticket 006). Bundled by the app target for the provider request/Debug screen (ticket 007) |
| tests/PencilEchoTests/ | Scaffold, spike, document-store, command-validator and provider/Keychain/transport tests; latest results are recorded in docs/testing/library-009.md |
| tests/PencilEchoUITests/ | Debug-only library and rich-source journeys using isolated temporary libraries and persisted relaunch state |
| tests/evidence/009/ | Library relaunch and accessibility XXXL/damaged-package screenshots |
| docs/testing/library-009.md | Current library behavior, package-preservation rules, verification commands and limitations |
| tests/fixtures/documents/ | Checked-in v1 document packages for `DocumentStoreTests` and the `generate-fixtures.swift` script that writes them (ticket 005) |
| tests/fixtures/latex/ | 30-expression native math corpus (011) |
| tests/evidence/011/ | Rich source/preview, corpus and 4× render evidence |
| tests/fixtures/providers/ | Synthetic OpenAI/Anthropic/Gemini SSE/status/safety fixtures and handwritten-image generator; copied into the test bundle |
| tests/evidence/007/ | Visually inspected Qwen Debug screen without credentials |
| docs/api/providers.md | Implemented provider contract, current official evidence, test limits and pending owner verification |
| tests/evidence/002/ | Visually inspected portrait simulator screenshot for the scaffold |
| tests/evidence/004/ | Three zooms, alternate z-order and synthetic stress simulator screenshots |
| docs/spikes/004-ink-object-layer.md | Prototype decisions, evidence, limits and physical acceptance procedure |
| docs/ | Product/technical intent, decisions, milestones and verification |
| inspiration/ | Separate upstream PenEcho clone, pinned discovery baseline; reference/reuse source |
| .agents/ and .ai/ | Canonical reusable AI guidance and discovery maps |
| bin/, lib/, scripts/, package.json | Copied AI-template tooling, not application runtime |

The Xcode project uses logical App, DocumentModel and Services groups with a single app module. No local package or project generator is needed for the shell; separate targets can follow a demonstrated dependency need. Swift files added to shared/service later must be explicitly added to app target membership. The hosted test target imports PencilEcho with `@testable`; its scaffold tests establish discovery, and its Debug-only spike tests exercise geometry/transactions and the lasso handler. They do not establish physical touch/Pencil acceptance.

No upstream code or assets were copied for tickets 002 or 004. Ticket 007 derives presets/stream accumulation/image content handling from approved upstream paths, with provenance headers; its SSE framer and synthetic PNG are original. Keep upstream reference changes isolated from app delivery and record provenance for future reused material.
