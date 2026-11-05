# 026 — Settings and Chat panels: clear, HIG-style content

Milestone: UI/UX upgrade · Status: Open · Owner: **Cursor (Grok), junior** · Depends on: nothing (start from `main` at `a9c8a0c`) · Reviewer: Claude

Read [the UI style guide](../docs/design/ui-style-guide.md) first and follow it exactly. This ticket changes **how two panels look**, not what they do. Every setting, binding and action must keep working exactly as it does now.

## Problem (owner review, 2026-11-05)

The settings panel opened from the editor (and from the library) is hard to read: sections are in a confusing order, provider fields, connections and canvas preferences mix together, and labels such as "Ask when I pause writing" sit far from related controls. The Chat panel is plain text with "You" / "Assistant" labels and a bare text field.

## Part A — `AISettingsView` (settings)

Keep `struct AISettingsView`, its `init`, `onDone`, the `AISettingsModel` and every binding. Only reorganize and restyle the `Form`.

New section order (`Form` with `.formStyle(.grouped)`):

1. **AI provider** — Provider picker; model (text field + "Suggested models" menu + "Fetch models" button, as today); "Reads images" toggle; API key (`SecureField`, "Save key" / "Remove key"); **Test connection** button with its result shown inline as `Label` (✓ green "Connected" / ⚠ orange message). Footer: one sentence on where the key is stored ("Keys stay in this iPad's Keychain.").
2. **Endpoint** (only when the provider allows a custom URL) — base URL field with the existing validation message as an inline `Label` with `exclamationmark.triangle`.
3. **Saved connections** — the existing list; each row uses `LabeledContent` (provider name, model as secondary text) and a checkmark on the active one.
4. **Answers** — "Answer automatically when I pause" toggle (same `autoAsk.enabled` binding) and, right under it, "Pause before answering" stepper (same binding, shows "2 s"); disabled when the toggle is off. Footer: "Pencil Echo asks the AI after you stop writing for this long."
5. **Appearance** — AI font picker (Handwritten / Rounded / System), thinking indicator toggle.
6. **Privacy** — the existing "What is sent" text as the section footer, plus a short row `Label("Only the part of the page you ask about is sent", systemImage: "lock")`.
7. **About** — version (`LabeledContent`), Third-party notices (`NavigationLink`).

Rules: `LabeledContent` for read-only values; section headers in sentence case; footers for explanations (not extra rows); no fixed font sizes; destructive "Remove key" uses `role: .destructive`; `Done` stays the `.confirmationAction`. Must look right both in a sheet and in a narrow (320 pt) inspector.

## Part B — `AgentChatView` (chat)

Keep `struct AgentChatView`, `init(controller:onClose:)` and every controller call.

- **Messages:** bubbles. User messages trailing, `.tint` background with white text; assistant messages leading, `Color(.secondarySystemBackground)`; corner radius 16 continuous; max width ≈ 85 %; `textSelection(.enabled)` kept. Drop the "You"/"Assistant" captions (VoiceOver label per bubble: "You: …" / "Assistant: …").
- **Pending:** the pending instruction as a user bubble, then an assistant bubble with `ProgressView` + "Working…" and the streaming text when present; Cancel as a small bordered button in that bubble.
- **Empty state:** `ContentUnavailableView("Ask about your page", systemImage: "bubble.left.and.text.bubble.right", description: Text("Answers appear here and as editable drafts on the page."))`.
- **Input bar:** pinned with `.safeAreaInset(edge: .bottom)`: scope chip (`Menu` showing "Selection" or "Visible page" with lasso/viewfinder symbol; the same scope behavior as today), multi-line `TextField` (identifier `chat-input` kept) in a rounded 12 pt container, **Send** button (`arrow.up.circle.fill`, `.buttonStyle(.glassProminent)`, disabled when empty or pending, ⌘↩).
- **Drafts bar:** when drafts exist, a compact row above the input: "2 drafts on the page" + Accept all (`.borderedProminent`) + Discard all (`role: .destructive`, `.bordered`).
- **Errors:** inline `Label` with `exclamationmark.triangle`, `.orange`/`.red` symbol, text in `.primary` (identifier `chat-error` kept).
- Toolbar: "New chat" leading, "Close" trailing, as today.

## Files you own (only these)

- `application/App/Settings/AISettingsView.swift`
- `application/App/AskAI/AgentChatView.swift`

**Don't touch** any other file: not the models (`AISettingsModel` logic stays), not `AskAIEditorContainer.swift` (ticket 024 decides where these panels open), not the library, not `project.pbxproj`. **Don't add new files** (put helper views as `private struct`s in the same file). If a change seems to need another file, stop and write it in your report.

## Acceptance criteria

- [ ] Settings sections appear in the order above with the listed headers and footers; every control from before still exists and changes the same stored setting (provider, model, vision override, key save/remove, test connection, endpoint, saved connections, auto ask on/off and delay, AI font, thinking indicator, notices).
- [ ] The delay stepper is directly under the auto toggle and disabled when auto is off.
- [ ] Settings looks correct at 320 pt width (inspector) and as a full sheet; no truncated labels at Dynamic Type AX3 (text wraps).
- [ ] Chat shows bubbles as specified, an empty state, a pinned input bar with scope chip and a prominent Send button, a drafts bar when drafts exist, and inline errors.
- [ ] Send is disabled when the input is empty or a request is pending; ⌘↩ sends.
- [ ] Identifiers `chat-input` and `chat-error` still exist; existing unit tests (`AgentChatTests`, `ProviderSettingsTests`) pass unchanged.
- [ ] VoiceOver reads each bubble with "You:" / "Assistant:" and each settings control with its label and value.
- [ ] Styling matches the style guide (system text styles, semantic colors, radii 12/16, `Label` for every symbol, one prominent button per surface).
- [ ] Screenshots of Settings (light, dark, AX3) and Chat (empty, conversation, pending, drafts) in `tests/evidence/026/`.

## Handoff to Cursor (Grok)

- **Your task is only this ticket.** Two files, look and layout only. Don't change behavior, models or other files. Note anything else you see in your report.
- **Work isolated:** `git worktree add ../penecho-026 -b ui/026-panels main`; work only in `../penecho-026`.
- **Simulator:** `xcrun simctl create "PE-026" com.apple.CoreSimulator.SimDeviceType.iPad-A16 com.apple.CoreSimulator.SimRuntime.iOS-27-0`; derived data `/tmp/PencilEcho-026`.
- **Verify:** run the full unit suite on `PE-026`:
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination "platform=iOS Simulator,id=<PE-026 id>" -derivedDataPath /tmp/PencilEcho-026 -parallel-testing-enabled NO -only-testing:PencilEchoTests test`.
  For screenshots, open Settings from the library's Settings row; for Chat, launch Debug with `-chatFixture` per `docs/testing/editor-shell-and-chat-020-021.md`.
- **Commit** on `ui/026-panels`; don't merge, push or touch `main`.
- **Report** in `docs/testing/panels-026.md`: changes, screenshots, test output, open questions.
- Claude reviews every acceptance criterion before merge.
