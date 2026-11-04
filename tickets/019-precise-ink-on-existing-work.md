# 019 — Precise ink on existing work (mazes, graphs, geometry)

Milestone: PE-003 · Status: Open · Owner: Unassigned · Depends on: 016, 017

## What

Let AI ink answers draw accurately on top of the user's own drawing: a path through a hand-drawn maze, a tangent line on a sketched graph, an angle mark on a triangle. The answer must line up with the existing ink and must not cross what it should avoid.

## Why

PenEcho's demo (https://www.youtube.com/watch?v=TQki5P37qno, about 0:24–0:31) draws a maze, writes "find path", and gets the solution path drawn inside the maze corridors.

Pencil Echo can already place `draw_ink` with `at_frame` over existing work, but:

- The capture is scaled to fit `maxImageSide` with at most 2× (`AskAIController`, `scale = min(2, maxImageSide / longest side)`), so thin hand-drawn walls can be hard to read precisely.
- `draw_ink` coordinates are in a local box that is scaled into the frame, so the model has to get both the box and the frame right; small errors move the whole path off the corridors.
- Nothing tells the model that ink drawn over existing work must stay between existing strokes.

Upstream sends a magnified duplicate of the attention region ("focusInset", `inspiration/src/server/canvas-command-prompt.js` line 720) and uses one global origin with integer coordinates for `draw` (line 148).

## Scope

- **Focus image.** When the attention region (ticket 017) is small compared to the context region, send a second, magnified image of it (for example up to 3× and the provider's image size limit). The prompt says it is for reading detail only and gives its own scale.
- **Page-coordinate ink.** Add an optional `draw_ink` mode where stroke points are page points (no local box, no scaling), for overlays on existing work. The validator checks every point is inside the page bounds and near the context region.
- **Overlay rules in the prompt:** trace inside open space (corridors, gaps), never across existing strokes unless asked; use a distinct color; keep the path continuous from the marked start to the marked end.
- **Grid hint (optional, behind a setting):** draw a faint coordinate grid with labels on the capture image only, if real-provider runs show it improves accuracy. Never drawn on the document.

## Exclusions

- Solving the maze on the device (image processing, path finding). The model solves it; the app only renders and validates.
- Snapping AI ink to user strokes.
- Erasing or editing the user's ink.

## Affected areas

`application/App/AskAI/AskAIController.swift` (focus image, request), `service/Providers/` (multi-image requests for every adapter), `shared/CanvasCommands/` (page-coordinate ink mode, validator), `service/AI/CanvasCommandPrompt.swift`, `docs/api/canvas-commands-v1.md`, `docs/api/providers.md`, `tests/PencilEchoTests/`.

## Acceptance

- [ ] On a hand-drawn maze of about 6×6 cells, "find path" draws a continuous path from the entry arrow to the exit arrow that stays inside the corridors. *(Real provider, A16. Record how many of 5 tries succeed.)*
- [ ] "Draw the tangent at x = 1" on a sketched parabola places a line touching the curve near x = 1. *(Real provider.)*
- [ ] Page-coordinate ink outside the page or far from the context region is rejected with nothing changed. *(Validator tests.)*
- [ ] Requests with a focus image work for every provider adapter, or the focus image is skipped for providers that accept one image only.

## Automated checks

- Unit tests: focus image is created only when the attention region is small enough, with the correct scale and rectangle in the request.
- Adapter tests: OpenAI-compatible, Anthropic and Gemini request bodies carry two images in the right order.
- Validator and converter tests for page-coordinate ink.
- Fixture test: a recorded maze answer converts to strokes at the expected page positions.

## Device and provider gates

Owner A16 run with a real provider. Accuracy depends on the model; record the model name with the results in `docs/testing/`.

## Stop conditions

Stop and ask the owner if the selected models solve fewer than 2 of 5 maze tries even with the focus image; the remaining option (the grid hint, or on-device path finding) needs an owner decision.
