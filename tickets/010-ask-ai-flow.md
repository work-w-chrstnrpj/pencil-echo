# 010 — Ask AI: capture, request, validate, place, undo

Milestone: PE-002 · Status: In Progress — implemented and simulator-verified; real provider and owner A16 runs pending · Owner: Claude (taken over to parallelize) · Depends on: 004, 006, 007, 008

## What

The core loop: select a handwritten problem (or use the visible area), ask the AI, and place a validated, editable answer beside it as one undo step.

## Why

This is the product's primary acceptance gate (`docs/product-specification/product-specification.md`).

## Scope

- **Trigger:** "Ask AI" button + optional instruction field (default: "Solve and explain"). With a mixed-lasso selection, capture that region + ~24 pt margin; otherwise capture the visible viewport.
- **Capture:** render ink + objects in the region to PNG (cap long edge ~2048 px), record `requestId`, document `revision`, region frame and page ID. Capture is immutable.
- **Request:** system prompt ported from `inspiration/src/server/canvas-command-prompt.js` (trimmed to v1 commands, with provenance), JSON schema from 006, image from capture, via the selected provider (007).
- **Pending UI:** non-blocking indicator near the selection with Cancel. Drawing stays responsive.
- **Validate:** `CommandValidator` (006). Invalid → error banner with Retry (manual only). No partial apply.
- **Stale:** if `revision` changed **inside the captured region** during the request → review card ("Your problem changed. Place answer anyway?" Place / Discard). Changes elsewhere don't count; note how this is detected.
- **Place:** first free space right of the region, else below, else expand canvas/next page. Never overlap the original ink.
- **Apply:** all operations in one undo group, objects tagged `createdBy: ai:<requestId>`, then autosave.
- **Offline / network error:** keep the instruction + capture so the user can tap Retry; never auto-retry; never switch providers.
- Conversation: store request/answer text in the document (`conversation.json`, already defined in `docs/database/document-schema-v1.md`) for later chat (PE-003).

## Exclusions

Suggestions, auto-solve, chat UI, diagrams, whole-document context.

## Acceptance

- [ ] Handwritten equation → answer appears beside it as editable Markdown/LaTeX objects.
- [x] One undo removes the whole answer; redo restores it.
- [x] Editing the problem during a pending request shows the review card.
- [x] Cancel discards the late response.
- [ ] Airplane mode → error with Retry; original content untouched.
- [x] Save/reopen keeps a retained answer and doesn't resurrect an undone answer.
- [ ] Unit tests for placement, stale detection and duplicate request IDs; owner A16 + real-provider run recorded separately.

## Implementation evidence — 2026-11-03 (Claude)

**Files**
- `service/AI/CanvasCommandPrompt.swift`: system prompt translated and trimmed from upstream `canvas-command-prompt.js` (provenance header). It includes a user turn carrying `captureFrame`, `imageScale`, `pageBounds` and `allowReplace`, and the one allowed Markdown-fence strip.
- `service/AI/AnswerPlanner.swift`: three pure helpers.
  - `AnswerPlacement` sizes answers and finds free space right of the region, then below it, never overlapping ink or objects.
  - `ScopeFingerprint` detects whether the captured region changed.
  - `Conversation.recordingAnswer` records the exchange, with an applied request kept on undo and the 2,000-message / 16 KB limits.
- `application/App/AskAI/AskAIController.swift`, the lifecycle `idle → pending → idle | review | failed`:
  - **Capture:** the region is clipped to the page under its centre and rendered to PNG at up to 2×, long edge ≤ 2,048 px, with light ink so dark-mode ink stays visible.
  - **Validation:** `CommandValidator`, with no partial apply.
  - **Placement:** right of the region, then below it; a full canvas grows its page, and a full notebook page uses the next page, adding one if needed. `at_frame` is kept only when it doesn't land on ink.
  - **Applying:** one `applyAIAnswer` = one undo step; objects are tagged `ai:<requestId>`.
  - **Failure:** provider errors and invalid output keep the capture for a manual Retry with the same request ID. Cancel drops late responses. A non-vision model is refused before sending. Nothing retries automatically and the provider never switches.
- `AskAIEditorContainer.swift` and `AskAIOverlay.swift`:
  - The instruction field (default "Solve and explain") and Ask AI button.
  - A non-blocking "Asking AI…" card with Cancel.
  - The review card ("Your problem changed. Place answer anyway?" Place / Discard) and the error banner with Retry.
- Editor hooks (agreed with the 008 session):
  - `EditorSession.conversation` and `applyAIAnswer`, which sets the conversation before `commit`, so it is not undoable.
  - `DocumentEditorController.askAIRegion`: the mixed selection + 24 pt, else the visible area.
  - `DocumentEditorRepresentable.onMake`.

**How staleness is detected**

At capture time, the ink strokes whose bounds intersect the region are fingerprinted (bounds, point count, transform, ink, mask), together with the objects intersecting it (id, frame, source). When the answer arrives, the fingerprint is recomputed. Review is shown only if the revision changed *and* the fingerprint differs, so edits elsewhere on the page are placed directly.

**Verification**
- `AskAITests`: 20 tests with a fake provider and fake document covering prompt, fence stripping, placement, fingerprints, conversation, valid/stale/discard/elsewhere/cancel/network-retry/invalid/duplicate/non-vision/read-only, notebook overflow to a new page, canvas growth, `at_frame` kept or moved off ink, and capture clipping and size.
- `AskAIEditorTests`: 4 tests on the real `EditorSession` and `DocumentStore`. One undo removes the whole two-object answer and redo restores it; save/reopen keeps the answer; an undone answer stays gone after saving while its applied request is kept; answers don't overlap the problem ink; a read-only session ignores answers.
- The documented test command: **141 tests in 11 suites passed** (iPad (A16) / iOS 27.0).
- Simulator: the editor shows the Ask AI bar. With no key saved, Ask AI shows the provider's missing-key message with Retry, and the page is unchanged. Screenshot: `tests/evidence/010/missing-key-retry.png`.

**Not done or not verified**
- A real Qwen request on the owner's A16. This needs a key, which can only be entered in Debug builds (Debug → Qwen vision test (007)) until ticket 012 adds settings. The provider and model come from the 007 Qwen preset.
- Airplane mode on the device: the network-error path is unit-tested only.

**Deviations**
- The pending card and review card sit at the top of the editor, below its tool row, not next to the selection. The system tool picker covers the bottom of the screen.
- Ask AI is a bar in the editor rather than a toolbar button, so the instruction field is always at hand.

**Not part of 010**
`tests/PencilEchoUITests/LibraryUITests.swift`, added by someone else for 009, has two failing assertions in `testDamagedPackageAndAccessibilityTextSize` (expects `library-document-*` identifiers).

