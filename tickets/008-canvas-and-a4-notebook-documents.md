# 008 — Canvas and A4 notebook editors

Milestone: PE-001 · Status: In Progress — simulator verified; owner A16 check and 004 device review pending · Owner: Claude (taken over from Codex to parallelize) · Depends on: 004, 005

## What

Production versions of the two document types, built on the approach chosen in the 004 spike and saved with the 005 schema.

## Why

The first acceptance gate needs a real document to write in, save and reopen.

## Scope

- **Canvas:** one large page that grows as the user draws near edges (cap and growth step defined from 004 measurements).
- **Notebook:** vertically scrolling A4 pages (595×842 pt). Add page, delete page (with confirm), page indicator.
- Backgrounds per page: blank, lined, dotted, grid (drawn, not part of ink; not erasable).
- Pencil-only drawing; finger pans/zooms. `PKToolPicker` with pen, marker, eraser, lasso, plus the mixed lasso from 004.
- Object layer from 004 with move/resize of selected objects and delete.
- Unified undo/redo (toolbar buttons + ⌘Z / ⇧⌘Z with keyboard).
- Autosave: debounced (~2 s after last change) and on scene background/close, via `DocumentStore`. Increment `revision` only on content changes.
- Basic VoiceOver labels for toolbar and objects.

## Exclusions

No AI, image/PDF import, export, search or multiwindow editing of the same document (one window per document in v1; opening it twice focuses the existing window or opens read-only, so document the choice).

## Acceptance

- [ ] Create canvas and notebook; draw; add a test text object; close; reopen: ink, objects, backgrounds and page order match.
- [ ] Force-quit within 2 s of a stroke loses at most that last debounce window; document still opens.
- [ ] Undo/redo works across strokes and object moves.
- [ ] Rotation keeps content aligned.
- [x] Unit/UI tests for save/reopen; simulator build/test commands pass.
- [ ] Owner device check on A16 recorded separately.

## Implementation — 2026-11-03

Started after 005 was resolved. Ticket 004's physical A16 checks and Owner + Claude review are still open, so this editor is built on the spike approach **before** that review. If the device checks fail, revisit the undo and lasso parts first. Code: `application/App/Editor/`, tests: `tests/PencilEchoTests/EditorSessionTests.swift`. The library (009) opens the editor full screen.

Decisions:

- **One editor for both types.** One `PKCanvasView` is the only scroll/zoom surface. Backgrounds, objects and the selection overlay are sibling layers synchronised to its zoom and offset (004 approach). Ink draws above objects (004 recommendation).
- **Notebook** pages stack vertically in one document space with a 32 pt gap (`EditorLayout`). Ink is composed into one drawing on open and split back on save by each stroke's vertical centre, so `ink/<pageId>.drawing` stays page-relative. A stroke that crosses a page edge belongs to one page. The page width fits the viewport on open and on rotation. Add page inserts after the current page with its background; delete page asks for confirmation, removes that page's ink and objects, is undoable and keeps at least one page. The indicator shows "Page n of m".
- **Canvas** starts at 2,000 × 2,000 and grows right and down in 1,000 pt steps when content comes within 400 pt of an edge, up to the 20,000 pt schema cap. It never grows left or up, because that would shift every stroke and object. Undo does not shrink it. The step and margin are provisional until 004's A16 measurements.
- **Backgrounds** (blank, lined, dotted, grid; default spacing 24) are drawn per visible region by `PageBackgroundView`, never into the ink. A pattern closer than 6 screen points is skipped. A change is undoable.
- **Input and tools.** `.pencilOnly`, fingers pan and zoom. `PKToolPicker` offers pen, marker, eraser and the native lasso (ink only). The **Select** toggle is the 004 mixed lasso: trace a loop with one finger or the Pencil, then drag inside to move ink and objects together. Tap selects one object; the round handle resizes it within its page. Delete removes the selection; double-tap or Edit text edits an object's source. Markdown and LaTeX show their source until 011.
- **Undo.** The session's `UndoManager` is shared with PencilKit through the canvas. Native strokes and erases use PencilKit's registration. Every other edit commits an inverse snapshot (pages, composed drawing, objects). The manager groups by event, the default PencilKit expects, so each user action is one step. Toolbar buttons and ⌘Z / ⇧⌘Z (key commands) drive it.
- **Revision** +1 per committed change, undo and redo included. A tool gesture counts once even if the eraser changes the drawing many times. Previews and selection don't count.
- **Autosave** runs 2 s after the last change, on Done, and when the scene leaves the foreground (inside a background task). Saves are serialised. Each save renders the 009 thumbnail. A conflict (`expectedRevision` mismatch) stops all saving and shows a banner, so neither copy is overwritten. Other failures keep the changes in memory, and Done offers "Close Without Saving".
- **One window per document (choice for v1).** A document already open in another window opens **read-only** there with a banner (`OpenDocuments`). It doesn't focus the other window, because SwiftUI's `WindowGroup` here has no per-document scene to activate. A package with unreadable ink also opens read-only, so its bytes are kept.
- **VoiceOver.** Toolbar buttons have labels. Objects are elements labelled by type and the start of their source. The canvas has a label and a hint. Save state is visible text.

Verification: the Debug simulator build and the full test run passed, **116 tests in 9 suites** (15 new editor tests), on a dedicated iPad (A16) iOS 27.0 simulator. The tests cover notebook save/reopen (pages, order, backgrounds, objects, page-relative ink, thumbnail), canvas growth and its cap, undo/redo across strokes and moves with revision, previews, move clamping, resize limits, page delete and undo, compose/decompose, the debounced autosave, the no-op save, the second-writer conflict, read-only refusal and the one-editor registry. Strokes in the tests are committed snapshots. **Native Pencil stroke undo, finger/Pencil arbitration, rotation alignment, force-quit timing and the A16 check are NOT RUN.** Debug and Release simulator builds also pass with ticket 010's in-progress `AskAI` files present.

**Device fix (first owner install, 2026-11-03, by the 009/010 session).** On the iPad, the Pencil drew no visible ink and the paper showed black. The layer frames were set in `viewDidLayoutSubviews`, but the stack view sizes the viewport later, so the canvas, background and overlay stayed zero-sized. `EditorViewportView` now re-lays them out from its own `layoutSubviews`. A Debug-only `-anyInputDrawing` launch argument lets a finger draw in the simulator. Rendering was checked in the dark-mode simulator; the A16 check is still open.

Not done: rename (009 owns it), per-object z-order controls, text editing beyond a single-line field, and growth to the left or top.

## Device bug fixed — 2026-11-03 (Claude)

- **Symptom:** on the owner's A16, the Pencil drew no visible ink. In dark mode the page area was black.
- **Cause:** `viewDidLayoutSubviews` sized the canvas, page background and selection overlay from `viewport.bounds`. The viewport is a stack-view child: the stack sizes it after that callback, and again when the banner toggles, without calling the controller back. Those layers stayed at zero size, so there was no ink, no Pencil hits, and only `systemBackground` behind.
- **Fix:** `EditorViewportView` calls back from its own `layoutSubviews`, so layers are resized on every viewport layout.
- **Also added:** a Debug-only `-anyInputDrawing` launch argument, which lets a finger draw in the simulator.
- **Verified:**
  - In the dark-mode simulator: lined paper, the fixture's ink and a new stroke are all visible.
  - Unit tests: 165 tests in 13 suites passed.
  - Reinstalled on the iPad; the owner's Pencil check is pending.

