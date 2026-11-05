# Library navigation polish — ticket 025

Date: 2026-11-05 (Asia/Manila). Status: implemented; runtime/visual acceptance blocked. Execution: ticket-plan mode. Branch: `ui/025-library`. Worktree: `/Users/chrixcrusher/Documents/Projects/penecho-025`.

## Scope

Started from current `main` at `a160742` (the style-guide/ticket commit after the ticket's named baseline). Only the five owned Swift/test files are changed; this requested report and requested evidence are the documentation exceptions. No editor, Ask AI, Settings, MCP, persistence, document schema, thumbnail renderer or project configuration changes are included. The four editor UI test methods and their existing shared helpers are unchanged.

- HomeView now displays only LibraryView. The Debug menu/covers and launch-argument routing are removed; prototype/provider screens and their tests remain in place.
- View options combines sort and explicit checkmarked Grid/List choices; Recent retains its fixed last-opened order. New is the single prominent toolbar menu, with a canvas primary action, canvas/notebook choices and their keyboard shortcuts. A system ToolbarSpacer separates the two controls.
- Sidebar badges reuse section filtering, independent of search/sort; zero counts remain visible. Settings is pinned to the sidebar bottom and opens the unchanged AI Settings sheet.
- Cards use canvas 4:3 / notebook A4-shaped previews, continuous radius 16, a 1-point semantic separator border and no shadow. Headline titles, relative edited dates and favorite symbols replace full timestamps. Context menus include Open/Rename/Favorite/Delete and a page preview; cards have a pointer highlight.
- List rows use 56-point thumbnails with continuous radius 12, wrapping title/type/relative-date text and Favorite/Delete swipe actions. Destructive confirmation and unavailable-document behavior remain intact.
- Existing section-specific/search empty states and accessibility identifiers remain. Accessibility descriptions combine title, type, edited date/availability and favorite state. Accessibility text sizes allow grid titles to wrap beyond two lines to prevent truncation; ordinary sizes retain the two-line limit.

## Verification

Simulator: **PE-025**, A16 / iOS 27.0, `CE517F75-611F-419B-92D7-A25B2DC5EF88`. Derived data: `/tmp/PencilEcho-025`. UI journeys use UUID-isolated synthetic libraries and landscape orientation; editor-owned tests are excluded.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,id=CE517F75-611F-419B-92D7-A25B2DC5EF88' -derivedDataPath /tmp/PencilEcho-025 -parallel-testing-enabled NO test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEchoLibraryUI -destination 'platform=iOS Simulator,id=CE517F75-611F-419B-92D7-A25B2DC5EF88' -derivedDataPath /tmp/PencilEcho-025 -parallel-testing-enabled NO -only-testing:PencilEchoUITests/LibraryUITests/testCreateRenameReopenRelaunchAndConfirmedDelete -only-testing:PencilEchoUITests/LibraryUITests/testFavoriteSearchAndListLayoutSurviveRelaunch -only-testing:PencilEchoUITests/LibraryUITests/testDamagedPackageAndAccessibilityTextSize test
```

Current results:

- Hosted test-target build: **PASS** (`** TEST BUILD SUCCEEDED **`). Both new LibraryTests methods compile.
- Independent native model check: **PASS**, using the actual LibraryModel, DocumentModel, DocumentMigrator and DocumentStore sources, with an unused AppDocuments.store stub and the unchanged OpenDocuments class extracted for linkage. This checks the computed helpers, not iPad UI or the full hosted suite:

  ```text
  Passed 14 library count/relative-date assertions against actual LibraryModel and DocumentStore sources.
  ```

- Full hosted suite: **BLOCKED/INTERRUPTED** during simulator startup, before any tests executed. There is no passing “Test run with N tests … passed” line to report.
- Three library UI journeys: **FAILED TO START** after restarting only PE-025. The retry ended with `** TEST EXECUTE FAILED **` and the diagnostic below. xcresult records zero passes and one runner preparation error; none of the three requested test methods executed. This is an infrastructure failure, not a passing test run or a failed library assertion.

  ```text
  Testing failed:
      Timed out trying to boot simulator after waiting 60.00s.
      PencilEchoUITests-Runner encountered an error (Failed to prepare device 'PE-025' for impending launch.)
  ```

  Result bundle: `/tmp/PencilEcho-025/Logs/Test/Test-PencilEchoLibraryUI-2026.11.05_09-37-25-+0800.xcresult`.
- Final UI test-target build-for-testing: **PASS** (`** TEST BUILD SUCCEEDED **`). This compiles the final library and all three updated UI journeys without starting the simulator.
- Source/scope checks: **PASS** — `git diff --check`; no Debug/hammer/cover/launch routing in HomeView; all four editor UI test methods byte-for-byte unchanged; context menu contains one Rename action.

 Added model assertions for all five sidebar counts, independence from search, relative date text and missing dates. Updated only the three library journeys for New/View options and list swipe actions; they cover ignored Debug arguments, create/rename/reopen/delete, favorite/search/layout relaunch persistence, settings access, damaged packages and large text.

## Screenshots

No library screenshots were captured: PE-025 remained on the Apple boot screen and could not launch the app. The five requested captures remain open:

| Requested image | UI attachment name | Result |
|---|---|---|
| Grid | `025-grid` | Blocked before app launch |
| List | `025-list` | Blocked before app launch |
| Empty Favorites | `025-empty-favorites` | Blocked before app launch |
| Search with no results | `025-search-no-results` | Blocked before app launch |
| Dark mode | `025-dark-mode` | Blocked before app launch |

The test source also captures `025-large-text-damaged`. No placeholder/mock images or boot screens are presented as library evidence. When the journeys run, export their attachments to `tests/evidence/025/` and inspect them before closing visual acceptance.

## Review and remaining acceptance

Implementation is reviewable; runtime and screenshot acceptance remain open until the simulator can start the app. This is a presentation-only change with no architecture/API/schema changes, so canonical technical intent is unchanged; documentation is confined to this ticket's explicitly requested report. The development plan and ticket status are left for the required reviewer rather than edited outside the ticket's ownership list.


Claude review remains required before merge. Pointer hover, VoiceOver speech and hardware keyboard shortcuts also need owner interaction acceptance; simulator automation and source checks do not establish physical device acceptance. The branch is committed for review; it has not been merged or pushed. No broader fixes or other worktrees’ changes are included.

## Final review summary

- Implemented and committed on `ui/025-library` from the requested isolated worktree.
- No application source outside HomeView / LibraryView / LibraryModel changed. LibraryModel changes are two computed presentation helpers only. No persistence or behavior changes were made there.
- Both hosted and UI test-target builds pass; 14 native helper assertions pass. Runtime test acceptance is **not complete**: zero UI passes, one runner startup error, full hosted execution interrupted before tests.
- The five requested screenshots and their visual inspection remain blocked before app launch. The three UI journeys already contain the named capture points for a future run.
- Owner VoiceOver, pointer and hardware-keyboard checks and Claude review remain open. No merge, push or owner-device installation was performed.

## Senior review and verification (Claude, 2026-11-05)

Code review: scope respected (HomeView, LibraryView, LibraryModel helpers and the three library journeys only; no project file). Debug menu removed; View options + New; sidebar counts; page-shaped cards; relative dates; context menu with preview; list swipe actions.

Fixes made during review:

- **New wasn't prominent:** `.buttonStyle(.glassProminent)` doesn't apply to a `Menu` by itself; added `.menuStyle(.button)`.
- **Favorites journey:** the search empty state is "No Results for “…”" on iPadOS 27, so the assertion matches the prefix. While search is active iPadOS hides the toolbar's View options, so sort and layout now run before the search. Menu items are system menu items without SwiftUI identifiers, so the layout helper finds Grid/List by label (`library-layout-toggle` was never reachable).

Results on the iPad (A16) simulator:

- Full unit suite: **✔ Test run with 258 tests in 26 suites passed.**
- Library UI journeys: `testCreateRenameReopenRelaunchAndConfirmedDelete` ✔, `testDamagedPackageAndAccessibilityTextSize` ✔, `testFavoriteSearchAndListLayoutSurviveRelaunch` ✔.
- The four editor journeys still in `LibraryUITests.swift` on this branch fail (two because the sidebar row is now also named "Settings"). Ticket 024 moves and rewrites them with unique identifiers.
- Screenshots in `tests/evidence/025/` (grid, list, empty Favorites, search no results, dark mode, large text + damaged, toolbar and counts). The journeys force landscape and XCUI captures those rotated and cropped at the top edge; they were rotated upright, and `025-toolbar-and-counts.png` is a direct simulator capture showing the toolbar.
