# 004 — Ink + editable object layer spike

Milestone: PE-000 · Status: In Progress — simulator verified; Claude review done (conditional approval); owner A16 acceptance pending · Owner: Codex (build), Owner + Claude (review) · Depends on: 002

## What

A throwaway-quality but measured prototype proving that PencilKit ink and editable UIKit objects can share one coordinate system with zoom/pan, mixed lasso and unified undo on the A16.

## Why

This is the main technical risk (see `docs/feasibility/feasibility-assessment.md`). PencilKit has no object layer, `PKLassoTool` selects strokes only, and `PKCanvasView` keeps its own undo stack. The result decides the architecture for PE-001+.

## Scope

- A spike screen (behind a debug menu item) with one `PKCanvasView`, `drawingPolicy = .pencilOnly`, a large fixed content size (e.g. 4000×4000 pt).
- Object layer: UIKit views (a text label, an image, a colored box) positioned in **document coordinates** and kept aligned with ink during zoom, pan and rotation. Document whether objects live inside the canvas scroll view's content or in a synced overlay, and why.
- Z-order: test ink above objects and ink below objects; recommend one.
- Mixed lasso: a custom lasso (`PKToolPickerCustomItem` or a mode button) that hit-tests `PKStroke` paths and object frames, selects both, and moves them together.
- Unified undo: one `UndoManager` transaction groups an object insert + stroke changes; an "Insert answer" button adds an object as **one** undo step; Pencil strokes stay individually undoable.
- Measurements on the physical A16: memory with ~2,000 strokes and ~50 objects, scroll/zoom smoothness (Instruments or `CADisplayLink` frame drops), and stroke latency feel.

## Exclusions

No persistence, AI, A4 pages, backgrounds or polished UI. Code may be rewritten in 008.

## Acceptance

- [x] Simulator seeded alignment at 0.25×, 1× and 4× visually checked, with screenshot evidence. Continuous gesture/rotation alignment on A16 remains pending.
- [ ] Mixed lasso selects and moves ink + objects together.
- [ ] One undo removes an inserted object; redo restores it; stroke undo still works.
- [ ] Finger touch pans/zooms and never draws.
- [x] `docs/spikes/004-ink-object-layer.md` records the approach, provisional z-order choice, simulator measurements, known limits and pending physical measurements.
- [x] Simulator Debug/Release builds pass; physical measurements are explicitly marked NOT RUN.

## Stop conditions

Stop and report if alignment drifts at zoom, if undo can't be unified without private API, or if memory exceeds ~1 GB at the test load.

## Implementation and verification — 2026-11-03

Plan-first execution of the existing ticket. Debug → Ink + object spike opens an in-memory 4,000 × 4,000 point PencilKit/UIView workspace with selectable z-order, mixed lasso/move, text editing, shared undo/redo, a combined text+ink Insert answer action, synthetic load and footprint/display-link monitoring. No persistence, AI, dependencies or upstream ports were added. The release shell remains unchanged.

The canonical simulator build/test commands passed. Final run: **14 tests in 4 suites passed** (11 spike tests and 3 scaffold placeholders). Release simulator build passed too. Unit/integration checks establish selection geometry, real lasso-handler state transitions, cancellation restoration, mixed-move transactions, combined insert undo/redo and synthetic ink-action ordering. They do not establish real Pencil stroke undo, touch arbitration or hardware latency.

The [spike report](../docs/spikes/004-ink-object-layer.md) contains screenshots at all three zoom levels, both z-orders, simulator measurements and exact owner-device steps. Simulator stress screenshot: 2,000 strokes / 50 objects, 79 MiB current / 86 MiB sampled peak. No visible seeded alignment drift or 1 GiB stop occurred. Provisional recommendation: ink above objects, subject to Owner + Claude review.

The unchecked acceptance items remain open for actual touch/Pencil interaction and physical A16 evidence. The computer-use tool did not expose Simulator; deterministic handler tests and launched screenshots are the available simulator evidence. Do not treat this ticket as resolved or promote the approach into 008 before the device checks/review. No root Git metadata exists, so no commit or PR was created. No scope deviations.

## Claude review — 2026-11-03

Verdict: **approve the approach for ticket 008, conditional on the owner's A16 steps below.** Simulator evidence and code agree with the report. Nothing found requires private API or a different architecture.

Checked independently:
- **Code:** I read `InkObjectSpikeView.swift`, `SpikeDocument.swift`, `SpikeGeometry.swift`, `SpikeMetrics.swift` and the 11 spike tests. The coordinate math (`v = p × z − o`, anchor at the document origin) matches the report. The objects are a sibling layer, and nothing touches PencilKit's private views.
- **Tests:** they pass in the full suite (80 tests, 7 suites, `iPad (A16)` simulator).
- **Landscape at 0.25×:** this case was not in the evidence. The content (1,000 pt) is narrower than the viewport (about 1,156 pt), so a centering scroll view would misalign the layers. Launched with `-spike004 -spikeZoom 0.25` in landscape, there was no drift: the underline stays under the label and the red stroke crosses the box. PencilKit does not center small content.
- **Rotation:** landscape → portrait kept alignment, and the app stayed running. During the first rotation the app was once found on the home screen. No crash report was written and it did not reproduce, so treat it as unexplained and watch for it on the device.

Decisions:
- **Z-order: agree with ink above objects.** The consequence for 008 and 011: the transparent canvas sits on top and receives every touch. Object gestures (select, double-tap to edit, resize) must keep living on the viewport, as the spike does, never on the object views.
- **Sibling overlay rather than objects inside the canvas content:** agree. It is the only option that avoids PencilKit's private view hierarchy.

Risks for the device run and for 008, in priority order:
1. **Undo grouping can crash.** `groupsByEvent = false` means every undo registration needs an open group. Groups are opened only between `canvasViewDidBeginUsingTool` and `canvasViewDidEndUsingTool`. If PencilKit registers a stroke or eraser undo outside that window (for example after end-of-tool, or from Pencil double-tap or Scribble), `UndoManager` raises an exception. The simulator cannot show this. Device step 1 must include fast consecutive strokes and the eraser. If it fails, give `PKCanvasView` its own throwaway undo manager and register document snapshots from `canvasViewDrawingDidChange`. That uses public API only and keeps one history.
2. **Undo memory.** Each action stores a full `PKDrawing` snapshot, up to 50 levels. With the 2,000-stroke load, do 20 or more moves and then check the memory peak. 008 may need stroke diffs instead of snapshots.
3. **Text sharpness at 4×.** UILabel text gets soft because the layer is scaled. 011's "sharp at 4×" acceptance needs a `contentScaleFactor` update or a re-render on zoom end.
4. **Fragile state:** selection by stroke index, and `contentSize` set by hand to document × zoom in `loadFixture`. Acceptable in a spike; 008 should use stable stroke identity and derive the content size in one place.

Remaining before this ticket can be resolved: the owner's physical A16 steps 1–7 in `docs/spikes/004-ink-object-layer.md`, with risk 1 added to step 1 and risk 2 to step 6. The three unchecked acceptance items (lasso, undo, finger) depend on them.
