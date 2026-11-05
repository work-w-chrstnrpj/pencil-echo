# 027 — Claude Code share popover and banner: restyle

Milestone: UI/UX upgrade · Status: Open · Owner: **OpenCode (intern)** · Depends on: nothing (start from `main` at `a9c8a0c`) · Reviewer: Claude

Read [the UI style guide](../docs/design/ui-style-guide.md) first. This is a **small, look-only** task in **one file**. Don't change how sharing or pairing works.

## Problem (owner review, 2026-11-05)

The "Share with Claude Code" popover is a long scrolling page: toggle, a paragraph, two command boxes, a QR code and two buttons all at the same weight. It's hard to see at a glance whether sharing is on and whether the Mac is connected.

## Target design

```
┌ Claude Code ──────────────────────────────┐
│  ● Connected                               │  ← status row: symbol + text (+ last activity below, caption)
│  Share this document            [  ON  ]   │  ← toggle
│  Sharing stops when Pencil Echo closes     │  ← footer, caption, secondary
├────────────────────────────────────────────┤
│  ▸ Set up your Mac                         │  ← DisclosureGroup, collapsed when connected
│     1  Pair this iPad          [Copy]      │     each step: number badge, title, monospaced command, Copy
│        pencilecho-mcp pair pe1-…           │
│     2  Add to Claude Code      [Copy]      │
│        claude mcp add pencil-echo …        │
│     3  Ask Claude Code about your page     │
│     [QR code]                              │
├────────────────────────────────────────────┤
│  Reset pairing…                            │  ← destructive, plain, at the bottom
└────────────────────────────────────────────┘
```

- **Layout:** `Form` (`.formStyle(.grouped)`) inside the popover, width 360–420, height fits content (popover max ~560 pt, scrolls only if needed).
- **Status row:** `Label` with a symbol and text, both required:
  - not sharing: `laptopcomputer` + "Not shared" (`.secondary`)
  - starting/waiting: `antenna.radiowaves.left.and.right` + "Waiting for your Mac" (`.orange` symbol)
  - connected: `checkmark.circle.fill` + "Connected" (`.green` symbol)
  - paused: `pause.circle` + "Paused while Pencil Echo is in the background"
  - failed: `exclamationmark.triangle.fill` + the existing message (`.red` symbol)
  Use the existing `MCPShareCenter.shared.state` / `statusText` / `lastActivity`; under the status, `lastActivity` as `.caption` `.secondary` when present.
- **Toggle:** "Share this document" bound exactly like today (`center.share(target)` / `center.stopSharing(target)`), with the footer "Sharing stops when Pencil Echo goes to the background or the iPad locks."
- **Set up your Mac:** `DisclosureGroup`, **expanded** when not connected, **collapsed** when connected. Steps as rows: a numbered circle (`Text("1")` in a 24 pt `Circle` with `.tint` fill, white `.caption.bold()`), title (`.subheadline.weight(.semibold)`), the command in `.system(.caption, design: .monospaced)` with `.textSelection(.enabled)`, and a **Copy** button per command (`doc.on.doc`; after copying shows `checkmark` + "Copied" for 2 s, with `.symbolEffect(.bounce)`). The QR code (existing `MCPShareCenter.qrImage(for:)`) sits under the steps at 140 pt, with accessibility label "Pairing code as a QR code". Keep the warning sentence ("The code is a secret…") as the group's footer, not a paragraph at the top.
- **Reset pairing…:** last section, `role: .destructive`, keeps the existing confirmation dialog and its text.
- **Banner (`MCPShareBanner`, same file):** a glass capsule (`.glassEffect(.regular, in: .capsule)`), `Label` with `laptopcomputer` + `lastActivity ?? statusText`, `.caption.weight(.medium)`, 12/6 padding, status dot (8 pt `Circle`, green connected / orange waiting) before the text. Keep its type name and `init()`. (Ticket 024 decides whether and where it's placed. Don't place it anywhere.)

## Files you own (only this one)

- `application/App/MCP/MCPShareView.swift`

**Don't touch** any other file. In particular: not `MCPShareCenter.swift`, `MCPServer.swift`, `MCPCanvasTools.swift`, `MCPWire.swift` (sharing logic), not `AskAIEditorContainer.swift` (ticket 024 owns where the popover opens), not `project.pbxproj`. Keep `struct MCPShareView`, `init(target:)`, `struct MCPShareBanner` and `init()` exactly. Don't add new files; private helper views go in the same file.

## Acceptance criteria

- [ ] Status row shows the correct symbol **and** text for each of the five states.
- [ ] The share toggle turns sharing on and off exactly as before (try it with the steps below).
- [ ] "Set up your Mac" is expanded when not connected and collapsed when connected; it can always be opened.
- [ ] Each command has its own Copy button that copies the exact command text (pair command includes the current code) and confirms with "Copied".
- [ ] QR code still shows the current pairing code; "Reset pairing…" still asks for confirmation and makes a new code.
- [ ] `MCPShareBanner` is a glass capsule with a status dot and text.
- [ ] No text truncated at Dynamic Type AX3; everything readable in light and dark mode; VoiceOver reads status, toggle (with value), each step and each Copy button.
- [ ] Only `MCPShareView.swift` changed; the full unit suite passes (`MCPTests` must stay green).
- [ ] Screenshots: not shared, waiting, connected (collapsed setup), dark mode, AX3, in `tests/evidence/027/`.

## Handoff to OpenCode

- **Your task is only this ticket and only this file.** If you think something else needs changing, write it in your report; don't change it.
- **Work isolated:** `git worktree add ../penecho-027 -b ui/027-share-popover main`; work only in `../penecho-027`.
- **Simulator:** `xcrun simctl create "PE-027" com.apple.CoreSimulator.SimDeviceType.iPad-A16 com.apple.CoreSimulator.SimRuntime.iOS-27-0`; derived data `/tmp/PencilEcho-027`.
- **See the popover:** build and install the Debug app on `PE-027`, then launch it with a test pairing so you don't need a Mac:
  `xcrun simctl launch <PE-027 id> com.chrixcrusher.pencilecho -MCPPairingCode pe1-0a1b2c3d-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA -MCPAutoShare YES`
  then open a canvas and tap the laptop button in the AI toolbar. For "connected", run the Mac bridge from `tools/mcp-bridge` with `PENCILECHO_MCP_PAIRING` pointing at a file paired with that same code (see `docs/api/mcp.md`), then `pencilecho-mcp status`.
- **Verify:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination "platform=iOS Simulator,id=<PE-027 id>" -derivedDataPath /tmp/PencilEcho-027 -parallel-testing-enabled NO -only-testing:PencilEchoTests test`. Paste the "Test run with N tests … passed" line in your report.
- **Commit** on `ui/027-share-popover`; don't merge, push or touch `main`.
- **Report** in `docs/testing/share-popover-027.md`: what changed, screenshots, test output, questions.
- Claude reviews every acceptance criterion before merge.
