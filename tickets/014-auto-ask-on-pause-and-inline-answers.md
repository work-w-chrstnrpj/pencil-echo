# 014 — Auto Ask on pause, newest-ink capture and inline answers

Milestone: PE-002 · Status: In Progress — implemented and simulator-verified (2026-11-04); owner A16 run with a real provider pending · Owner: Claude · Depends on: 010

## What

Make Ask AI behave like PenEcho's Auto AI: when the user stops writing, capture only the newest ink and write a short answer right next to it, with no button press.

## Why

Owner A16 run with a real Qwen provider (2026-11-04) found three problems:

1. **The answer lands far from the annotation.** With no selection, `DocumentEditorController.askAIRegion` captures the whole visible viewport. `AnswerPlacement.freeRect` then places the answer right of or below that whole region, which is usually the screen edge or the next page.
2. **You have to tap "Ask AI" every time.** In PenEcho, Auto AI fires after a configurable pause (`AUTO_AI_DELAY_SECONDS`, default 5 s; see `inspiration/src/server/main.js` and `inspiration/docs/pen-intelligence.md`, "Auto AI timing").
3. **`2+2=` gets a typed explanation instead of `4`.** The default instruction is `"Solve and explain"`, which asks for an explanation. The scope is also too wide for `at_frame` to point at the equals sign. Upstream's `solve` and `answer` policies say to add only the missing value right after the existing `=` and to include steps only when asked.

## Scope

- **Capture region:** bounds of the strokes added since the last answer (or since the document opened), plus the 24 pt margin. Fall back to the selection, then to the viewport. Pass the surrounding page as context only if needed.
- **Auto Ask:** a pause timer starts on `canvasViewDidEndUsingTool` and restarts on every new stroke. It does not fire while a request is pending, during lasso or eraser use, on a read-only document, or when no new ink exists. Settings: on/off and a delay of 1–10 s (default 2 s on iPad). The "Ask AI" button stays for manual use.
- **Prompt:** port the upstream `answer`/`solve` wording (provenance per ticket 003). Change the default instruction to answer the newest content directly. Prefer `at_frame` right after an `=` or in a blank, sized to the handwriting height. Add explanation only when the handwriting asks for it.
- **Look:** render short AI answers in a handwriting-like style, sized to the source ink and in a distinct ink color, so they read as written beside the prompt rather than as a text box.
- **Placement:** answer frames that fall back to flowing placement go directly right of the newest ink, then below it. They never jump to a new page while space remains near the source.

## Exclusions

- Pen gestures (circle to explain, underline to solve, etc.). Those are a later ticket.
- Plots, drawings and images. See ticket 016.

## Acceptance

- [ ] Writing `2+2=` and pausing places `4` immediately after the `=`, with no button press and no explanation text. *(Needs a real provider; the prompt asks for this, but model output isn't verified yet.)*
- [ ] Answers sit within about one line height of the newest ink in canvas and A4 documents. *(Owner A16 check.)*
- [x] No request while still writing, during a pending request, or on a read-only document. One request per pause.
- [x] Unit tests for the capture region, timer rules and placement. *(Owner A16 run with a real provider still pending.)*

## Implementation notes (2026-11-04)

- **Newest ink** (`AskAIController.newestInkRegion`): strokes whose `PKStrokePath.creationDate` is later than a watermark. The watermark starts at the newest stroke when the document opens and moves forward on each newest-ink capture. Creation dates survive lasso moves and erasing, so those don't count as new ink. Capture order: selection, newest ink, the last newest-ink region if it still has ink, then the viewport.
- **Auto Ask:** the editor reports tool begin and end (`DocumentEditorController.onToolBegan` / `onToolEnded`). Only inking tools start the timer. PencilKit can report the drawing change after the tool ends, so the controller checks for new ink when the timer fires. A pending request re-arms the timer. A held review answer or a selection skips it.
- **Setting:** `AutoAskSettings` is stored under its own UserDefaults key (`ai.autoAsk.v1`), on by default with a 2 s pause (1–10 s range). It appears in AI Settings → Auto Ask.
- **Prompt:** the default instruction is now "Answer the newest handwriting". The system prompt ports the upstream `answer`/`solve` rules: add only the missing result, use `at_frame` right after an `=`, and give steps only when asked.
- **Handwritten style:** objects with `createdBy: ai` render in Noteworthy at 26 pt in blue ink with no border (`DocumentObject.rendersHandwritten`). Text answers are sized to fit their text, and `at_frame` text keeps the requested vertical center. Math stays SwiftMath, tinted blue. The font size isn't matched to the user's ink height yet.
- **Simulator check:** the pause fired a request with no tap (the simulator has no key, so the expected key error showed), and existing AI answers show in handwriting.

