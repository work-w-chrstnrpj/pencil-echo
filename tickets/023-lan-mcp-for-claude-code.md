# 023 — LAN MCP: let Claude Code on the Mac work on the iPad canvas

Milestone: PE-005 (moved earlier by owner request, 2026-11-05) · Status: In Progress — implemented; simulator end-to-end verified with the Mac bridge (2026-11-05); owner A16 + Claude Code run pending · Owner: Claude · Depends on: 017, 018, 019, 021

## What

Let Claude Code on the owner's Mac look at the open Pencil Echo document on the iPad and place answers on it, over the home network. Claude Code runs on the owner's Claude subscription, so requests cost nothing extra and can use the strongest models at high effort.

## Why

Owner (2026-11-05): mazes and drawings come out poorly with the current API provider, and a Claude subscription can't be used as an API key. Anthropic's terms allow subscription sign-in only in Anthropic's own products, so Pencil Echo must not sign in with it. Claude Code *is* an Anthropic product. If Pencil Echo is an MCP tool that Claude Code calls, the model work runs in Claude Code under the subscription, and Pencil Echo only supplies images and applies validated answers.

Confirmed scope already includes this (`docs/decisions.md`: "opt-in, paired LAN MCP access while app is active; selected documents only"; `docs/tdd/tdd.md`, "Widgets and MCP": secure authenticated transport, local-network permission, opted-in documents only, same command boundary as internal AI).

Upstream reference (design only): `inspiration/docs/mcp-implementation.md` and `inspiration/docs/mcp-setup.md`. PenEcho runs an HTTPS server with its own certificate and gives the AI a small stdio bridge that handles discovery, trust and reconnection.

## Design

```
Claude Code (Mac, subscription)
   │  stdio (MCP JSON-RPC)
   ▼
pencilecho-mcp bridge (Mac, Swift command-line tool built from this repo)
   │  HTTPS on the LAN, certificate pinned, bearer token
   ▼
Pencil Echo on the iPad (foreground, "Share with Claude Code" on)
   │  same capture code and CommandValidator as Ask AI
   ▼
Answers placed as drafts (ticket 021) → the user taps Accept all
```

- **Why a bridge:** Claude Code starts it as a normal stdio MCP server. The bridge finds the iPad with Bonjour when its IP changes, pins the iPad's certificate (so no certificate has to be installed on the Mac), and reconnects after the iPad sleeps. The same bridge works for Codex and Cursor later.
- **iPad server:** `NWListener` (Network.framework) with TLS, advertised as Bonjour service `_pencilecho-mcp._tcp`. It runs only while the app is in the foreground and sharing is on. Backgrounding, locking or turning sharing off stops it.
- **Identity:** on first pairing the app creates a P-256 key in the Keychain and a self-signed certificate (minimal DER builder, no dependency), plus a random 256-bit bearer token.
- **Pairing:** Settings → Claude Code shows a pairing code containing the host ID, certificate SHA-256 fingerprint and token, as text and as a QR code. The owner runs `pencilecho-mcp pair <code>` once on the Mac; the bridge stores it in the Mac Keychain. "Reset pairing" makes a new key, certificate and token, and the old pairing stops working.
- **Sharing scope:** only the document open in the editor, and only while its "Share with Claude Code" switch is on. A banner on the iPad shows "Claude Code connected" and every request.

## MCP tools (v1)

| Tool | Input | Result |
|---|---|---|
| `pencil_echo_status` | `{}` | Shared document title, type, page count, revision; or "nothing shared". |
| `pencil_echo_capture` | `target`: `newest` (default), `visible`, `selection`, `page`; optional `page` index | PNG image (plus the magnified focus image when ticket 019 adds one) and JSON: `captureId`, `captureFrame`, `focusFrame`, `imageScale`, `pageBounds`, revision. Same capture code as Ask AI (017/019). |
| `pencil_echo_place` | `captureId`, `answer` (canvas commands v3 JSON) | Validated by `CommandValidator` against that capture's stored context, then placed as drafts. Returns what was placed, or the validator error so Claude can fix and retry. `edit_object`/`delete_object` stay refused. |
| `pencil_echo_instructions` (MCP prompt) | — | The canvas command rules from `CanvasCommandPrompt.system`, so Claude writes valid answers. |

Phase 2 (separate acceptance, same ticket only if v1 lands early): `pencil_echo_wait_for_request` long-polls until the owner taps **Send to Claude Code** on the iPad, then returns that capture. With Claude Code's `/loop`, this gives an Ask-AI-like flow without typing on the Mac.

## Scope

- iPad server, TLS identity, pairing UI, sharing switch, connected banner, foreground-only lifecycle, local-network usage text (`NSLocalNetworkUsageDescription`, `NSBonjourServices` in `Info.plist`). No new entitlement; works with the free Personal Team.
- Bridge in `tools/mcp-bridge/` (Swift package, macOS 15+, built with the installed Xcode): `pair`, `serve` (stdio MCP, launched by Claude Code), `status`.
- MCP protocol: JSON-RPC 2.0 over stdio, `initialize`, `tools/list`, `tools/call`, `prompts/list`, `prompts/get`. Image results use MCP `image` content.
- Limits: one client session at a time; 30 requests per minute; capture PNG at most 2048 px on the longest side and 3 MB; answers at most the existing validator limits; requests time out after 60 s.
- Docs: `docs/api/mcp.md` (tool contract and pairing), `docs/deployment/deployment.md` (Mac setup), `docs/decisions.md` (record that Claude Code is tested first; Codex and Cursor later, separately).

## Exclusions

- Using subscription credentials inside Pencil Echo, or any Anthropic sign-in in the app.
- Internet (non-LAN) access, cloud relay, or access while the app is in the background.
- Filesystem, command execution, other documents, or the library through MCP.
- Editing or deleting existing work through MCP.
- Codex and Cursor acceptance (separate evidence per `docs/decisions.md` gate 5).

## Affected areas

New: `application/App/MCP/` (server, TLS identity, pairing view, session), `tools/mcp-bridge/`, `docs/api/mcp.md`, `tests/PencilEchoTests/MCPTests.swift`. Changed: `application/App/Info.plist`, `application/App/AskAI/AskAIController.swift` (share capture/placement entry points), `application/App/AskAI/AgentChatController.swift` (draft placement reuse), settings and editor views, `docs/deployment/deployment.md`, `docs/decisions.md`.

## Acceptance

- [ ] Pairing on the A16 and the owner's Mac succeeds once and survives app relaunch and a new iPad IP address.
- [ ] In Claude Code, "solve the maze on my Pencil Echo page" captures the page, and the path appears on the iPad as drafts. *(Owner run; record model and success count out of 5.)*
- [ ] "Draw a dog" from Claude Code places a recognizable drawing. *(Owner run.)*
- [ ] With sharing off, the app in the background, or the iPad locked, every tool returns a clear "not shared / not reachable" error and nothing is captured.
- [ ] A wrong token, a different certificate, or a second client is refused.
- [ ] A malformed or over-limit answer is refused with the validator's error and nothing changes.

## Automated checks

- Unit: MCP JSON-RPC parsing and errors, tool argument validation, capture-to-place round trip with a fake transport, rate limit, single-session rule, sharing-off refusal, pairing code encode/decode, token comparison in constant time.
- Unit: self-signed certificate DER is valid (`SecCertificateCreateWithData` accepts it) and the fingerprint matches.
- Bridge: `swift test` for stdio framing, pairing storage and pinned TLS against a local test server.
- Simulator: the server starts and stops with foreground/background notifications.

## Device and provider gates

Owner A16 + Mac on the same Wi-Fi, Claude Code signed in with the owner's subscription. No API key is used.

## Stop conditions

Stop and ask the owner if: Claude Code drops or truncates image tool results above some size; the local-network permission or TLS listener doesn't work under free Personal Team signing; or a model routinely ignores the validator errors.

## Implementation notes (2026-11-05)

- **Transport change from the design above:** TLS 1.2 with a pre-shared key (`TLS_PSK_WITH_AES_128_GCM_SHA256`) instead of a self-signed certificate and bearer token. Both ends are Network.framework, so the 256-bit pairing key authenticates and encrypts directly, with no certificate code. The link carries the same newline-delimited JSON-RPC as stdio. `instructions` is a tool rather than an MCP prompt, because models call tools more reliably. Details: `docs/api/mcp.md`.
- **Draft ink bug fixed (affected 021 too):** PencilKit's canvas doesn't draw strokes dated before 1970. Draft markers were negative dates, so chat and MCP ink drafts were saved, outlined and exported but invisible on the canvas. Markers are now positive, from 60 s after the epoch. `DraftMarker.isSynthetic` (first day of 1970) keeps AI and draft ink out of Auto Ask's newest ink. Older negative markers still load. `docs/database/document-schema-v1.md` is updated.
- **Bridge connect race fixed:** concurrent connects (from `initialize` and the first tool call) now share one attempt. The iPad keeps only the newest connection, so two racing attempts could knock each other out.
- **Debug-only launch options** for end-to-end checks: `-MCPPairingCode pe1-…` sets a known pairing; `-MCPAutoShare YES` shares the first opened document. Neither exists in Release builds.
- **Verified (simulator + this Mac):**
  - 256 unit tests pass in 26 suites. 16 are new for 023: pairing code, line framing, JSON-RPC dispatch, rate limit, every tool path including validator errors, stale capture, read-only and ink drafts, plus a real TLS-PSK round trip and a wrong-key refusal on iOS.
  - `pencilecho-mcp selftest` passes on macOS.
  - Bridge → simulator app over Bonjour + TLS-PSK: `status`; a full stdio session (initialize, tools/list with the iPad's full answer schema, instructions, capture of a 91 KB PNG, a bad answer returning a fixable error, place, a second place refused); 3 sessions in a row.
  - Drafts (text plus a wave with an arrowhead) appear with dashed outlines, and **Drafts → Accept all** keeps them.
  - The server stops when the app goes to the background and resumes in the foreground.
- **Not yet verified:** the physical A16 and the owner's Mac on Wi-Fi, the local network permission prompts on both, Claude Code itself (tool-result image size limits), and the maze/dog quality runs.

