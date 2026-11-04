# 017 — Pen gestures and context around the newest ink

Milestone: PE-003 · Status: Open · Owner: Unassigned · Depends on: 010, 014

## What

Let the user point at existing work with the pen. A hand-drawn circle or box selects what is inside it. An arrow points to where the answer should go. A short label such as "why?", "more" or "explain" asks for detail about the selected content. The request also includes the content around the newest ink, so a short note like "find path" or "what func will this be like?" can refer to a drawing made earlier.

## Why

PenEcho's demo (https://www.youtube.com/watch?v=TQki5P37qno) shows two cases that Pencil Echo can't handle yet:

1. **Circle + "why?"** (about 0:55–1:05): the user circles a step in an earlier AI derivation, draws an arrow and writes "why?". The answer explains that step and is placed past the arrowhead.
2. **A note about earlier ink** (about 0:12–0:17 and 0:24–0:30): "what func will this be like?" refers to a curve drawn earlier, and "find path" refers to a maze drawn earlier.

Today the capture is the bounds of the newest strokes plus a 24 pt margin (`AskAIController.newestInkRegion`, `captureMargin`). If Auto Ask already fired on the maze, the next request sees only "find Path" and not the maze. The prompt (`service/AI/CanvasCommandPrompt.swift`) only reacts to the word "why" and has no rules for circles, boxes or arrows. Ticket 014 left pen gestures out on purpose.

Upstream handles both: `inspiration/src/server/canvas-command-prompt.js` line 127 (gesture rules and placement past the final arrowhead) and line 720 (`latestInput.imageRect` as the attention region inside a larger `captureRect`).

## Scope

- **Attention vs context region.** The newest-ink bounds stay the *attention* region. The capture becomes a larger *context* region: the attention region grown to include nearby ink and objects on the same page (for example a fixed growth of about 1.5× the attention size, at least 200 pt, clipped to the page and to `maxImageSide`). Send both rectangles in the request's user turn. The prompt says the attention region is the new request and the rest is context only.
- **Gesture rules in the prompt.** Port the upstream rules (provenance per ticket 003): a circle or box selects the content inside it; an arrow links the selection to a destination; labels like "why", "more", "explain", "detail" ask for a fuller explanation of the selection and are not copied into the answer; follow an arrow chain to its last arrowhead.
- **Placement past the arrowhead.** Answers to an arrow request go in clear space just beyond the final arrowhead (model `at_frame`, validated against page bounds). If the model gives no frame, place the answer next to the attention region as today.
- **AI objects in the capture.** Make sure earlier AI answers (text, Markdown, LaTeX, plots, AI ink) inside the context region are rendered in the capture image, so they can be circled and asked about.
- **Language.** If the newest input is only a control label ("more", "why"), answer in the language of the selected content.
- Add the new region fields to `docs/api/canvas-commands-v1.md` (request context) and the reuse row to `docs/reuse-inventory.md`.

## Exclusions

- Recognizing gestures on the device (shape classifiers, gesture-only commands without a model call). The model reads the gesture from the image.
- Lasso-scoped AI and chat (separate PE-003 work).
- Editing or replacing the circled AI object. Answers are added; `allowReplace` stays false.

## Affected areas

`application/App/AskAI/AskAIController.swift` (capture region, request context), `service/AI/CanvasCommandPrompt.swift`, `shared/CanvasCommands/` (request context type), `docs/api/canvas-commands-v1.md`, `docs/reuse-inventory.md`, `tests/PencilEchoTests/`.

## Acceptance

- [ ] Circling a step of an earlier AI answer, drawing an arrow and writing "why?" places an explanation of that step past the arrowhead, without copying "why?". *(Real provider, A16.)*
- [ ] Drawing a maze, pausing until Auto Ask fires, then writing "find path" sends a capture that contains the whole maze. *(Unit test on the region; real provider for the answer.)*
- [ ] Sketching a curve, then writing "what func will this be like?" next to it, gets an answer about that curve. *(Real provider.)*

## Automated checks

- Unit tests: context region grows around the attention region, includes nearby strokes and objects, clips to the page and the image size limit, and never shrinks below the attention region.
- Unit tests: the user turn contains both rectangles in page points with the correct `imageScale` mapping.
- Fixture test: a recorded model answer with `at_frame` past an arrowhead validates and is placed there.
- Capture test: AI text, LaTeX, plot and ink objects inside the context region appear in the rendered PNG.

## Device and provider gates

Owner A16 run with a real provider (Qwen first) for the three demo cases above.

## Stop conditions

Stop and ask the owner if a larger context region makes requests noticeably slower or more expensive on the selected provider, or if models routinely answer the old context instead of the newest ink.
