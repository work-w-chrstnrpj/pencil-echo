# 021 — Agent chat panel beside the canvas

Milestone: PE-003 · Status: Implemented; native checks/builds verified; simulator and owner gates open · Owner: Codex (starts after 017 and 020 merge) · Depends on: 010, 016, 017, 020

## What

Add a chat panel next to the document where the user can type (or dictate) a request about the canvas, such as "According to this diagram I drew, solve for the time of descent on both paths". The agent sees the current page or the lasso selection, replies in the chat, and places its answer on the canvas as editable drafts the user can accept or discard.

## Why

PenEcho's editor has an Agent panel next to the canvas (owner screenshot, 2026-11-04). The confirmed scope already includes a chat agent (`docs/decisions.md`, "Chat agent and opt-in, paired LAN MCP access"; PE-003 "Scoped captures, conversation"). Today Ask AI only takes handwriting. There's no way to give a longer typed instruction or follow up on an answer.

Upstream reference (behavior only): `inspiration/src/client/app/canvas-agent-runtime.js`, `assist-agent.js`, `inspiration/docs/canvas-agent-visual-explorer.md`, and the batch accept/discard controls in `inspiration/public/index.html` lines 55–58.

## Scope

- **Panel:** a trailing panel opened from the AI toolbar (ticket 020) and remembered per document. It shares the trailing area with the settings panel; only one is open at a time. On compact width it opens as a sheet.
- **Context:** each message sends the lasso selection if there is one, otherwise the visible part of the page, using the capture and context regions from ticket 017. A chip above the text field shows which ("Selection" or "Visible page") and can be tapped to switch.
- **Conversation:** keep up to the last 10 turns per document (text only; earlier images are not resent). Stored in the document package so it survives closing, and cleared with a "New chat" button. Add it to `docs/database/document-schema-v1.md` as an optional file following the ticket 005 migration rules.
- **Answers:** the reply text streams into the chat. Canvas commands in the reply go through the existing `CommandValidator` and placement, and are added as **drafts**: shown with a dashed outline until accepted. "Accept all" and "Discard all" buttons appear in the chat and the top bar while drafts exist. Each accept or discard is one undo step.
- **Status:** a "Working…" line with a Cancel button while a request is pending, using the same cancellable provider stream as Ask AI.
- **Privacy:** the "What is sent" section in settings explains that chat sends the selection or visible page plus recent messages to the selected provider.

## Exclusions

- Animated demonstrations, simulations and HTML widgets (the screenshot's request asks for one; that is PE-006). The agent answers with text, math, plots and ink only and says so if asked for an animation.
- Tools that edit or delete existing objects (`allowReplace` stays false).
- MCP or CLI agents (PE-005).
- Internet search.

## Affected areas

`application/App/AskAI/` (new chat view and controller), `application/App/Editor/DocumentEditorView.swift` (panel), `service/AI/CanvasCommandPrompt.swift` (chat turn format), `service/Providers/` (multi-turn messages for each adapter), `shared/Document/` (chat history file, draft flag on objects), `docs/api/canvas-commands-v1.md`, `docs/database/document-schema-v1.md`, `tests/PencilEchoTests/`, `tests/PencilEchoUITests/`.

## Acceptance

- [ ] With the incline diagram from the owner screenshot selected, typing "solve the time of descent on both paths" returns a worked answer in the chat and places the result beside the diagram as drafts. *(Real provider, A16.)*
- [ ] A follow-up message ("why is the curved path faster?") uses the previous turn. *(Real provider.)*
- [ ] Accept all keeps the drafts as normal objects; Discard all removes them; both can be undone.
- [ ] Closing and reopening the document keeps the chat history; New chat clears it.
- [ ] Cancel stops the request and places nothing.

## Automated checks

- Unit tests: context selection (selection vs visible page), history trimming to 10 turns, history persistence and migration, draft accept/discard and undo.
- Adapter tests: multi-turn request bodies for OpenAI-compatible, Anthropic and Gemini.
- Fixture test: a recorded chat reply with text plus canvas commands streams into the chat and places drafts.
- UI test: open the panel, send a message against a fixture provider, accept all.

## Device and provider gates

Owner A16 run with a real provider for the incline example and one follow-up.

## Stop conditions

Stop and ask the owner if storing chat history inside the document package conflicts with export or sharing plans, or if a provider can't take images and multi-turn text in the same request.

## Implementation record — 2026-11-04

Implemented in the shared checkout following the ticket sequence. Runtime source and meaningful regression checks are present; acceptance checkboxes above remain evidence gates, not claims from code inspection. See [verification report](../docs/testing/editor-shell-and-chat-020-021.md) for current commands, results, deviations and retained owner/device/provider checks. Existing concurrent work on 017–019 and 022 is preserved.

Verification: Debug/Release simulator builds and hosted/UI test-target builds passed; the combined native source check passed 80 assertions. Hosted runtime and UI execution were blocked by simulator boot stalls. Physical A16/Pencil/VoiceOver and real-provider acceptance are still pending; no full-suite or UI passing run is claimed.
