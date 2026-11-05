# Settings and Chat panels — ticket 026

Date: 2026-11-05. Implemented by Claude (taking over from Cursor Grok, whose session ended after creating the worktree without changes). Branch `ui/026-panels`, worktree `penecho-026`.

## Scope

Only `application/App/Settings/AISettingsView.swift` and `application/App/AskAI/AgentChatView.swift` changed. `AISettingsModel`, `AgentChatController` and every binding and action are unchanged. Frozen interfaces kept: `AISettingsView(onDone:)`, `AgentChatView(controller:onClose:)`, navigation titles "AI Settings" and "Agent chat", buttons Done, Send, New chat, Close, Accept all, Discard all, and identifiers `chat-input` and `chat-error`.

## Settings

`Form` with `.formStyle(.grouped)`, sections in this order:

1. **AI provider:** provider picker, model ID, Suggested models menu, Fetch models (bearer providers), discovered models with a checkmark on the current one, Reads images toggle. The footer combines the "only this provider" rule with the vision guidance.
2. **API key:** key field, saved-key state, Save key / Remove key (destructive), Test connection with a progress spinner. The status shows as symbol + text: green check for "Connected…", info for key saved/removed and model counts, orange warning otherwise. The footer explains where keys are stored.
3. **Endpoint:** base URL field. An invalid URL shows an inline orange warning `Label` with the text in `.primary`; otherwise "Requests go to".
4. **Saved connections:** provider name with the model on a secondary line, and a checkmark on the active connection (accessibility value "Selected").
5. **Answers:** "Answer automatically when I pause" (same `autoAsk.enabled`), then "Pause before answering" (same stepper and range), disabled when off. The footer explains the delay.
6. **Appearance:** AI font, thinking indicator.
7. **Privacy:** a `lock` row "Only the part of the page you ask about is sent", with the existing "What is sent" text as the footer.
8. **About:** version, third-party notices.

**Deviation from the ticket, by the senior author:** the key and connection test are their own **API key** section, right after AI provider, instead of being inside it. Seven rows in one group was too long, and HIG groups favor short, related sets.

## Chat

- **Bubbles:** user messages trailing in the tint color with white text, assistant messages leading on `secondarySystemBackground`, corner radius 16 continuous, width capped by a 48 pt minimum spacer (about 85 % of a 360 pt panel). Text stays selectable. VoiceOver reads each bubble as one element: "You: …" / "Assistant: …".
- **Pending:** the instruction as a user bubble, then an assistant bubble with a spinner, "Working…", a small bordered Cancel, and the streaming text.
- **Empty state:** `ContentUnavailableView("Ask about your page", …)`.
- **Bottom bar** (`.safeAreaInset(.bottom)`, `.bar` background): inline error (orange symbol, `.primary` text, `chat-error`), drafts bar ("N drafts on the page", Discard all, Accept all), then the context chip (`Menu` + `Picker`: Selection / Visible page), the multi-line field in a 12 pt rounded container (`chat-input`), and **Send** (`arrow.up`, `.glassProminent`, circle, ⌘↩, disabled when empty or pending).

**Test impact (for ticket 024):** because bubbles are now one accessibility element, the old query `app.staticTexts["Solve the time of descent"]` no longer matches. Ticket 024's moved chat journey must find the message by label (`label CONTAINS …`). Ticket 024 is fixing that test.

## Verification

- Build: `generic/platform=iOS Simulator` Debug build passes, with no warnings in the changed file(s).
- Full unit suite on the iPad (A16) simulator: **✔ Test run with 256 tests in 26 suites passed** (2026-11-05). `MCPTests`, `AgentChatTests` and `ProviderSettingsTests` included.
- Screenshots aren't captured on this branch. The panels are captured by ticket 024's editor UI journeys (settings inspector, compact settings sheet, chat with drafts), in `tests/evidence/024/`.
