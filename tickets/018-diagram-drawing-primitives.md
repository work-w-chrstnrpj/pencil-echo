# 018 — Diagram drawing: arrowheads, arcs, wavy lines and labels

Milestone: PE-003 · Status: In Progress — fixture-tested on the iPad (A16) simulator (2026-11-05); owner A16 run with a real provider pending · Owner: Grok · Depends on: 016

## What

Let AI ink answers draw labeled diagrams: arrows with arrowheads, arcs, wavy and zigzag lines, filled shapes, and text labels placed with the drawing. This covers Feynman diagrams, free-body diagrams, circuits, flowcharts and geometry sketches as native ink.

## Why

PenEcho's demo (https://www.youtube.com/watch?v=TQki5P37qno, about 0:44–0:55) answers "Draw a simple Feynman diagram showing electron–positron annihilation, e⁺e⁻ → μ⁺μ⁻, mediated by a virtual photon" with a labeled diagram.

Pencil Echo's `draw_ink` only has `line`, `polyline`, `smooth` and `ellipse` strokes (`InkStrokeSpec.Kind` in `shared/CanvasCommands/CanvasCommands.swift`). There are no arrowheads, no arcs, no wavy photon lines, no fills, and labels can only be separate text objects placed by the flowing layout, so they don't line up with the drawing.

Upstream `draw` has `line|smooth|rect|ellipse|circle|arc` items with `closed`, `fill` and `arrows` index lists (`inspiration/src/server/canvas-command-prompt.js` line 148, `inspiration/src/shared/finish-drawing.js`).

## Scope

- **Canvas commands v3** for `draw_ink` (spec in `docs/api/canvas-commands-v1.md`, versioned like v2; v1 and v2 answers still accepted):
  - New stroke kinds: `arc` (center, radii, start and sweep angles), `rect`, `wave` (sine wave along a polyline, with amplitude and wavelength) and `zigzag`. `wave` and `zigzag` are expanded into points on the device, so the model sends a few numbers instead of many points.
  - Per-stroke `arrow`: `none`, `end`, `start`, `both`, or `mid` (arrowhead halfway along, as on fermion lines). Arrowheads are drawn as two short strokes sized to the pen width.
  - Per-stroke `fill` for closed shapes (vertices, dots), drawn as dense PencilKit ink or a filled path.
  - **Labels:** optional `labels` on the drawing: short text or LaTeX (`e^-`, `\gamma`, `\mu^+`) at a point in the drawing's local box. They are placed with the drawing and become separate editable text/LaTeX objects in one undo step.
- **Limits:** the existing 64 strokes / 2,048 points still apply after `wave` and `zigzag` are expanded; at most 16 labels of 40 bytes each; angles and amplitudes finite and bounded. Over-limit answers are rejected with nothing changed.
- **Prompt:** describe the new kinds and when to use them (wavy line for photons, curly for gluons as `wave` with small wavelength, arrows on fermion lines, labels next to lines), ported from the upstream draw policy (provenance per ticket 003).
- Update `docs/database/document-schema-v1.md` only if labels need a new object link; otherwise labels are ordinary AI objects.

## Exclusions

- HTML or SVG widgets and the upstream `diagram_source` renderer (PE-006).
- Automatic graph layout from a semantic description (nodes and edges without coordinates).
- Curly gluon loops as a dedicated primitive; approximate them with `wave`.

## Affected areas

`shared/CanvasCommands/CanvasCommands.swift`, `shared/CanvasCommands/CommandValidator.swift`, `shared/schemas/canvas-commands-v1.json`, the ink answer converter used by `application/App/AskAI/AskAIController.swift`, `service/AI/CanvasCommandPrompt.swift`, `docs/api/canvas-commands-v1.md`, `docs/reuse-inventory.md`, `tests/PencilEchoTests/`, `tests/fixtures/providers/`.

## Acceptance

- [ ] The Feynman diagram request above places a diagram with two incoming fermion lines with arrows, a wavy photon line between two vertices, two outgoing lines and readable particle labels next to each line. *(Real provider, A16.)*
- [ ] "Draw a free-body diagram of a block on an incline" places labeled force arrows. *(Real provider.)*
- [x] A drawing and its labels are one undo step, and labels stay editable. *(Simulator: `aDrawingAndItsLabelsAreOneUndoStep`. Labels are ordinary text/LaTeX objects.)*
- [x] Malformed or over-limit `arc`, `wave`, `zigzag`, arrow and label values are rejected with nothing changed. *(Validator tests.)*

## Automated checks

- Validator tests for every new field, including limits after `wave`/`zigzag` expansion and v1/v2 compatibility.
- Converter tests: arc endpoints, wave amplitude/period, arrowhead direction at the end, start and middle, fill coverage.
- Fixture test: a recorded Feynman-diagram answer validates, converts and places the drawing plus labels.
- Schema test: `canvas-commands-v1.json` accepts the new fields and rejects unknown ones.

## Device and provider gates

Owner A16 run with a real provider for the Feynman and free-body diagram prompts.

## Stop conditions

Stop and ask the owner if models can't produce usable coordinates for labeled diagrams even with these primitives; the fallback is the PE-006 widget renderer, which is a larger scope change.

## Implementation notes (2026-11-05)

Version 3 `draw_ink` adds `arc`, `rect`, `wave` and `zigzag`, plus `arrow`, `fill` and up to 16 labels of 40 bytes. Waves and zigzags expand on device; the 64-stroke / 2,048-point budget applies after expansion. Version 1 and 2 answers still validate. Labels are ordinary text or LaTeX objects in the same undo group as the ink, so `document-schema-v1` did not change. Placed AI ink is recolored to the canvas AI ink color at apply time. The recorded Feynman fixture validates and places the drawing plus five labels. Evidence: [diagrams-018-019.md](../docs/testing/diagrams-018-019.md). Real-provider Feynman and free-body runs were not done.
