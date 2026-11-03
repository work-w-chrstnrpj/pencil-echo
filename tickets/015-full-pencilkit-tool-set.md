# 015 — Full PencilKit tool set

Milestone: PE-001 · Status: In Progress — implemented and simulator-verified (2026-11-04); owner A16 check pending · Owner: Claude · Depends on: 008

## What

Offer every PencilKit drawing tool in the editor's tool picker, not just pen, marker, vector eraser and lasso.

## Why

Owner A16 run (2026-11-04) said the pen choice is too limited. `DocumentEditorController.toolPicker` builds its tool list by hand: `.pen`, `.marker`, `PKToolPickerEraserItem(type: .vector)` and `PKToolPickerLassoItem()`.

## Scope

- Add the pencil, monoline, fountain pen, watercolor and crayon inking items, the pixel eraser and the ruler. Check each against the deployment target, because some inking types need iOS 17 or later.
- Or use the system default `PKToolPicker()` item set if it covers the same tools.
- Keep the selected tool and color across document reopen if PencilKit does not already.
- Make sure every ink type renders correctly in `RegionCapture` (for Ask AI) and in `ThumbnailRenderer`.

## Acceptance

- [ ] Every tool above can draw, erase and save, and the strokes survive reopen. *(The picker shows them in the simulator; drawing with each tool still needs the A16 check.)*
- [ ] Ask AI captures and thumbnails show watercolor and crayon strokes. *(Both use `PKDrawing.image`, which renders every ink type. Not checked by eye yet.)*
- [ ] Owner A16 check.

## Implementation notes (2026-11-04)

`DocumentEditorController.toolPicker` now lists pen, monoline, fountain pen, marker, pencil, crayon, watercolor, eraser (its options switch between object and pixel erasing), lasso and ruler. `stateAutosaveName = "editor.toolPicker"` keeps the last tool and color across documents. The deployment target is iPadOS 27, so every ink type is available.

