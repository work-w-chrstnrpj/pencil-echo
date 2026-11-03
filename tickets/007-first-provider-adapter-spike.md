# 007 — OpenAI-compatible adapter, first provider Qwen

Milestone: PE-000 · Status: In Progress — implemented/fixture verified; owner real-provider check pending · Owner: Codex · Depends on: 002, 006

## What

Build one generic **OpenAI-compatible Chat Completions** adapter and prove it end to end with **Qwen** (Alibaba Cloud Model Studio / DashScope). Scope: API key in Keychain, image + text request, streaming, cancellation and normalized errors.

## Why

Owner decision (2026-11-03): Qwen first. Nine of the eleven planned providers expose an OpenAI-compatible API. Getting this adapter right once covers most of ticket 012.

## Qwen specifics

- Region presets, from upstream `inspiration/src/providers/api-presets.js`:

| Preset | Base URL |
|---|---|
| `qwen-global` (Singapore) | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` |
| `qwen-us` (Virginia) | `https://dashscope-us.aliyuncs.com/compatible-mode/v1` |
| `qwen-china` (Beijing) | `https://dashscope.aliyuncs.com/compatible-mode/v1` |

- API keys are region-specific. The key is bound to the preset it was entered for.
- Handwriting needs a **vision model** (Qwen VL family). Verify current model IDs, image input format (`image_url` with base64 data URL), image size limits, streaming and `response_format` / JSON mode support against Alibaba Cloud's current official docs. Don't rely on upstream or memory alone.
- If the selected model has no structured-output support, request JSON in the prompt and rely on the 006 validator.

## Scope

- `AIProvider` protocol in `Services`:
  - `capabilities(model)`: vision, streaming, structured output, max image size. Capabilities are per model, not per provider.
  - `send(request) -> AsyncThrowingStream<AIEvent, Error>` with events `textDelta`, `completed(String)` and `usage`.
  - Cancellation via `Task` cancellation.
- `ProviderPreset`: `id`, display name, base URL, auth style (Bearer header by default), default models, and a quirks flag set (e.g. `noStreamUsage`, `jsonModeOnly`, `noSystemRole`).
- `OpenAICompatibleProvider`: `POST {baseURL}/chat/completions` with SSE parsing.
- `AIRequest`: `requestId`, model, system prompt, user instruction, PNG image(s), optional JSON schema (from 006).
- Normalized `AIError`: `invalidCredentials`, `unsupportedModel`, `modelLacksVision`, `rateLimited`, `timeout`, `network`, `cancelled`, `invalidOutput`, `server(status)`.
- An image request to a model without vision → `modelLacksVision` before any network call. Never strip the image silently.
- `KeychainStore` (`kSecClassGenericPassword`, this-device-only), keyed by preset ID + base URL. No key or response body is ever logged.
- Port request building and streaming from `inspiration/src/server/api-stream.js`, `src/server/model-content.js` and `src/providers/api-presets.js`, with the provenance header from ticket 003.
- Debug screen: choose a Qwen region, paste a key, pick a model, send the bundled test image of a handwritten equation, and see the streamed text.

## Exclusions

- Placing the answer on the canvas (010).
- Other providers and the settings UI (012, 013).
- Automatic retry or failover.

## Acceptance

- [x] Unit tests with checked-in synthetic protocol fixtures (not live recordings): streamed success, 401, 429, malformed JSON, mid-stream cancel, image sent to a text-only model.
- [x] The adapter is generic: no Qwen-specific code outside the preset and quirks.
- [ ] The owner runs one real Qwen vision request on the bundled image successfully. Record it as real-provider evidence.
- [x] New adapter/content/Debug sources contain no key or response-body logging; source scan found no logging calls. Live-provider log inspection remains part of owner acceptance.

## Implementation and verification — 2026-11-03 (Asia/Manila)

Plan-first execution of the ticket; dependency 006 now has Swift types/validator and is recorded resolved by its owner. Added the generic OpenAI-compatible provider, model capabilities and quirks, a bounded SSE parser/accumulator, cancellable ephemeral URLSession transport, endpoint-scoped this-device-only Keychain storage, and a Debug Qwen screen. No automatic retry/failover, canvas placement, provider settings expansion or paid dependency was added.

The Debug screen is **Debug → Qwen vision test (007)**. It selects one of the three ticket regions and a model, stores a masked key in Keychain, sends the bundled synthetic handwritten equation, shows incremental text and validates the completed answer with `CommandValidator`. qwen3-vl-plus is the default, with non-thinking mode; qwen-vl-plus/max and a text-only negative-control model are also listed. Model/region/account availability is not claimed from fixtures. Current official-contract evidence and owner steps are in [providers.md](../docs/api/providers.md).

Verification on Xcode 27.0 (27A266a), iPad (A16) / iOS 27.0 simulator:

- Canonical Debug build passed. Canonical full test command passed: **83 tests in 7 suites**, including 20 new provider test methods, with zero failures. Existing 005/006 and spike tests were preserved.
- Release simulator build (`-configuration Release`) passed; Debug UI is excluded from Release, while the provider service remains compiled.
- New tests include HTTP/auth/rate-limit and streaming failures, image/model gates, fragmented UTF-8/SSE, truncation/limits, schema fallback and model-specific quirks, Keychain round-trip/update/delete/accessibility and region/endpoint isolation. The Keychain test used a unique synthetic identity and removed it afterward.
- URLProtocol fixtures exercise the actual URLSession delegate path and prove DONE/cancellation closes an intentionally open response. No test contacts a provider; fixture.invalid requests are intercepted locally.
- Debug screen launched and was visually inspected in [the screenshot](../tests/evidence/007/qwen-debug.png). The equation PNG was inspected too. No key was entered or live request sent.
- New provider/Debug/content sources have no print/debugPrint/NSLog/Logger/os_log calls. Errors contain fixed diagnostics, not server messages.
- One earlier run failed test-host bootstrap; the subsequent complete run passed. A nested Swift Testing macro compilation issue in the new test file was corrected before the successful run. No signing or global Xcode-selection changes were needed.

Ported files carry the approved upstream-path/commit/license headers. The SSE framer is original Swift; eventsource-parser was not copied. The image and protocol fixtures are our own synthetic assets. The only evidence deviation is using synthetic fixtures instead of live recordings: no owner credential was supplied or discovered. Owner real Qwen vision/stream/cancellation/validator acceptance remains **NOT RUN**, so the ticket is not resolved. No root Git metadata exists; no commit or PR was created.
