# Claude Code share popover and banner — ticket 027

Date: 2026-11-05. Implemented by OpenCode (intern), finished and reviewed by Claude (senior). OpenCode left the restyle uncommitted with no report; its test run hung on a wedged simulator, so Claude took the ticket over. Branch `ui/027-share-popover`, worktree `penecho-027`.

## Scope

Only `application/App/MCP/MCPShareView.swift` changed. `MCPShareView(target:)`, `MCPShareBanner()` and all sharing logic (`MCPShareCenter`, server, tools, wire) are unchanged.

## What changed

- **Layout:** `Form` with `.formStyle(.grouped)`, 360–420 pt wide, ideal height 520 pt (scrolls only beyond 560).
- **Status row:** symbol + text for every state, with `share-status`. Not shared (`laptopcomputer`, secondary), waiting (`antenna.radiowaves.left.and.right`, orange), connected (`checkmark.circle.fill`, green), paused (`pause.circle`), failed (`exclamationmark.triangle.fill`, red, with the center's message). The last activity is a caption under it while sharing.
- **Toggle:** "Share this document" (`share-toggle`), same `share` / `stopSharing` binding; footer about background and lock.
- **Set up your Mac:** `DisclosureGroup` (`share-setup`), open while not connected and collapsed once connected; the user can always open or close it. Three numbered steps in tinted circles, monospaced selectable commands in 8 pt rounded boxes, and a Copy button per command (`share-copy-pair`, `share-copy-add`) that shows `checkmark` + "Copied" for 2 s with `.symbolEffect(.bounce)`. QR code at 140 pt (`share-qr`), and the secret-code warning at the end of the group.
- **Reset pairing…:** its own last section, destructive, with the original confirmation dialog (`share-reset`).
- **Banner:** glass capsule (`.glassEffect(.regular, in: .capsule)`) with an 8 pt green/orange dot and `Label`, `share-banner`.

## Review notes (Claude)

- All acceptance items for layout, states, copy, QR, reset and banner are met in source.
- Fixed: the frame had only min/max heights, so the popover opened at 280 pt and scrolled; added `idealHeight: 520`.
- The banner isn't placed by the editor any more after ticket 024 (status moved to the Claude Code capsule in the navigation bar). The type stays available, as the ticket requires.

## Verification

- Build: `generic/platform=iOS Simulator` Debug build passes, with no warnings in the changed file(s).
- Full unit suite on the iPad (A16) simulator: **✔ Test run with 256 tests in 26 suites passed** (2026-11-05). `MCPTests`, `AgentChatTests` and `ProviderSettingsTests` included.
- Visual check of the five popover states (not shared, waiting, connected, dark, AX3) is still open: the editor journeys in ticket 024 open the popover, but connected needs a paired Mac.
