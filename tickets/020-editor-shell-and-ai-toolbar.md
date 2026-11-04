# 020 — Editor layout: top bar, AI toolbar and settings panel

Milestone: PE-002 · Status: Implemented; native checks/builds verified; simulator and owner gates open · Owner: Codex · Depends on: 008, 010, 012, 014, 015

## What

Give the editor a layout like PenEcho's: a top bar for the document, a floating toolbar for AI, view and document controls, and settings that open as a side panel without leaving the document. Apple's floating tool picker (`PKToolPicker`) stays and remains the only place to pick pens, erasers, lasso, colors and widths.

## Why

Owner review of PenEcho's editor (2026-11-04, screenshot of the web app) asked to take inspiration from its commands and navigation. Today the editor only has a Done button, the document title (`DocumentEditorView`) and a floating "Ask AI" button (`AskAIOverlay`). Auto Ask and its delay can only be changed in the AI Settings sheet, which opens from the library (`LibraryView`), not from a document.

Owner decision (2026-11-04): **build our own toolbar and keep Apple's tool picker** for drawing. The picker keeps Pencil double-tap and squeeze, the ruler, the system color picker and the behavior iPad users expect. Our toolbar holds only what the picker doesn't have.

Upstream reference (layout and interaction only, not code or styles): `inspiration/public/index.html` lines 36–275 (document meta, status, file actions, toolbar, Auto AI delay popover, reasoning effort, AI color, hand tool, undo/redo, fullscreen, grid).

## Scope

- **Top bar** (SwiftUI toolbar on the editor's navigation bar):
  - Leading: back to the library, then the document name. Tap the name to rename it in place (same limits as `LibraryView` rename).
  - Save state: "Saved", "Saving…" or "Not saved", taken from the editor session's autosave.
  - Center: AI status ("Ready", "Asking…", "Placed", or an error), replacing the floating status labels in `AskAIOverlay`.
  - Trailing: new canvas, new notebook, export PNG of the current page (share sheet), settings.
- **Floating AI toolbar** (one compact bar above the canvas, draggable to the top or bottom edge, never covering the tool picker):
  - **Run AI** (the existing Ask AI action).
  - **Auto / Manual** switch. A long press or chevron opens a popover with the pause delay (1–10 s), stored in `AutoAskSettings`.
  - **Reasoning level** menu (Off, Low, Medium, High), shown only when the selected model supports it. Map it per adapter: OpenAI-compatible `reasoning_effort`, Anthropic extended thinking budget, Gemini thinking budget. Store it per provider in `ProviderSettings`. If this turns out larger than a day of work, split it into its own ticket.
  - **AI ink color**: 8 swatches. Today AI answers are always blue (`DocumentObject.rendersHandwritten`).
  - **Hand mode**: turns off drawing so a finger or Pencil only scrolls and zooms (`PKCanvasView.drawingPolicy` / `isDrawingEnabled`).
  - **Undo and redo** buttons (the editor's undo manager), for users who don't use the three-finger gesture.
  - **Grid toggle**: show or hide the page background pattern (`PageBackgroundView`), stored per document.
  - **Fullscreen**: hide the top bar and AI toolbar; a small button brings them back.
- **Settings side panel:** on iPad regular width, the settings open as a trailing panel next to the document. On compact width they open as the existing sheet. The panel reuses `AISettingsView` and adds:
  - A list of saved AI connections (provider + model) you can switch with one tap. This builds on `AISettings.providers`; switching only changes `selectedPresetID` and the model.
  - Canvas preferences: Auto Ask on/off, AI font (Handwritten, Rounded, System), thinking indicator on/off (a small animated mark at the capture region while a request is pending).
  - About: version, third-party notices.
- **Accessibility:** every control has a label and hint, works with VoiceOver and keyboard, supports Dynamic Type in the settings panel, and keeps 44 pt touch targets.

## Exclusions

- Replacing or duplicating `PKToolPicker` tools (pen, eraser, lasso, ruler, ink color, width).
- Text tool, shapes/graph assist, image and clipboard insert (PE-004 import work).
- Cloud account, share to cloud, plugins, internet search, CLI connections (not feasible on iPad or not in scope).
- Language and theme switches. The app follows the system language and appearance.
- Copying PenEcho's name, logo, icons, CSS or brand colors.

## Affected areas

`application/App/Editor/DocumentEditorView.swift`, `DocumentEditorController.swift`, `EditorSession.swift`, `PageBackgroundView.swift`, `application/App/AskAI/AskAIOverlay.swift`, `AskAIController.swift`, `application/App/Settings/AISettingsView.swift`, `service/Providers/AISettings.swift` and the three adapters (reasoning level), `shared/Document/` (grid flag, if stored per document), `docs/api/providers.md`, `docs/database/document-schema-v1.md`, `tests/PencilEchoTests/`, `tests/PencilEchoUITests/`.

## Acceptance

- [ ] In a document, Auto/Manual, the pause delay, AI color and reasoning level can be changed without leaving the document, and the next request uses them.
- [ ] Renaming from the top bar updates the library.
- [ ] The save state shows "Saving…" then "Saved" after drawing.
- [ ] Hand mode stops drawing; scrolling and zooming still work.
- [ ] The grid toggle hides and shows the page pattern and is remembered when the document is reopened.
- [ ] Fullscreen hides the bars and one tap brings them back.
- [ ] Settings open as a side panel in landscape on the A16 and as a sheet in Split View compact width.
- [ ] The tool picker still appears and works as before.
- [ ] VoiceOver reads every toolbar control by name. *(Owner A16 check.)*

## Automated checks

- Unit tests: reasoning level request mapping for each adapter, and hidden when unsupported; AI color and font stored and applied to new AI objects; grid flag persistence and migration.
- UI tests: open a document, toggle Auto/Manual, change the delay, rename from the top bar, toggle the grid, enter and leave fullscreen, open settings.
- Snapshot or screenshot evidence for regular and compact widths in `tests/evidence/020/`.

## Device and provider gates

Owner A16 run in landscape and portrait with Apple Pencil, and one real-provider request with a reasoning level set.

## Stop conditions

Stop and ask the owner if the floating toolbar and `PKToolPicker` overlap in a way that can't be solved by placement, or if a provider's reasoning setting changes the answer format the validator expects.

## Implementation record — 2026-11-04

Implemented in the shared checkout following the ticket sequence. Runtime source and meaningful regression checks are present; acceptance checkboxes above remain evidence gates, not claims from code inspection. See [verification report](../docs/testing/editor-shell-and-chat-020-021.md) for current commands, results, deviations and retained owner/device/provider checks. Existing concurrent work on 017–019 and 022 is preserved.

Verification: Debug/Release simulator builds and hosted/UI test-target builds passed; the combined native source check passed 80 assertions. Hosted runtime and UI execution were blocked by simulator boot stalls. Physical A16/Pencil/VoiceOver and real-provider acceptance are still pending; no full-suite or UI passing run is claimed.
