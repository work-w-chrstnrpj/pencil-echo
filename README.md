# Pencil Echo

An open-source, native Swift iPad app based on the PenEcho reference in `inspiration/`.

Write a problem with Apple Pencil, ask AI to solve or explain it, and receive an editable answer on the board. Documents stay local without an account; AI requests use the user's configured provider and API key.

## Current state

Ticket 002 adds a native SwiftUI iPad scaffold, the shared PencilEcho build scheme and three unit-test placeholders. The home screen is now a local document grid: New Canvas/New Notebook create saved documents and open the native editor. Long-press items to rename or confirm permanent deletion; trash is not available yet. See [library behavior and evidence](docs/testing/library-009.md). Ticket 004 adds a Debug-only PencilKit/object-layer experiment with lasso/move, undo and synthetic-load monitoring; [simulator evidence and pending device checks](docs/spikes/004-ink-object-layer.md) are recorded separately. Native document storage/command validation (005/006) and a generic provider service with a Qwen Debug screen (007) are implemented; [real-provider acceptance](docs/api/providers.md) and the integrated physical-device workflow remain pending. Ticket 011 adds editable native Markdown and LaTeX objects with a live source preview, one-step edit undo, automatic height and zoom rendering; see [renderer limits and evidence](docs/testing/rich-text-011.md). Ticket 013 adds native Anthropic/Gemini streaming through the AI Settings provider picker, with synthetic fixture verification; live requests remain [not verified](docs/api/providers.md#native-anthropic-and-gemini-adapters--ticket-013). The root Node package and scripts belong to the copied AI template, not the iPad runtime. The workspace root is not currently a Git repository; `inspiration/` is a separate cloned repository.

Initial acceptance device: iPad A16 with Apple Pencil USB-C, verified iPadOS 27.0.1 (24A446). Xcode 27.0 / iPadOS 27.0 SDK compatibility is recorded in ticket 001. Open `application/PencilEcho.xcodeproj` to develop the app; see [native verification commands](docs/testing/test-specification.md).

## Documentation

- [Product requirements](docs/product-specification/product-specification.md)
- [Technical intent](docs/tdd/tdd.md)
- [Milestones and acceptance](docs/development-plan/development-plan.md)
- [Decision record and open gates](docs/decisions.md)
- [Project structure](docs/project-structure/project-structure.md)
- [Testing](docs/testing/test-specification.md)
- [Deployment](docs/deployment/deployment.md)

## Reference and reuse

Reference baseline: `inspiration/` commit `341e34d6cf2965ac8f58d0d89cf33e285ace9b2d` (upstream main, package version 1.4.2, updated 2026-11-03). Later upstream changes require deliberate review. Desktop file compatibility is not a requirement. The owner has approved copying and porting upstream code/assets because this project is private and experimental (see `docs/decisions.md`); retain provenance and applicable notices. Use distinct Pencil Echo branding; review upstream `LICENSE`, `NOTICE`, and `TRADEMARKS.md` before incorporating material. The copied template's MIT license/package metadata does not establish licensing for an upstream-derived application.
