# 004 — PencilKit and editable object layer

Status: Implemented prototype; simulator verification recorded below. Claude review recorded 2026-11-03 (conditional approval, see end). Awaiting physical A16/Pencil acceptance. Updated 2026-11-03 (Asia/Manila).

## Scope and entry

Run the Debug configuration, open **Debug → Ink + object spike (004)** on the home screen. The spike and its launch arguments compile only under `DEBUG`; Release retains the placeholder home screen. The screen owns a disposable 4,000 × 4,000 point document. Closing it discards its contents. There is no persistence, AI, notebook implementation or third-party dependency, and no upstream material was copied.

The sample contains a UIKit text label, an SF Symbol image and an opaque yellow box, plus two synthetic PencilKit strokes. Use Edit text (or a finger double-tap) to edit the selected text label, falling back to the first text label. Image/box positions are editable through mixed selection; image replacement and object resizing are outside this spike.

## Coordinate approach

`PKCanvasView` is the only scrolling/zooming surface. A noninteractive sibling `objectContainer` holds UIKit views in document coordinates. Its anchor is the document origin, its scale is `canvas.zoomScale`, and its position is `-canvas.contentOffset`. Scroll/zoom delegate callbacks and layout changes resynchronize the layer with implicit animations disabled. Content inset adjustment is disabled.

For document point `p`, viewport point `v`, zoom `z` and content offset `o`:

```text
v = p × z − o
p = (v + o) / z
```

The selection outline is a separate, noninteractive viewport overlay, so its line width stays constant while zooming. This uses public UIKit/PencilKit APIs only and does not inspect or modify PencilKit's internal view hierarchy. Keeping objects out of the canvas's private content view avoids depending on that hierarchy. A production editor still needs culling and measured document limits.

Automated checks cover both portrait- and landscape-sized layouts, zoom 0.25×/1×/4×, and transformed view coordinates. Rendered screenshots cover the same three zoom levels. These do not establish continuous pinch/rotation behavior on hardware.

## Z-order experiment

The Ink above / Ink below button swaps the sibling order. In Ink below, opaque labels and the yellow box obscure the seeded strokes within their frames; in Ink above, strokes remain visible across the objects.

**Prototype recommendation: ink above objects.** This allows annotations on images and boxes and keeps handwriting visible. Review this choice before ticket 008, including answer placement and whether later object types need explicit per-object layering. The toggle remains available for comparison. Selection overlays always appear above both layers.

## Mixed lasso

In Ink mode, `.pencilOnly` draws and fingers navigate. In Mixed lasso mode, the PencilKit drawing recognizer is disabled, a one-touch pan recognizer collects a document-space polygon, and two-finger navigation remains assigned to the canvas. Trace a loop, lift, then drag from inside the selection's combined bounds to move the group. A second loop outside the bounds replaces the selection. Switching modes clears it.

Object selection tests polygon/rectangle containment and edge crossings. Stroke selection samples the visible masked path ranges every 2 points in path space, applies the stroke's transform, and tests point containment and segment/polygon intersections. It selects **whole strokes** by their centerlines, not partial strokes or the full brush footprint. Empty paths and hidden mask ranges are excluded. Index-based selection is invalidated by subsequent drawing edits.

During a move, preview snapshots update both layers without undo registration. Ending restores the initial snapshot then commits the final one as a single action. Cancelling restores the initial snapshot without an undo entry. Translation is clamped as one group to the fixed document bounds. Arbitrarily large scaled strokes, dense lasso paths and large documents need further profiling.

## Undo experiment

`SpikeCanvasView.undoManager` returns the same document-level `UndoManager` used by `SpikeHistory`. Native PencilKit tool sessions are explicitly grouped by begin/end tool delegate callbacks. Custom edits register an inverse complete snapshot; applying a snapshot disables registration around programmatic `drawing` assignment to avoid duplicate entries. Redo registers the inverse transaction. Undo history is capped at 50 actions.

Insert answer deliberately adds a text object **and** a blue ink underline in one action. Tests verify one undo removes both, redo restores both, mixed moves undo together, cancellation leaves no entry, and separate synthetic ink actions remain individually undoable. Synthetic ink actions are not proof of native Pencil stroke/eraser undo. Actual PencilKit input timing and its undo registration still require the physical checks below; no private API workaround is used.

## Measurements and evidence

Environment: Xcode 27.0 (27A266a), iOS 27.0 simulator, iPad (A16), UUID `709D6F70-328D-4458-8F8A-B2C47A945A80`. These are simulator observations on the development Mac, not measurements of A16 hardware.

| Check | Result / limitation |
|---|---|
| Debug simulator build | Passed with the canonical build command |
| Hosted tests | 14 passed: 11 spike tests plus 3 scaffold placeholders; no failures |
| Release simulator build | Passed; spike code and home-menu entry are excluded by `#if DEBUG` |
| Alignment | No visible drift in the three seeded screenshots; automated view-coordinate checks also passed |
| Z-order | Both orders rendered; opaque-object occlusion confirmed for Ink below |
| Stress fixture | Exactly 2,000 synthetic strokes (24 control points each), 50 objects within 4,000 × 4,000 points |
| Simulator memory sample | Screenshot: 79 MiB current, 86 MiB sampled peak; no 1 GiB stop triggered in this run |
| Display-link sample | Screenshot: approximately 20 missed frames over 1,420 intervals; idle after load, with a concurrent host build; not a scrolling benchmark |
| Physical A16 memory / scrolling / latency feel | NOT RUN |
| Actual finger/pinch/Pencil gesture dispatch | NOT RUN; Simulator is not exposed by the available computer-use surface |
| Owner + Claude review | Pending |

`SpikeMetrics` samples `task_vm_info.phys_footprint` once per second and reports a sampled peak. `CADisplayLink` estimates missed frames from timestamp gaps divided by the expected interval; it is not GPU instrumentation or a stroke-latency measure. Measurements reset on screen appearance or fixture reset. At a sample ≥1,024 MiB, the prototype stops canvas interaction and displays a stop message. Sampling cannot capture every transient allocation or prevent an allocation-time OOM. Record foreground continuous runs; interruptions/backgrounding can distort frame counts.

Screenshots, all visually inspected:

- [0.25×, ink above](../../tests/evidence/004/zoom-025-ink-above.png)
- [1×, ink above](../../tests/evidence/004/zoom-100-ink-above.png)
- [4×, ink above](../../tests/evidence/004/zoom-400-ink-above.png)
- [1×, ink below](../../tests/evidence/004/zoom-100-ink-below.png)
- [2,000 strokes / 50 objects, simulator monitor](../../tests/evidence/004/stress-simulator.png)

UIKit label rendering becomes soft when magnified at 4×; high-resolution object rendering remains production work. No production document-capacity or performance claim follows from these fixtures.

## Repeatable commands

Use the canonical build/test commands in [AGENTS.md](../../AGENTS.md). For the Release exclusion check, add `-configuration Release` to the build command. For screenshots after building and installing the Debug product on the simulator:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch --terminate-running-process 709D6F70-328D-4458-8F8A-B2C47A945A80 com.chrixcrusher.pencilecho -spike004 -spikeZoom 0.25
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl io 709D6F70-328D-4458-8F8A-B2C47A945A80 screenshot tests/evidence/004/zoom-025-ink-above.png
```

Wait for launch/render completion before capturing. Repeat with zoom `1` and `4`. Add `-spikeInkBelow` for the alternate order or `-spikeStress` for the synthetic load. Do not relaunch/terminate the app while hosted tests are running. These arguments affect only a Debug launch and never write documents.

## Physical A16 procedure — pending

Install the reviewed Debug build in place using the owner's locally configured free Personal Team; preserve existing documents and never uninstall as a test step. Record actual OS/build, device, app source snapshot, orientation and display configuration. Use iPad A16 / Apple Pencil USB-C.

1. Open the spike through the Debug menu. Draw two separate Pencil strokes. Undo each independently, redo both, then repeat after using the eraser. Try Undo/Redo buttons and standard keyboard shortcuts if a keyboard is available.
2. Pan with one finger and pinch with two in Ink mode; verify no new stroke appears. Repeat with Pencil disconnected. In lasso mode, verify two-finger pan/pinch and that cancelled gestures restore previews.
3. At 0.25×, 1× and 4×, draw near objects, pan, pinch and rotate between portrait/landscape. Capture alignment screenshots; test both z-orders. Stop and report if alignment drifts.
4. Trace a loop around the first label and its underline; confirm the status selects both. Move the group, undo and redo; both must move together. Test a masked/erased stroke and an image/box selection too.
5. Insert answer. One undo must remove both the text object and blue underline; redo restores both. Draw a new Pencil stroke afterward and verify it has its own undo step.
6. Load 2,000 / 50. Record memory current/peak after settling and after at least 30 seconds of continuous pan/zoom at multiple scales. Record display-link intervals/missed estimate and preferably an Instruments trace. Write a latency-feel observation with Pencil; do not infer it from frame counters.
7. Stop on ~1 GiB footprint, alignment drift, or an undo failure that would need private APIs. Do not promote this approach into ticket 008 until the failures are understood and Owner + Claude review is recorded.

## API evidence

Implementation signatures were checked against the installed iPadOS 27 SDK. Apple documents that [pencilOnly permits only Pencil drawing](https://developer.apple.com/documentation/pencilkit/pkcanvasviewdrawingpolicy) and that [maskedPathRanges describes the path inside the mask](https://developer.apple.com/documentation/pencilkit/pkstroke-swift.struct/maskedpathranges). Runtime and hardware acceptance remain separate from those API contracts.

## Verification notes

The canonical simulator build and test commands succeeded; the final test run reported 14 tests in 4 suites passed (11 spike assertions/behavior tests, 3 scaffold placeholders). Gesture-handler tests feed deterministic pan states into the real lasso handler, including move/undo and cancellation; they do not synthesize touch dispatch. The Release build also succeeded. Xcode emitted the existing AppIntents metadata-skipped warning; the test runtime emitted a PointerUI XPC diagnostic without test failures.

The first test attempt was interrupted by relaunching its host app during verification. It was discarded and rerun without simulator interaction; the subsequent runs passed. No signing changes or global Xcode selection changes were needed. Context validation was not rerun for this ticket; ticket 002 records its existing excluded-upstream link failure. The workspace has no root Git metadata, so no commit or PR was created. No ticket scope was added beyond this debug experiment.

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
