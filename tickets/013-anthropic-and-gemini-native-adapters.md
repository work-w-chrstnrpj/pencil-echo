# 013 — Anthropic and Google Gemini native adapters

Milestone: PE-002 · Status: In Progress — implemented and fixture-verified; owner live acceptance pending · Owner: Codex · Depends on: 007, 012

## What

Native `AIProvider` implementations for the **Anthropic Messages API** and the **Google Gemini API**, plugged into the 012 settings screen.

## Why

Both providers' native APIs differ from Chat Completions in auth, image blocks, streaming events and structured output. Both offer OpenAI-compatible endpoints, but those have documented gaps. Native adapters give reliable vision and JSON output.

## Scope

- **Anthropic:**
  - `POST https://api.anthropic.com/v1/messages`
  - `x-api-key` + `anthropic-version` headers
  - base64 `image` content blocks
  - SSE events (`message_start`, `content_block_delta`, `message_delta`, `message_stop`)
  - structured JSON via the documented mechanism (structured outputs or tool use)
  - error types mapped to `AIError`
- **Gemini:**
  - `generateContent` / `streamGenerateContent` with `alt=sse`
  - API key header
  - `inlineData` image parts
  - `responseMimeType: application/json` + `responseSchema`
  - safety-block responses mapped to a clear `AIError`
- Verify every field above against each provider's **current official docs** before coding, and record the results in `docs/api/providers.md`.
- Default model lists plus free-text model ID, and per-model vision flags as in 012.
- Port any matching logic from `inspiration/src/server/api-stream.js` with provenance per ticket 003.

## Exclusions

- Prompt caching, tool use beyond structured output, files APIs, Vertex AI auth.

## Acceptance

- [x] Fixture tests for each adapter: streamed success, auth failure, rate limit, overloaded/5xx, malformed output, cancel. Gemini also gets a safety block.
- [x] Same `AIEvent` / `AIError` behavior as the OpenAI-compatible adapter, so ticket 010 needs no provider-specific code.
- [ ] The owner runs a real Ask AI request for each provider they hold a key for. Record each as real-provider evidence or "not verified".

## Implementation and verification — 2026-11-04

Executed Mode A against this ticket and the existing 007/012 provider contracts. Native `AnthropicProvider` and `GeminiProvider` implement request/auth/image/structured-output construction and strict stream accumulation. `NativeProviderSupport` owns shared bounds, safe errors, cancellation and `ProviderFactory`; the factory is used by Ask AI and Test connection. Native entries are in the existing picker, with static model suggestions, free-text IDs, opt-in unknown-model vision, exact endpoint-scoped keys and native-aware model discovery. All official fields were checked before coding; [provider contracts and sources](../docs/api/providers.md#native-anthropic-and-gemini-adapters--ticket-013) record the current API/model facts and Gemini's supported-but-deprecated `responseSchema` surface.

Anthropic stream extraction derives from inventoried `inspiration/src/server/api-stream.js @ 341e34d` and carries provenance. Gemini and the native request/bounds logic are original Swift. No upstream edits, paid dependencies, migrations, signing changes or global Xcode-selection changes.

**Passed:** full hosted suite, **181 tests in 14 suites**, including 14 native-provider tests (parameterized for both providers and HTTP statuses). Coverage includes fragmented SSE success, native URLs/headers/images/schemas, completion/usage, auth/rate-limit/overload, malformed/truncated/non-JSON output, cancellation, Gemini safety/late safety, thinking omission, credential/vision gates, endpoint changes and unknown-model settings. Both native adapters apply synthetic answers through the existing Ask AI controller with one application transaction. Debug test build and Release simulator build (arm64/x86_64) passed.

The initial Release attempt collided with the unit build's Xcode database lock; its serialized rerun passed. Early test compilations and a cancellation test assumption were corrected before the passing run: cancelling an AsyncThrowingStream consumer may end iteration normally, so the contract asserts no completed answer and a closed connection, matching the existing adapter. Release retains the existing editor background-save `taskId` capture warning and the AppIntents metadata-skipped warning.

**Not verified:** real Anthropic request, real Gemini request, physical A16/Pencil and owner/VoiceOver acceptance. No live API key was accessed or provider request sent during fixture testing. The settings UI was compiled; no new native-settings UI journey or screenshot is claimed. The final acceptance checkbox remains open until the owner records live runs for the providers they hold keys for. Workspace root has no Git metadata, so no commit or PR was created.

Commands and local run logs are recorded in `docs/api/providers.md`.
