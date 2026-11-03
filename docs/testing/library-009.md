# Basic library — ticket 009

Status: Implemented; simulator verification recorded below. Physical A16 and spoken VoiceOver acceptance remain separate product checks. Updated 2026-11-03 (Asia/Manila).

## Behavior

The home screen is a local document grid with New Canvas and New Notebook actions. Documents are saved under the app's `Documents/Documents/` directory without accounts or a separate library database. The grid rebuilds from package manifests, newest first, with a stable filename tie-break for identical timestamps. Cards show a thumbnail or type placeholder, title, type icon and updated date. Corrupt manifests and unsupported versions remain visible.

Tap a valid card to open the native editor. The library checks the exact listed package before opening, so corrupt required content produces “Can't open” as well. The editor independently loads again to handle changes between those steps. New documents open directly into the editor. Done uses the editor's save/unsaved-change flow; interactive swipe dismissal is disabled. Closing an editor, returning to the foreground, or pull-to-refresh rebuilds the grid and reloads visible thumbnail previews.

Long-press a card for Rename and Delete; both actions are also exposed to accessibility. Rename trims whitespace, accepts 1–200 characters, keeps the content revision unchanged and updates the edited date. Delete requires an alert confirming that it is permanent. There is no trash until PE-004. Invalid-title controls refuse submission, and operation errors never include document content.

Library and editor windows use the shared `AppDocuments.store` actor. Rename/delete temporarily acquire the same in-process document claim as editors. If another window owns editing, the action is refused with a close-first message. Editors acquire their claim before awaiting load, preventing a metadata action from racing an editor's initial snapshot. Failed loads release the claim. This does not replace ticket 008's document revision and save/conflict policy.

## Package preservation and previews

Rename clones the original package into an item-replacement directory, changes only `manifest.json`, then swaps the package atomically. It preserves all other file bytes, including unreadable optional files and unknown files; a failed metadata write leaves the old package intact. Content saves keep the separately specified v1 cleanup behavior. Listing rejects manifest IDs that disagree with package filenames, so tapping one entry cannot redirect to another document.

Before editor saves, `ThumbnailRenderer` produces a first-page PNG with a maximum 512-pixel edge. It renders objects and ink above them, crops canvases to their content, and uses the first A4 page for notebooks. Image assets use pending bytes or the saved package's assets folder, with bounded ImageIO downsampling. Missing images show placeholders. Markdown/LaTeX source is represented as text until the dedicated renderer work; page background patterns are not included in this preview. Invalid geometry is skipped/refused rather than passed to an unbounded renderer.

Visible thumbnail reads run off the main thread, accept files up to 2 MiB, and downsample before displaying. Missing/unreadable previews use a type placeholder. A library refresh reloads visible previews even when the content revision/updated date did not change; cancelled image tasks cannot overwrite a newer result.

The grid width and fonts scale with Dynamic Type and fit the actual available width. Each card exposes one accessible label containing its full title, type and edited date or unavailable reason. Accessibility actions expose Rename/Delete. Simulator accessibility-tree checks do not establish spoken VoiceOver behavior on the owner device.

## Source and verification

- `application/App/Library/`: grid/presentation, observable state and thumbnail rendering.
- `service/Persistence/DocumentStore.swift`: manifest-only listing, metadata-only atomic rename and guarded package deletion.
- `application/App/Editor/DocumentEditorView.swift`: shared-store/editor handoff and safe ownership acquisition; `EditorSession.makeDocument()` supplies stored-asset context for thumbnail generation.
- `tests/PencilEchoTests/LibraryTests.swift`: 19 library tests, including fresh-store relaunch, malformed packages/identity, rename preservation/failure, open-editor guards, deterministic 500-package listing, PNG/image assets and editor-save previews.
- `tests/PencilEchoUITests/LibraryUITests.swift`: two simulator UI journeys in the separate PencilEchoLibraryUI scheme. They compile only in Debug and use a unique temporary library selected with a validated UUID launch argument. The ordinary owner Documents directory is never used for these create/delete tests. Release does not accept this test-root override.

The UI journeys verify:

1. Create Canvas → close editor → rename → reopen → terminate/relaunch → retain title → create Notebook → cancel deletion → confirm deletion → relaunch → retain Notebook and omit deleted Canvas.
2. Seed a damaged package in the isolated test library → launch at accessibility XXXL text size → verify a hittable card with “Can't open” in its accessibility label → open/dismiss its explanation and retain the package.

Screenshots exported from those passed UI tests and visually inspected:

- [Library after process relaunch](../../tests/evidence/009/library-after-relaunch.png)
- [Damaged package at accessibility XXXL](../../tests/evidence/009/library-large-text-damaged.png)

The older `library.png`, if present, records the initial library implementation; the two screenshots above record the completed editor handoff and new UI journeys. Empty documents can display a type placeholder until a content save supplies a thumbnail.

## Commands

Run from the workspace root, with no global Xcode selection changes. The PencilEcho scheme runs hosted unit/model tests. The PencilEchoLibraryUI scheme runs PencilEchoUITests independently, avoiding mixed runner launches.

Unit/model/service checks:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO test
```

UI journeys independently:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEchoLibraryUI -derivedDataPath /tmp/PencilEcho-009-UI -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO test
```

The canonical build command and the same build with `-configuration Release` verify both app configurations. Simulator runtime: iOS 27.0, iPad (A16); Xcode 27.0 (27A266a). No provider calls, owner-document deletion, physical installation or signing changes are part of this verification.

## Product checks still open

On the owner A16, check the library with VoiceOver speech/actions and large Dynamic Type in portrait, landscape and supported multitasking sizes. Confirm create/open/edit/close/reopen on real Pencil input and repeated saves. These remain part of the integrated device acceptance; simulator results do not close that gate. Ticket 004/008 device performance and 007 live-provider acceptance remain independent.

## Final simulator results — 2026-11-03

- `PencilEcho` unit/model/service test command: **TEST SUCCEEDED**, 141 tests in 11 suites passed, including all 19 library tests. This includes the other sessions' current editor and Ask AI source; it is not a claim of device/live-provider acceptance.
- `PencilEchoLibraryUI` test command: **TEST SUCCEEDED**, 2 UI journeys passed, 0 failures. The separate scheme used `/tmp/PencilEcho-009-UI` for build results and each test used its own temporary document library. The two retained screenshots were exported from this successful result bundle and visually checked.
- Earlier combined attempts are not counted as green: the initial run found five editor-test issues while that code was changing; a later mixed-runner attempt stalled after its 141 unit tests passed and was terminated. Both dedicated schemes subsequently completed successfully. Temporary compile errors from concurrent Ask AI work were also resolved before the final unit run; no such source was reverted for this ticket.
- Project plist lint, both shared-scheme XML parses and local evidence links passed validation. Debug simulator build passed. Release build status is recorded with ticket 009's final verification notes.

The native source, package contract, project map, development plan, test commands and README were updated together. No root Git repository is present, so there is no commit/PR evidence for this workspace state.

Release simulator build also passed on the final shared source. It emitted the existing editor background-save `taskId` capture warning and the AppIntents metadata-skipped warning; no build errors. The 008 background-save/device behavior remains under its separate acceptance gate.
