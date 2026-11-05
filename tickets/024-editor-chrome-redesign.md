# 024 — Editor chrome: one command bar, inspectors, clear AI controls

Milestone: UI/UX upgrade · Status: Resolved on simulator (2026-11-05); owner A16 check pending · Owner: **Claude (senior)** · Depends on: nothing (works on `main` as of `a9c8a0c`) · Reviewer: owner

Follow [the UI style guide](../docs/design/ui-style-guide.md). This is the highest-risk UI ticket: it touches the UIKit editor, PencilKit's tool picker and every editor control.

## Problem (owner review, 2026-11-05)

- Two rows of commands: the SwiftUI AI toolbar (`AskAIEditorContainer.aiToolbar`) and the UIKit editing row (`DocumentEditorController.makeToolbar`). Both scroll sideways.
- Duplicates: undo/redo in the AI toolbar, the UIKit row **and** Apple's tool picker; two grid buttons (grid toggle and page background).
- "Auto"/"Manual" is unclear. "Pause delay" is a separate chevron. A "move toolbar" button sits among real commands.
- Settings and chat are a hand-built `HStack` panel instead of a system inspector.
- Claude Code sharing is an icon-only laptop button with no status.

## Target design

```
┌ ‹ Library   Untitled Canvas ▾        [Select][Insert +][View]   [✦ Ask AI][Auto ▾]   [💬][⌘ Claude Code ●][⚙] ┐
│              Saved · Answer placed                                                                         │
│                                                                                                            │
│                              (page)                                                                         │
│                                                                                                            │
│                       ┌──────────── selection bar (only with a selection) ───────────┐                    │
│                       │  Edit text   Ask about selection   Delete                     │                    │
│                       └───────────────────────────────────────────────────────────────┘                    │
│                         ( Apple tool picker: pens, eraser, lasso, ruler, colors, undo/redo )              │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Navigation bar (the only command row):**

| Group | Items | Notes |
|---|---|---|
| Leading | Back to library | System back. Accessibility label "Library". |
| Title | Document name + **title menu** (`.toolbarTitleMenu`): Rename…, Export page as PNG, New canvas, New notebook | Replaces the "Document actions" button and the tap-to-rename title. |
| Subtitle | `navigationSubtitle`: save state · AI status · page "2 of 5" (notebooks) | Replaces the two caption labels. Errors don't go here; see overlays. |
| Editing | **Select** (toggle, `lasso.badge.sparkles` or similar, value On/Off) · **Insert** menu (`plus`): Text, Markdown, Formula, Graph; notebooks also "Add page after this one" · **View** menu (`eye`): Page style (Blank/Lined/Dotted/Grid, checkmarked), Show page pattern (toggle), Draw with finger (toggle; replaces "Hand mode", inverted meaning made clear), Full screen | All of the UIKit row moves here; the row is deleted. |
| AI | **Ask AI** (`sparkles`, `.glassProminent`, ⌘↩) · **Answer mode** menu showing "Auto" or "On request": "Answer automatically when I pause" (toggle), Pause before answering (1–10 s, `Picker` with 1, 2, 3, 5, 10 s), Reasoning (only for supported models, as today), AI ink color | One prominent action in the bar. |
| Trailing | **Chat** (inspector toggle, ⌘⇧C) · **Claude Code** status item · **Settings** (inspector toggle, ⌘,) · **Drafts** menu (only when drafts exist; shows count: "2 drafts" → Accept all / Discard all) | Claude Code item: when not sharing, `laptopcomputer` + "Claude Code"; when sharing, a capsule with a status dot (green connected, orange waiting) and text. Tap → popover with `MCPShareView(target:)` (content restyled in ticket 027). |

At compact width the system overflow menu takes the lowest-priority items (View, Settings, Claude Code) automatically; verify nothing is lost.

**Removed:** the UIKit command row; our undo/redo buttons (tool picker and ⌘Z / ⌘⇧Z keep them); the grid toggle button (now in View); "Move toolbar" and the bottom-toolbar mode; the "Pause delay" chevron; the icon-only laptop button; `MCPShareBanner` at bottom-leading. Status moves into the Claude Code capsule, so the banner view is no longer placed. Leave the type itself alone; ticket 027 restyles it.

**Selection bar:** when a lasso selection exists (ink or objects), a small floating glass bar (`GlassEffectContainer`) appears just above the selection's bounds, clamped on screen and never under the tool picker. It holds Edit text (only for one text/Markdown/LaTeX object), Ask about selection (runs Ask AI on the selection), Delete. It hides while dragging.

**Inspectors:** Settings (`AISettingsView(onDone:)`) and Chat (`AgentChatView(controller:onClose:)`) move to `.inspector(isPresented:)`, one at a time, width 320–400. Remove the `HStack`/`Divider` panel and the compact `.sheet` (inspector handles compact). Their *content* is restyled by ticket 026; don't edit those files.

**Overlays:** `AskAIOverlay` becomes one glass card at the top center for review ("Your page changed. Place the answer anyway?" Place / Discard) and failure (message, Retry, Dismiss). Pending state is shown by the thinking indicator plus "Asking…" in the subtitle, with Cancel in the Ask AI button's menu (long-press / secondary action) and Esc.

**Full screen:** hides the navigation bar; one small glass "Exit full screen" button top-trailing (Esc also exits).

**Keyboard:** ⌘↩ Ask AI, ⌘⇧C Chat, ⌘, Settings, ⌘⇧F Full screen, Esc cancels a pending request / exits full screen, ⌫ deletes the selection.

## Files you own (only these)

- `application/App/AskAI/AskAIEditorContainer.swift`
- `application/App/AskAI/AskAIOverlay.swift`
- `application/App/Editor/DocumentEditorController.swift` (remove `makeToolbar`, expose the actions it called, selection-bar geometry)
- `application/App/Editor/DocumentEditorView.swift`
- New: `application/App/Editor/EditorSelectionBar.swift`, `tests/PencilEchoUITests/EditorUITests.swift` (+ `project.pbxproj` entries; this ticket is the only one adding files)
- `tests/PencilEchoUITests/LibraryUITests.swift`: **only** move `testRichSourceSaveCancelUndoAndReopen`, `testEditorShellControls`, `testChatFixtureAcceptReopenAndClear`, `testCompactSettingsSheet` into `EditorUITests.swift` and update them. Don't touch the other tests in that file (ticket 025 owns them).
- `tests/PencilEchoTests/EditorSessionTests.swift` / `AskAIEditorTests.swift` only if a moved action needs a unit test.

**Don't touch:** `Library/`, `Settings/`, `AgentChatView.swift`, `MCP/` (any file), `HomeView.swift`, models and services. Public initializers used here stay as they are: `AISettingsView(onDone:)`, `AgentChatView(controller:onClose:)`, `MCPShareView(target:)`.

## Acceptance criteria

- [ ] Exactly one command row (the navigation bar). The UIKit `makeToolbar` row and the SwiftUI `aiToolbar` are gone; no horizontal scrolling bar remains.
- [ ] No control appears twice: no undo/redo, lasso, color or pen controls outside the tool picker; one place for page pattern.
- [ ] Regular width (iPad A16 landscape and portrait): ≤ 8 visible top-level bar items besides back and title; compact (Split View ⅓): every action still reachable through the overflow menu.
- [ ] Every former action still works: select, insert text/Markdown/formula/graph, edit selected text, delete selection, page style, show pattern, add/delete page (notebook), draw with finger, full screen, rename, export PNG, new canvas/notebook, Ask AI, auto mode + delay, reasoning (supported models), AI ink color, chat, Claude Code, settings, accept/discard drafts.
- [ ] Selection bar appears only with a selection, stays on screen, never overlaps the tool picker, and hides during drag.
- [ ] Settings and Chat open as inspectors, one at a time, and as sheets at compact width; state survives rotation.
- [ ] Claude Code item shows "not sharing / waiting / connected" with symbol + text, and opens `MCPShareView` in a popover.
- [ ] Ask AI review and failure cards follow the style guide; Cancel and Esc stop a pending request.
- [ ] All keyboard shortcuts above work; VoiceOver reads every bar item with label + value; Dynamic Type AX3 doesn't clip the bar (items overflow).
- [ ] Tool picker visibility, Pencil drawing and Auto Ask behave as before (no regression in `AutoAskTests`, `AskAIEditorTests`).
- [ ] `EditorUITests` (moved + new journeys: insert menu, view menu, selection bar delete, inspector toggle, drafts menu) pass on a dedicated simulator; full unit suite passes.
- [ ] Screenshots (regular landscape, regular portrait, compact, full screen, selection bar) in `tests/evidence/024/`.

## Handoff

Claude implements this one. Branch `ui/024-editor-chrome` in its own worktree. Merges **last**, after 025–027, rebasing onto them (the only shared files are `project.pbxproj` and `LibraryUITests.swift`, handled as above).

## Implementation notes (2026-11-05)

- **One bar:** the UIKit `makeToolbar` row and the SwiftUI `aiToolbar` are gone. The navigation bar holds back (identifier `Done`, label "Library"), the title with a title menu (Rename…, Export page as PNG, New canvas, New notebook), a subtitle (save state · AI status · page n of m), and three groups: Select / Insert / View, Ask AI (`.glassProminent`, becomes Stop while pending) / Answer mode, then Chat / Claude Code / Settings. Undo and redo stay in Apple's tool picker and on ⌘Z / ⌘⇧Z.
- **Editor state:** `EditorChromeState` (`application/App/Editor/EditorSelectionBar.swift`) is written by `DocumentEditorController` (select mode, selection rect, pages, page style, notices) and read by the shell. The controller's editing actions are now internal methods.
- **Selection bar:** a `GlassEffectContainer` above the selection (or below it when there's no room), kept on screen and above the tool picker; Edit, Ask AI, Delete. It's hidden during drag. ⌫ deletes the selection.
- **Inspectors:** Chat and Settings use `.inspector`, attached **outside** the editor's `NavigationStack`. Inside it, the panels' own titles and Done buttons merged into the editor's bar (the editor title showed "AI Settings"). The panel content is padded above Apple's floating tool picker so the chat field can be tapped.
- **Drafts:** a glass capsule above the tool picker ("N drafts on the page", Discard all, Accept all) while chat is closed.
- **Cards:** review and failure cards are glass cards at the top; notices (former UIKit banner) are a dismissible glass card that leaves after 5 s.
- **Full screen:** hides the bar; a glass exit button top-trailing; ⌘⇧F toggles, Esc exits or stops a request.
- **Claude Code:** status capsule with a green/orange dot when sharing; opens `MCPShareView` in a popover. `MCPShareBanner` is no longer placed.
- **Tests:** four editor journeys moved to `EditorUITests.swift` and rewritten, plus two new ones (one command bar, selection bar). Findings: system menu items don't carry SwiftUI identifiers (find by label); toggles keep a menu open on iPadOS 27; with an inspector open in portrait the bar overflows, so Chat sits in the overflow menu (the panel has Close).

