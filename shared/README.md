# DocumentModel

The Xcode project's DocumentModel group points here. Future shared Swift types own document IDs, geometry and versioned schema contracts.

Ticket 002 adds the group; it is part of the single app module, not a separate Swift module. `Document/` holds the document package v1 types and migration hook (ticket 005). `CanvasCommands/` holds the canvas commands v1 types and `CommandValidator` (ticket 006). Ticket 005 defines the document package contract before persistence work.

`schemas/canvas-commands-v1.json` is the provider JSON Schema for AI answers; the contract is `docs/api/canvas-commands-v1.md` (ticket 006). It is now bundled by the app target for schema-bearing requests and the Qwen Debug screen (ticket 007).
