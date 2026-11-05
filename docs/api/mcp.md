# LAN MCP for Claude Code (ticket 023)

Claude Code on the owner's Mac can look at the Pencil Echo document open on the iPad and add answers to it. Claude Code runs on the owner's Claude subscription. Pencil Echo never signs in to Anthropic, never holds a subscription credential and never calls a model for these requests. It supplies images and applies validated answers.

## Pieces

```
Claude Code (Mac) ──stdio JSON-RPC──▶ pencilecho-mcp serve (Mac)
                                        │ TLS 1.2 PSK, newline-delimited JSON-RPC
                                        ▼
                        Pencil Echo on the iPad (foreground, sharing on)
                                        │ AskAIController capture · CommandValidator
                                        ▼
                                  drafts on the page
```

| Piece | Source |
|---|---|
| Wire format, pairing code, tool catalog (shared) | `application/App/MCP/MCPWire.swift`, symlinked into the bridge |
| iPad listener | `application/App/MCP/MCPServer.swift` |
| JSON-RPC dispatch and tools | `application/App/MCP/MCPCanvasTools.swift` |
| Pairing, sharing lifecycle | `application/App/MCP/MCPShareCenter.swift` |
| Share popover and banner | `application/App/MCP/MCPShareView.swift` |
| Mac bridge | `tools/mcp-bridge/` (Swift package, macOS 15+) |

## Transport and security

- **Discovery:** the iPad advertises Bonjour service `_pencilecho-mcp._tcp` named `Pencil Echo <hostId>`. The bridge browses for its paired host ID each time it connects, so a new iPad IP address doesn't matter.
- **Encryption and authentication:** TLS 1.2 with a pre-shared key (`TLS_PSK_WITH_AES_128_GCM_SHA256`). The key is the 256-bit pairing secret, and the PSK identity is `pencilecho-<hostId>`. A client without the key fails the TLS handshake before any message is read. There are no certificates.
- **Pairing code:** `pe1-<8 hex host id>-<43-character key>`. The iPad keeps it in its Keychain (`WhenUnlockedThisDeviceOnly`). The Mac stores it in `~/Library/Application Support/PencilEchoMCP/pairing.json` with mode 0600. **Reset pairing** on the iPad makes a new key and the old one stops working.
- **When it runs:** only while a document's **Share with Claude Code** switch is on and the app is in the foreground. Backgrounding or locking stops the listener; it restarts when the app returns. Closing the document stops sharing. The screen doesn't auto-lock while sharing.
- **Scope:** only the shared document. No library, files, other documents, settings or commands.
- **One client:** a new connection from the paired bridge replaces the previous one.
- **Limits:** 30 tool calls per minute; one message line at most 8 MB; images at most 3 MB each; the last 8 captures are kept.

## Tools

The bridge answers `initialize`, `ping` and (when the iPad isn't reachable) `tools/list` itself, so Claude Code starts even if the iPad is asleep. Everything else is forwarded.

| Tool | Arguments | Result |
|---|---|---|
| `pencil_echo_status` | — | Title, type, pages, revision, read-only, whether there's new ink. |
| `pencil_echo_instructions` | — | The Ask AI answer rules (`CanvasCommandPrompt.system`), MCP notes and the answer JSON Schema. |
| `pencil_echo_capture` | `target`: `newest` (default), `visible`, `selection`, `page`; `page` index | PNG image, the magnified focus image when ticket 019 makes one, and JSON with `captureId`, `captureFrame`, `focusFrame`, `imageScale`, optional `focusImageScale`, `pageBounds`, `pageIndex`, `revision`. |
| `pencil_echo_place` | `captureId`, `answer` (object, version 1–3) | Validated against that capture by `CommandValidator`, placed by `AnswerApplier`, marked as drafts (ticket 021) in one undo step named "Claude Code drafts". |

- **newest** is ink written since sharing started or since the last `newest` capture, with the context region from ticket 017. With no new ink it falls back to `visible` and says so in `target`.
- **Errors are tool results** (`isError: true`) the model can act on: nothing shared, unknown capture, rejected answer (with the validator path), page changed since capture, already placed, read-only, no room.
- `edit_object` and `delete_object` stay refused: `allowReplace` is always false.

## Setup

See [deployment](../deployment/deployment.md#claude-code-on-the-mac-ticket-023).
