# Provider and MCP contracts

Status: OpenAI-compatible adapter and Qwen Debug spike implemented/fixture verified (007); real-provider acceptance pending. Other adapters and MCP remain planned.

## Provider adapters

`service/Providers/` now implements the generic streaming adapter, model capability gates, normalized errors and endpoint-bound Keychain storage. The Qwen contract, limits, synthetic tests and pending owner check are recorded in [providers.md](providers.md). The Debug screen uses only a bundled equation, not document captures.

Qwen first, then OpenAI, Anthropic, OpenRouter, Google Gemini, Cerebras, Groq, Hugging Face, Mistral and NVIDIA; selectable model and custom endpoint. Two adapter kinds: one OpenAI-compatible Chat Completions adapter with per-provider presets/quirks (Qwen, OpenAI, OpenRouter, Cerebras, Groq, Hugging Face, Mistral, NVIDIA), and native adapters for Anthropic Messages and Gemini. Vision capability is per model, not per provider. Keychain-backed credentials. Independent adapter capability records cover vision, streaming, structured output, token/size limits and cancellation. Verify current official contracts before coding. Never route credentials or user data to another endpoint/provider automatically.

Normalize request ID, instruction, explicitly scoped image/text context, referenced conversation and response expectations. Normalize errors for credentials, unsupported model/capability, rate limit, timeout/network, cancelled request and invalid output. Retry requires user action. No API keys in shared packages, widget content or diagnostics.

## Internal canvas command boundary

Versioned, bounded structured operations for add/edit/move/resize/delete/capture. Validate IDs, geometry, content sizes and allowed types before applying a transaction. Additions preserve original work; replace/delete requires explicit request authorization. Stale target revision yields review, never blind overwrite. Request identity prevents duplicate effects. AI answer contract v1: `docs/api/canvas-commands-v1.md` and `shared/schemas/canvas-commands-v1.json` (ticket 006). Move/resize/capture operations and MCP use are not in v1.

## MCP

Candidate clients: Codex, Claude Code, Cursor. Choose transport and secure authentication after capability verification; do not promise a tool name/protocol until specified. Conceptual operations: list authorized documents, open authorized document, capture scoped region, read objects, apply validated edits, retrieve annotation feedback, present permitted widget and manage sessions.

Paired same-network access, user-enabled documents, foreground availability only. Deny unpaired clients, revoked sessions, unapproved document IDs and host filesystem/command access. Define reconnect, revocation, duplicate requests, stale revisions and background transitions before implementation. Verify each client independently; successful connectivity is not proof of all tool behavior.
