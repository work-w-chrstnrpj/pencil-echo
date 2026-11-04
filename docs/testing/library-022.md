# Library navigation — ticket 022

Status: Implemented; simulator verification recorded below. Physical A16, spoken VoiceOver and landscape/portrait acceptance remain a separate owner check. Updated 2026-11-05.

## Behavior

The library is a two-column `NavigationSplitView`. The sidebar lists Recent, Favorites and All Documents, then filters for Canvases and Notebooks; AI Settings sits at the bottom of the sidebar. In compact width the split view collapses to the system's normal sidebar presentation. The document area keeps the existing thumbnail grid and adds a list layout with a small thumbnail, title, type and modified date.

Favorites are toggled from each document's context menu and accessibility actions. The state is stored as the optional `isFavorite` manifest key. Last-opened times use the optional `lastOpenedAt` manifest key. Both are written by cloning the live package, rewriting only `manifest.json` and swapping it in atomically, exactly like rename, so ink, assets, conversation, thumbnails, unknown files and unreadable optional data are preserved. Neither key changes `revision` or `updatedAt`; favorites and opens are library metadata, not content edits. Packages written before ticket 022 have neither key and appear under All Documents.

The library records an open when a document is created or successfully opened. Recent contains documents with `lastOpenedAt` inside the last 30 days, always newest opened first, so opening a document moves it to the top of Recent. Recording is best effort and is skipped when another window already owns the document. A favorite change is refused while another window's editor owns the document, matching the existing rename/delete guard.

Search is `.searchable` over titles only and filters as the user types. Sort keys are last modified, last opened, title and created; Recent ignores the selected key because its newest-opened order is part of its meaning. Sort and grid/list layout are remembered across launches in UserDefaults, not in document packages. Empty sections have their own messages, and an empty search uses the system no-results state.

Rows expose one combined accessibility label with title, type, favorite state, edited date or unavailable reason, plus Rename/Delete/Favorite accessibility actions. The sidebar is a selectable `List`, so VoiceOver and keyboard selection use standard list behavior. The editor top-bar favorite star was intentionally left for a follow-up after ticket 020, as the ticket allows; this change ships the library context menu.

## Source

- `application/App/Library/LibraryView.swift`: split view, sidebar, search, sort/layout controls, grid and list rows, favorite context menu and empty states.
- `application/App/Library/LibraryModel.swift`: sections, Recent window, search, sort comparators, remembered preferences, favorite and open recording.
- `service/Persistence/DocumentStore.swift`: metadata-only atomic manifest rewrite and summary fields.
- `shared/Document/DocumentModel.swift`: optional `isFavorite` and `lastOpenedAt` v1 manifest keys.
- `tests/PencilEchoTests/LibraryTests.swift`: metadata persistence/preservation, migration compatibility, Recent window, every sort key, title search, preference persistence and open-editor guard.
- `tests/PencilEchoUITests/LibraryUITests.swift`: isolated Debug journey for favorites, search, list layout and relaunch.

## Verification

PENDING.

Screenshots in `tests/evidence/022/` are exported from the passing UI journey and visually checked.

## Commands

Run from the workspace root, without changing global Xcode selection. The PencilEcho scheme runs hosted unit/model tests; the PencilEchoLibraryUI scheme runs the Debug-only UI journeys against a UUID-isolated temporary library.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEchoLibraryUI -derivedDataPath /tmp/PencilEcho-022-UI -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO test
```

## Product checks still open

On the owner A16, check the sidebar, search, sort, list/grid switch, Favorites and Recent with VoiceOver speech and actions in portrait and landscape. Confirm favorites and layout survive relaunch on device. These are part of the integrated device acceptance and are not established by simulator results.
