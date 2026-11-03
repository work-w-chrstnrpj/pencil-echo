# 016 — Visual answers: plots, drawings and illustrations

Milestone: PE-003 · Status: In Progress — implemented, fixture-tested and installed on the A16 (2026-11-04); owner real-provider run pending · Owner: Claude · Depends on: 006, 010, 014

## What

Let Ask AI answer with graphics: function plots, native ink drawings and illustrations. Today canvas commands v1 can only add `text`, `markdown` and `latex` objects (`shared/CanvasCommands/CanvasCommands.swift`), so "plot y = x²" or "draw a cat" cannot produce a picture.

## Why

Owner A16 run (2026-11-04): "It can't even generate picture when I ask for a graph or draw a cat." PenEcho's command set has `plot_function`, `draw` (native ink strokes), `html_widget` (inline SVG/HTML) and `erase`, alongside `write_text` and `draw_formula` (`inspiration/src/server/canvas-command-prompt.js`, `inspiration/src/shared/finish-drawing.js`, `inspiration/src/shared/illustration-style.js`).

## Scope

- Canvas commands v2 (spec in `docs/api/`, a schema migration, validator limits):
  - **`plot_function`:** expression, x/y range and parameters. Rendered natively (Swift Charts or Core Graphics) as an editable plot object.
  - **`draw`:** bounded native ink (lines, polylines, smooth curves, ellipses and arcs, with point and stroke limits taken from upstream `finish-drawing.js`). Converted to `PKStroke`s and added to the drawing as one undo step.
  - **`svg`:** a sanitized static SVG for illustrations ("draw a cat"). No scripts, no external references, size limits. Stored as an asset-backed image object.
- Port the upstream `plot` and `create_visual` prompt policies (provenance per ticket 003).
- Document schema change for plot and SVG objects (ticket 005 migration rules).

## Exclusions

- Interactive HTML widgets, animation scenes and the Canvas Agent.
- Image generation through provider image APIs (not every provider offers it, and it isn't free).

## Acceptance

- [ ] "y = x²" with a plot request places a correct plot beside the ink. *(Plot rendering and placement verified in the simulator and tests; the model's plot output needs a real provider run.)*
- [ ] "draw a cat" places a recognizable drawing beside the request. *(Ink conversion and placement are tested; drawing quality depends on the model and isn't verified.)*
- [x] Malformed or oversized drawings are rejected with nothing changed. Fixture and validator tests.
- [ ] Owner A16 run with a real provider.

## Implementation notes (2026-11-04)

- **Scope change:** drawings are native ink (`draw_ink`) instead of SVG. Ink fits a handwriting notebook, can be erased and moved like the user's strokes, and needs no SVG sanitizer or image assets. SVG illustrations stay out of scope.
- **Plots:** a new `plot` object type. Its source is the editable `PlotSpec` line format (`shared/CanvasCommands/PlotSpec.swift`), checked by a bounded expression parser (`MathExpression`) and drawn by `PlotRenderer` through `RichTextRenderer`. Objects, thumbnails, Ask AI captures and the source editor's live preview all use it. Users can add one with f(x) → Graph. No asset is stored.
- **Commands:** answers are now version 2 (`docs/api/canvas-commands-v1.md`, "Version 2"); version 1 answers are still accepted. The provider schema and prompt describe `plot` and `draw_ink`, with the prompt rules ported from upstream `plot`/`create_visual`/finish-drawing policies.
- **Ink answers:** `InkAnswer` turns each stroke into a PencilKit pen stroke. Smooth strokes become Catmull-Rom curves, and ellipses are sampled at 64 points. Ink placed at an exact frame may overlap existing work (circles, arrows); otherwise it flows beside the newest ink like text answers.
- **Document schema:** `plot` was added to v1 as an additive pre-release change (`docs/database/document-schema-v1.md`).
- **Verified:** 201 unit tests pass (11 new for 016). In the simulator, the f(x) → Graph preview renders y = x² with grid, axes and labels. A Debug build signed with the free Personal Team was installed and launched on "iPad ni Paj".

