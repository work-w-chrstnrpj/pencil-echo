# 025 — Library: cleaner toolbar, better cards, no Debug button

Milestone: UI/UX upgrade · Status: Open · Owner: **Codex (mid-level)** · Depends on: nothing (start from `main` at `a9c8a0c`) · Reviewer: Claude

Read [the UI style guide](../docs/design/ui-style-guide.md) first. It defines spacing, corner radii, typography, colors and accessibility rules; follow it exactly.

## Problem (owner review, 2026-11-05)

- A floating **Debug** menu (hammer icon) sits over the library in Debug builds (`HomeView.swift`). The owner doesn't want it.
- The library toolbar has four loose buttons: Sort, Grid/List, New Canvas, New Notebook.
- Cards are plain thumbnails with a title and a full date; the sidebar has no counts; AI Settings is a sidebar row that feels bolted on.

## Target design

```
┌ Sidebar ───────────┐┌ Pencil Echo ───────────────────────── [View options ▾]  [ + New ▾ ] ┐
│ Library            ││ 🔍 Search documents                                                  │
│  🕘 Recent      3  ││                                                                      │
│  ☆ Favorites    1  ││  ┌────────┐  ┌────────┐  ┌────────┐                                  │
│  ▤ All          7  ││  │ thumb  │  │ thumb  │  │ thumb  │      cards: page-shaped thumbnail │
│ Types              ││  └────────┘  └────────┘  └────────┘      title (headline)             │
│  ✎ Canvases     5  ││  Maze ☆      Notes       Physics         "Edited 2 hours ago"         │
│  📓 Notebooks   2  ││                                                                      │
│                    ││                                                                      │
│ ⚙ Settings         ││                                                                      │
└────────────────────┘└──────────────────────────────────────────────────────────────────────┘
```

1. **Remove the Debug menu completely** from `HomeView.swift`: the overlay `Menu("Debug")`, its `@State` flags and both `.fullScreenCover`s. `HomeView` becomes just `LibraryView()`. Leave `InkObjectSpikeView`, `QwenDebugView` and their tests in place (unreferenced from UI is fine; deleting them is a separate cleanup). The `-spike004` / `-provider007` launch arguments stop doing anything; that's expected.
2. **Toolbar:** two items, separated with `ToolbarSpacer`:
   - **View options** menu (`line.3.horizontal.decrease.circle`): a "Sort by" section (Last modified, Last opened, Title, Created; checkmark on the current one; Recent shows "Sorted by last opened" disabled as today) and a "Show as" section (Grid / List, checkmarked). Replaces the separate sort menu and layout button. Keep identifiers: the menu gets `library-sort`; the Grid/List items keep the `library-layout-toggle` behavior (a UI test toggles layout. Expose a button inside the menu with identifier `library-layout-toggle`).
   - **New** (`plus`, `.glassProminent`): `Menu` with `primaryAction` = New Canvas; items New Canvas (⌘N) and New Notebook (⌘⇧N). Keep the existing create logic.
3. **Sidebar:** `List` with `.listStyle(.sidebar)`; rows use `Label` + a trailing count (`.badge(count)`); counts come from the existing model data (add small computed helpers in `LibraryModel` if needed. No persistence changes). Move "AI Settings" to a bottom **Settings** row (`gearshape`, identifier `library-ai-settings` kept) that opens the same `AISettingsView()` sheet. Default selection stays All Documents.
4. **Grid cards:** thumbnail in a page-shaped frame (canvas 4:3, notebook A4 portrait 1:1.414), corner radius 16 continuous, 1 pt `.separator` stroke, no shadow; below it the title (`.headline`, 2 lines max) and a relative date ("Edited 2 hours ago", `.subheadline`, `.secondary`) using `Date.RelativeFormatStyle`; favorite shown as a small `star.fill` symbol after the title (not color alone). `.hoverEffect(.highlight)`, `.contextMenu` with Open, Rename, Favorite/Unfavorite, Delete (destructive), and a context-menu preview of the thumbnail. Adaptive grid: `GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 20)`, 20 pt padding.
5. **List rows:** 56 pt thumbnail (corner 12), title, type + relative date on one secondary line, favorite symbol; swipe actions Favorite and Delete.
6. **Empty and search states:** `ContentUnavailableView` per section with a New Canvas / New Notebook button where relevant; search uses `ContentUnavailableView.search(text:)`.
7. **Damaged/unsupported documents** keep their current behavior and accessibility text; restyle the card to show `exclamationmark.triangle` + short text.

## Files you own (only these)

- `application/App/HomeView.swift`
- `application/App/Library/LibraryView.swift`
- `application/App/Library/LibraryModel.swift` (computed helpers only: counts, relative-date text. No storage or behavior changes)
- `tests/PencilEchoUITests/LibraryUITests.swift`: **only** `testCreateRenameReopenRelaunchAndConfirmedDelete`, `testFavoriteSearchAndListLayoutSurviveRelaunch`, `testDamagedPackageAndAccessibilityTextSize` and shared helpers they alone use. Ticket 024 moves the four editor tests out of this file; don't edit those four.
- `tests/PencilEchoTests/LibraryTests.swift` for any new helper.

**Don't touch:** anything under `Editor/`, `AskAI/`, `Settings/`, `MCP/`, `service/`, `shared/`, `ThumbnailRenderer.swift`, and `project.pbxproj`. **Don't add new files** (put new views in `LibraryView.swift` as private structs).

## Acceptance criteria

- [ ] No Debug menu, hammer icon or debug cover in any build configuration; `HomeView` contains only `LibraryView()`.
- [ ] Library toolbar shows exactly two items: View options and New. New's primary tap creates a canvas; its menu offers canvas and notebook; ⌘N / ⌘⇧N work.
- [ ] Sort and Grid/List are both inside View options, with checkmarks for the current choice; choices still persist across relaunch.
- [ ] Sidebar shows counts for Recent, Favorites, All, Canvases, Notebooks, and a bottom Settings row that opens AI Settings.
- [ ] Cards: page-shaped thumbnail, title, relative "Edited …" date, favorite symbol; context menu (Open, Rename, Favorite, Delete) with preview; hover effect with a pointer.
- [ ] List rows: thumbnail, title, type and relative date, swipe Favorite/Delete.
- [ ] Empty states for every section and for search.
- [ ] Styling matches the style guide: radii 12/16 continuous, spacing from the token list, system text styles, semantic colors, labels on every symbol.
- [ ] VoiceOver: each card reads "title, type, edited date, favorite" as one element with Rename/Delete/Favorite actions (as today). Dynamic Type AX3 doesn't clip titles.
- [ ] Existing identifiers still work: `library-grid`, `library-list`, `library-sort`, `library-layout-toggle`, `library-ai-settings`.
- [ ] Your three library UI tests pass (updated for the new menus); `LibraryTests` and the full unit suite pass.
- [ ] Screenshots (grid, list, empty Favorites, search with no results, dark mode) in `tests/evidence/025/`.

## Handoff to Codex

- **Your task is only this ticket.** Don't fix or restyle anything outside the files listed, even if you notice issues. Write them in your report instead.
- **Work isolated:** from the repository root run
  `git worktree add ../penecho-025 -b ui/025-library main` and work only in `../penecho-025`.
- **Simulator:** create your own and use only it:
  `xcrun simctl create "PE-025" com.apple.CoreSimulator.SimDeviceType.iPad-A16 com.apple.CoreSimulator.SimRuntime.iOS-27-0`. Use `-derivedDataPath /tmp/PencilEcho-025`.
- **Verify:**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination "platform=iOS Simulator,id=<PE-025 id>" -derivedDataPath /tmp/PencilEcho-025 -parallel-testing-enabled NO test`
  and the `PencilEchoLibraryUI` scheme for UI tests. Paste the final "Test run with N tests … passed" lines in your report.
- **Commit** on `ui/025-library` with a message ending `Co-Authored-By` your tool; don't merge, push or touch `main`.
- **Report back** (in `docs/testing/library-025.md`): what changed, screenshots list, test results, anything left undone and why.
- Claude reviews against every acceptance criterion before merge.
