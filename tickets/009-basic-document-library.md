# 009 — Basic document library

Milestone: PE-001 · Status: Resolved (2026-11-03) · Owner: Claude (initial library) + Codex (editor integration and regression verification) · Depends on: 005 (008 for opening editors)

## What

A minimal SwiftUI library screen: list, create, open, rename and delete documents.

## Why

Needed to create and reopen documents for the first acceptance gate. Full library features (folders, tags, search, cards, trash) are PE-004.

## Scope

- Grid of documents with title, type icon, updated date and a thumbnail (rendered from ink + objects at save time, stored as `thumbnail.png` in the package; defined in `docs/database/document-schema-v1.md`).
- New Canvas / New Notebook buttons.
- Rename (inline or sheet), delete with confirmation (hard delete is acceptable in v1; note it until trash exists in PE-004).
- Sort by updated date.
- Documents stored in the app's Documents directory; listing rebuilds from packages on disk (no separate database).

## Exclusions

Folders, tags, search, bookmarks, trash, import/export, iCloud.

## Acceptance

- [x] Create, rename, delete and reopen work; list survives app relaunch.
- [x] A corrupt package shows as "Can't open" without crashing the library.
- [x] Dynamic Type and VoiceOver labels on library items.
- [x] Tests for listing and rename/delete in `DocumentStore`.

## Implementation evidence — 2026-11-03 (Claude)

- `application/App/Library/LibraryView.swift`: the library screen.
  - A grid of thumbnail, title, type icon and updated date, newest first. Packages that can't be opened sort last.
  - New Canvas and New Notebook buttons in the toolbar and in the empty state.
  - Long-press menu with Rename (a sheet) and Delete (confirmation alert; a hard delete until PE-004 trash).
  - Damaged and newer-version documents show "Can't open" or "Needs a newer Pencil Echo".
  - The list refreshes when the window becomes active.
  - `HomeView` now hosts the library. The Debug menu moved to the bottom-right so it no longer covers the toolbar.
- `application/App/Library/LibraryModel.swift`: `@Observable` state over `DocumentStore`. Error text never includes document content.
- `application/App/Library/ThumbnailRenderer.swift`: renders `thumbnail.png` from the first page (ink above objects, long edge ≤ 512 px; canvases crop to their content). The editor calls it before each save (ticket 008).
- `DocumentStore` gained `rename(id:to:)`, which changes the title only and keeps the revision, and `deletePackage(at:)`, which also removes damaged packages and refuses paths outside the store root.
- Accessibility: one VoiceOver element per cell ("title, type, edited date" or the "Can't open" reason), with Rename and Delete as accessibility actions. Fonts and the cell width scale with Dynamic Type (`@ScaledMetric`).
- Tests: `tests/PencilEchoTests/LibraryTests.swift` (store rename/delete/listing, model create/rename/delete/errors, thumbnail size and format). `DocumentStoreTests` and `LibraryTests` now delete their temp folders. On `iPad (A16)` / iOS 27.0, `CommandValidatorTests`, `DocumentStoreTests` and `LibraryTests` passed: 58 tests.
- Simulator UI check: created a canvas, opened it (placeholder until 008), renamed it to "Geometry sketches", saw the damaged fixture as "Can't open" (tapping it explains why), and deleted it, which removed the package from disk. Screenshot: `tests/evidence/009/library.png`.
  - Two SwiftUI presentation bugs were found and fixed here. Chained alerts on one view dropped the rename alert, so rename became a sheet. A `confirmationDialog` opened from a closing context menu never appeared, so delete uses an alert.
- Not checked: Dynamic Type at the largest sizes, VoiceOver on a device, and the owner A16 run.
- Handoff: ticket 008 (another session) owns the switch from the placeholder to the real editor, the shared `AppDocuments.store`, and the open-elsewhere checks in `LibraryModel`. It had started editing these files before this ticket closed. The full suite had 5 failures in its in-progress `EditorSessionTests`, which are not part of 009.


## Editor handoff and regression follow-through — 2026-11-03 (Codex)

Completed the existing implementation rather than replacing it. The library now opens `DocumentEditorScreen` instead of the placeholder, shares `AppDocuments.store`, and refreshes after editor dismissal. Done follows the editor's save/error flow; swipe dismissal is disabled. Rename/delete acquire the open-document claim, and editor loading acquires its claim before awaiting disk access. A failed load releases it.

Rename is now a metadata-only atomic package clone/swap, preserving unreadable optional files, original ink and unknown files byte-for-byte. Manifest/package identity mismatches are listed as damaged. Required-file damage is detected on tap and shown as “Can't open.” Equal-date ordering is deterministic.

Thumbnail rendering now uses actual image assets (pending or stored), bounded ImageIO decoding and guarded geometry. Visible thumbnails reload on every refresh, even without an updated-date change; cancelled reads cannot replace a newer result. The adaptive grid fits the available width at large accessibility text sizes. The delete alert captures its target independently of SwiftUI clearing the presentation binding.

`LibraryTests` now has 19 tests, covering fresh-store/model relaunch, metadata preservation/interrupted rename, identity/corruption handling, open-editor guards, 500-package ordering, image previews and an actual editor-save thumbnail. The PencilEchoLibraryUI scheme includes two Debug-only `PencilEchoUITests` journeys covering create/rename/open/process relaunch, cancelling/confirming deletion, and a damaged package at accessibility XXXL. Every UI journey uses a unique temporary library; it never deletes or modifies owner documents. See [the library report](../docs/testing/library-009.md) for commands, screenshots, final run results and limits.

The initial combined run passed both UI journeys and all library checks but found five issues in the concurrently changing editor suite. A subsequent full unit run passed after those editor updates. Later verification uses the current shared project; no other session's source edits were reverted. Physical A16 and spoken VoiceOver acceptance remain separate from this simulator evidence. No upstream assets, third-party dependencies, global Xcode-selection changes, signing changes or physical installation were added. The workspace root has no Git metadata, so no commit or PR was created.

### Final verification

The normal `PencilEcho` test scheme completed successfully with **141 tests in 11 suites**, including the 19 library tests. The separate `PencilEchoLibraryUI` scheme completed successfully with **2 UI journeys**, no failures. Their result screenshots are under `tests/evidence/009/`. Debug simulator build and project/scheme validation passed. A combined runner stall was resolved by separating unit and UI schemes; it is not reported as a passing test run. See the library report for exact commands and remaining physical acceptance limits.

Release simulator build also passed on the final shared source. It emitted the existing editor background-save `taskId` capture warning and the AppIntents metadata-skipped warning; no build errors. The 008 background-save/device behavior remains under its separate acceptance gate.
- UI tests, 2026-11-03 (Claude): `tests/PencilEchoUITests/LibraryUITests.swift` now runs through its own `PencilEchoLibraryUI` scheme, not `PencilEcho`.
  - `testDamagedPackageAndAccessibilityTextSize` failed once while the library view and scheme were still changing. It then passed 3 of 3 repeated runs (`-test-iterations 3`), and both UI tests passed alone, so no code change was needed.
  - Don't run UI tests while another process installs or relaunches the app on the same simulator: that kills the test host ("signal kill while preparing to run tests").

