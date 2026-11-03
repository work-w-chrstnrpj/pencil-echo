# Provider implementation and verification

Status: Tickets 007/012/013 implemented and fixture-verified. Real-provider acceptance NOT RUN for any provider. Updated 2026-11-04 (Asia/Manila).

## Qwen contract checked against current documentation

Qwen uses an OpenAI-compatible Chat Completions POST, Bearer authentication, text/image_url message parts, incremental delta.content and a final usage chunk when requested. Alibaba now recommends workspace-specific domains, while documenting continued operation of existing domains. This spike retains the ticket's region presets; workspace/custom endpoints belong to 012. Keys remain region-specific. [Alibaba Chat API reference](https://www.alibabacloud.com/help/en/model-studio/qwen-api-via-openai-chat-completions).

| Preset | Base URL | Real-provider status |
|---|---|---|
| qwen-global | https://dashscope-intl.aliyuncs.com/compatible-mode/v1 | Not verified |
| qwen-us | https://dashscope-us.aliyuncs.com/compatible-mode/v1 | Not verified |
| qwen-china | https://dashscope.aliyuncs.com/compatible-mode/v1 | Not verified |

The US legacy base URL is also documented in [Alibaba's OCR API guidance](https://www.alibabacloud.com/help/fr/model-studio/qwen-vl-ocr-api-reference); using that host does not establish a model's regional/account availability. There is no automatic endpoint migration or failover.

| Model entry | Vision | Streaming | Output mode used | Extra request setting |
|---|---|---|---|---|
| qwen3-vl-plus (Debug default) | Yes | Yes | JSON object when a schema is supplied | enable_thinking: false |
| qwen-vl-plus | Yes | Yes | JSON object when a schema is supplied | None |
| qwen-vl-max | Yes | Yes | JSON object when a schema is supplied | None |
| qwen-turbo | No | Yes | JSON object when a schema is supplied | None |

The VL aliases above support JSON-object output in non-thinking mode. JSON-object mode requires a JSON instruction and does not enforce field names/types. The adapter includes the v1 schema in the prompt and the Debug screen validates the completed answer locally. It does not advertise strict JSON-schema support for these models. [Alibaba structured output](https://www.alibabacloud.com/help/en/model-studio/qwen-structured-output).

The vision examples cover qwen3-vl-plus, Base64 data URLs and streaming. The implementation accepts PNG only and uses a conservative **5,000,000-byte local per-image cap**, below the documented legacy Base64 guidance of less than 7 MB; this is an application limit, not the provider's maximum. It also caps image dimensions at 8,192 per side / 16,777,216 pixels, two images and a 14 MiB serialized request. These limits can be tightened or refined per model later. [Alibaba image/video understanding](https://www.alibabacloud.com/help/en/model-studio/vision).

These are explicit model entries, not family-name heuristics. Regional entitlements and alias availability must be proved with the owner's account. Unknown models fail closed until a verified capability entry exists; model discovery, free-text model entry, custom endpoints and other providers are ticket 012/013 work. Preset and per-model quirks remain data, with no Qwen branches in the adapter.

## Implemented service boundary

`AIProvider` exposes per-model capabilities and `send(AIRequest) -> AsyncThrowingStream<AIEvent, Error>`. Requests contain an app-generated UUID, model, system prompt, user instruction, PNG bytes and optional JSON schema; they contain no key. Events are textDelta, completed and usage. Partial deltas are preview only; completed is emitted once after successful stream termination. No document mutation occurs in this layer.

`OpenAICompatibleProvider` builds one request to the chosen base URL plus `/chat/completions`. Before reading a credential or opening transport, it rejects unknown/non-streaming models, images on non-vision models, invalid PNGs and oversized inputs. It supports strict json_schema, json_object, or prompt-only schema output according to the selected model and quirks. Strict support exists as generic request-building behavior, not a claim about the Qwen VL models above. v1 source/output limits are still enforced by `CommandValidator` at the command boundary.

The original SSE framer handles fragmented UTF-8, LF/CRLF/CR, comments, multiline data and EOF without a final separator. Limits are 64 KiB per line, 128 KiB per event, 2 MiB wire data and 256 KiB accumulated output. Session and consumer buffers fail on overflow rather than dropping deltas silently. Only successful `finish_reason: stop` completes; truncation, refusal, tools, malformed JSON, missing completion or unexpected content types fail closed. DONE closes transport immediately; EOF after a stop is accepted. Schema requests also require a syntactically valid final JSON object. The Debug screen then checks its full v1 semantics.

The URLSession transport uses ephemeral storage, no cookies/cache/credential storage, rejects **all HTTP redirects**, and has 60-second inactivity / 180-second resource timeouts. Task cancellation cancels its URLSession task. The Debug screen additionally invalidates its active request ID, so late events cannot replace the result of a cancelled or newer request. There is no app-level automatic retry, provider switch, authentication fallback or document apply.

## Credentials and diagnostics

`KeychainStore` uses `kSecClassGenericPassword`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, no synchronization, and an account derived from preset ID plus the exact normalized HTTPS base URL. User info, query and fragment components are rejected. Region/host/path/port changes do not reuse a credential. The Debug key field is masked, marked privacy-sensitive, cleared after save or region changes, and not populated from saved keys. Existing owner keys were not read or modified during verification; the Keychain test uses a unique synthetic identity and removes it afterward.

`AIError` exposes fixed messages for credentials, model/vision capability, rate limits, timeout, network, cancellation, invalid output and HTTP status. Local invalid-request, image-limit and Keychain failures have fixed diagnostics too. A small allowlist maps provider error codes; raw provider messages are never displayed as errors or logged. No logging calls exist in the new provider, image-content or Debug screen sources. Streamed answer text is deliberately displayed in the Debug result view only, with no persistence.

## Verification evidence

The checked-in fixtures in `tests/fixtures/providers/` are **hand-authored synthetic examples**, not captured responses from a real provider. They contain no live keys, private prompts or provider content. The PNG is our own synthetic handwritten-style equation `2x + 3 = 11`; its generator is checked in. The provider schema and PNG are bundled resources.

Provider tests cover success/usage, 401/403/404/408/429/500/504/302 mappings, safe 400 model errors, malformed events and final JSON, truncation/refusal, UTF-8/CRLF/multiline fragmentation, size limits, unknown/text-only models, credential region/endpoint isolation, Keychain read/update/delete/accessibility, data-driven quirks, prompt-only fallback and mid-stream cancellation. URLProtocol fixtures exercise the actual URLSession delegate path and confirm that DONE and consumer cancellation stop an intentionally open response; they intercept fixture.invalid and send no network packets. A 302 fixture verifies rejection of redirect statuses; redirects are denied by the transport delegate, without claiming a live redirect-server test.

Debug and Release build results, final full-suite counts and screenshot evidence are recorded in [ticket 007](../../tickets/007-first-provider-adapter-spike.md). No live provider request, paid service, global Xcode-selection change or physical installation was performed. Ticket 007 remains open until the owner's real Qwen vision request succeeds and is recorded separately.

## Owner real-provider check — pending

1. Build Debug and open **Debug → Qwen vision test (007)**. Choose the region matching your key, and a vision model available to your account. The endpoint is shown before sending.
2. Paste the key into the masked field and tap Save key on this device. It remains bound to that region/endpoint. Do not paste the key into chat, logs or ticket notes.
3. Confirm available quota in the provider account, then tap Send test image. Only the displayed bundled equation and prompt/schema are sent. No canvas content is captured.
4. Confirm incremental output, a completed v1-valid answer, and a correct solution/explanation for `x = 4`. Displayed output alone is not proof of mathematical correctness; inspect it. No document is modified.
5. Send again and cancel mid-stream; confirm late events do not change the cancellation status. A later retry must require another Send tap.
6. Record date, device/simulator, region, model, success/failure, streaming/cancellation and validator results. Do not record the key, raw response body or user content. Mark each untested region/model not verified. Preserve this gate if a real request is unavailable or rejected.

## OpenAI-compatible presets (ticket 012)

Checked against each provider's documentation on 2026-11-03. All presets use the 007 adapter: `POST <base>/chat/completions`, `Authorization: Bearer <key>`, streamed SSE, and images as `image_url` base64 PNG data URLs (local cap 5,000,000 bytes, as in 007). The catalog is `service/Providers/ProviderCatalog.swift`. A new provider is one entry there.

**Where models come from.** A provider's default models list only models whose vision support the provider documents. Any other model is either entered by ID or fetched from `GET <base>/models`, the standard OpenAI-compatible list that every preset below exposes. A model not in the defaults starts with vision **off**. Fetched metadata turns it on when it says so: `architecture.input_modalities` or `input_modalities` containing `image`, or `capabilities.vision`. Otherwise the user's toggle decides. Unknown models get no structured-output claim: the schema goes in the prompt, and `CommandValidator` enforces it.

**Usage reporting.** `stream_options.include_usage` is sent only where documented (Qwen, OpenAI, OpenRouter). Everywhere else the preset has `noStreamUsage`, so no extra parameter is sent that the provider might reject.

| Preset | Base URL | Key | Default models (vision) | JSON output used | Quirks | Notes and sources |
|---|---|---|---|---|---|---|
| Qwen ×3 | from 007 | Model Studio API key | from 007 | JSON object | `jsonModeOnly` | See above |
| OpenAI | `https://api.openai.com/v1` | API key | none; enter or fetch | prompt-only | `maxCompletionTokens` | `max_tokens` is deprecated and reasoning/GPT-5 models reject it ([OpenAI Ruby SDK reference](https://www.rubydoc.info/github/openai/openai-ruby/OpenAI/Models/Chat/CompletionCreateParams:max_tokens), [openai-agents issue](https://github.com/openai/openai-agents-python/issues/5455)). The model reference page could not be fetched (HTTP 403), so no vision IDs are claimed. |
| OpenRouter | `https://openrouter.ai/api/v1` | API key | none; fetch (public list) | prompt-only | — | `GET /api/v1/models` returns `architecture.input_modalities` and `supported_parameters` ([OpenRouter models docs](https://openrouter.ai/docs/overview/models)). Optional `HTTP-Referer` / `X-Title` headers are not sent. |
| Cerebras | `https://api.cerebras.ai/v1` | API key | `qwen-3.8-27b` | prompt-only | `noStreamUsage` | Image parts must be base64 PNG/JPEG data URIs. `json_object` mode can't be streamed, so it is not used ([chat completions reference](https://inference-docs.cerebras.ai/api-reference/chat-completions)). |
| Groq | `https://api.groq.com/openai/v1` | API key | `qwen/qwen3.8-27b` | prompt-only | `noStreamUsage` | 20 MB request limit with images ([Groq vision](https://console.groq.com/docs/vision)). JSON mode with images is documented without streaming, so it is not used. |
| Hugging Face | `https://router.huggingface.co/v1` | access token with "Make calls to Inference Providers" | none; enter or fetch | prompt-only | `noStreamUsage` | Model IDs may end in a `:provider`, `:fastest` or `:cheapest` suffix. `GET /v1/models` exists ([Inference Providers](https://huggingface.co/docs/inference-providers/index)). |
| Mistral | `https://api.mistral.ai/v1` | API key | `mistral-medium-2508`, `mistral-small-2506`, `mistral-large-2512`, `ministral-14b-2512`, `ministral-8b-2512` | prompt-only | `noStreamUsage` | Vision model list from [Mistral vision](https://docs.mistral.ai/capabilities/vision/). Image size limits are not stated there. |
| NVIDIA | `https://integrate.api.nvidia.com/v1` | API key | none; enter or fetch | prompt-only | `noStreamUsage` | Data-URI images are shown on some model pages (for example [MiniMax-M3](https://build.nvidia.com/minimaxai/minimax-m3)), but there is no official list of vision models or chat-completions image limit. |
| Custom | user-set HTTPS URL | API key | none | prompt-only | `noStreamUsage` | Required endpoint; HTTPS only, no credentials, query or fragment in the URL. |

**GitHub Models is not included.** GitHub's documentation says the service was retired, and its inference API and model catalog stopped working on July 30, 2026 ([GitHub Docs](https://docs.github.com/en/rest/models/inference)). The owner dropped it from the provider list on 2026-11-03 (`docs/decisions.md`).

**Errors.** These are the 007 mappings for every preset: 401/403 → missing or rejected key, 404 → unavailable model, 408/504 → timeout, 429 → rate limit, other statuses → HTTP status only. Provider error text is never shown or logged.

**Settings and keys.** `AISettings` (UserDefaults) holds the selected preset, an optional base-URL override, the model ID and per-model vision overrides. Keys live only in Keychain, bound to the preset ID plus the exact effective base URL. Switching provider or changing the endpoint never reuses a key, and a request never goes to a provider other than the selected one.

| Preset | Real-provider status |
|---|---|
| All presets above | Not verified (fixture tests only) |


## Native Anthropic and Gemini adapters — ticket 013

Updated 2026-11-04 (Asia/Manila). Native adapters and fixtures are implemented; real-provider requests remain **not verified**. The 012 OpenAI-compatible catalog is unchanged except for adding native entries. `ProviderFactory` selects the wire protocol for both Ask AI and Test connection; ticket 010's capture/validation/apply lifecycle contains no Anthropic/Gemini-specific branches.

### Official contract verification

These facts were checked before implementing the request builders. Documentation redirects from `ai.google.dev` to Google's `aistudio.google.com` are provider-owned; where a prose page could not be retrieved, Google's current REST discovery document was inspected directly.

| Contract | Native implementation | Official evidence |
|---|---|---|
| Anthropic endpoint/auth | `POST https://api.anthropic.com/v1/messages`; `x-api-key`, `anthropic-version: 2026-10-21`, JSON body and SSE Accept header. The current docs prefer Bearer but explicitly retain `x-api-key`, as required by this ticket. | [Authentication](https://platform.claude.com/docs/en/manage-claude/authentication), [API version migration](https://platform.claude.com/docs/en/api/migration-2026-10-21), [Messages](https://platform.claude.com/docs/en/api/messages/create) |
| Anthropic images/JSON | User content contains base64 `image` blocks with `source.type`, `media_type: image/png`, `data`; separate system prompt. Known models use `output_config.format` (`type: json_schema`, `schema`). No tool execution is required. | [Vision](https://platform.claude.com/docs/en/build-with-claude/vision), [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) |
| Anthropic stream | `message_start`, indexed block start/text delta/stop, cumulative `message_delta` usage, `message_stop`; ping/future event types tolerated. Thinking/signature blocks are ignored. Only a complete text answer with `end_turn` and terminal `message_stop` succeeds. Truncation, tools and refusal are rejected. | [Streaming Messages](https://platform.claude.com/docs/en/build-with-claude/streaming) |
| Gemini endpoint/auth | `POST https://generativelanguage.googleapis.com/v1beta/models/<bare-model-id>:streamGenerateContent?alt=sse`; key only in `x-goog-api-key`. This implements the streaming member of the generateContent API family, consistent with `AIProvider`; no non-streaming mode is exposed. | [Text generation](https://ai.google.dev/gemini-api/docs/text-generation), [GenerateContent reference](https://ai.google.dev/api/generate-content), [REST discovery document](https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta) |
| Gemini images/JSON | `contents[].parts[].inlineData` has `mimeType: image/png` and base64 data; `systemInstruction` holds text. Known models use `generationConfig.responseMimeType: application/json` and `responseSchema`. | [Image input](https://ai.google.dev/gemini-api/docs/image-understanding), [REST discovery document](https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta) |
| Gemini stream | Parse text from one candidate, ignoring thought parts; require `STOP`, then drain to EOF for final usage/errors. Usage reads `promptTokenCount`, `candidatesTokenCount`, `totalTokenCount`. Prompt blocks and safety/recitation/prohibited-content finish reasons become fixed `AIError.safetyBlocked` messages. | [GenerateContent responses](https://ai.google.dev/api/generate-content) |
| Gemini model parameters | No `candidateCount`, sampling controls or thinking override is sent. Current Gemini 3/4 docs say candidate count is unsupported; the adapter checks that at most one candidate is returned. | [Troubleshooting/model parameters](https://ai.google.dev/gemini-api/docs/troubleshooting) |

**Schema adaptation.** Google's discovery document marks `responseSchema` as deprecated but still supported; it remains the field requested by ticket 013. Its OpenAPI-shaped `Schema` needs uppercase types, `nullable` instead of JSON Schema null unions, string enums and recursive `properties`/`items`/`anyOf`. The adapter removes metadata and `additionalProperties`; integer enum constraints remain in the original schema embedded in the prompt and enforced by `CommandValidator`. Anthropic receives the original schema minus root `$schema`/`$id`. Neither adapter claims full arbitrary JSON Schema conversion. Revisit the Gemini wire field if Google removes the deprecated surface.

### Catalog and settings

| Preset | Static suggested models (documented vision + structured output) | Real-provider status |
|---|---|---|
| Anthropic (native) | `claude-sonnet-5-5`, `claude-haiku-5-5`, `claude-opus-5-5` | **Not verified** — no owner key/request used |
| Google Gemini (native) | `gemini-3.8-flash`, `gemini-4-argon` | **Not verified** — no owner key/request used |

Sources: [Claude model IDs/capabilities](https://platform.claude.com/docs/en/models/overview), [Gemini models](https://ai.google.dev/gemini-api/docs/models), [Gemini 3.8 Flash capabilities](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash). Catalog inclusion does not establish account access, free-tier availability or a successful live request.

Both presets support endpoint overrides and free-text bare model IDs. Vision defaults off for unknown IDs until the user enables it. Unknown IDs use prompt-only JSON rather than assuming provider structured-output support. Native model suggestions are static; the settings screen does not expose the OpenAI `/models` fetch action for them. `ModelDiscovery.fetch` returns local suggestions without credentials or networking when invoked for a native preset, and its OpenAI request builder refuses native presets. Keys remain scoped to preset ID plus exact normalized base URL, including override paths.

### Bounds, errors and cancellation

Native requests retain the existing local PNG validation, two-image cap, conservative 5,000,000 bytes per image, 16 KB instruction / 64 KB system prompt / 64 KB schema caps and 14 MiB encoded request cap. Native model IDs are limited to 256 UTF-8 bytes with no path delimiters. Output uses the existing SSE line/event/wire limits (64 KiB / 128 KiB / 2 MiB), a 256 KiB accumulated text cap and bounded AI-event buffering. Limits and vision checks precede credential reads. The shared transport remains ephemeral with no cookies, credential cache or redirects.

HTTP 401/403, 404, 429 and 5xx retain the common normalized errors. Midstream native error types map to credentials, rate limit, unsupported model, invalid request, timeout or server errors; overload is 529 for Anthropic and 503 for Gemini. HTTP 400 inspects only bounded JSON safe codes (16 KiB maximum); Gemini `API_KEY_INVALID`/`API_KEY_EXPIRED` reasons map to credentials. Raw provider diagnostic text is never surfaced or logged. See [Anthropic errors](https://platform.claude.com/docs/en/api/errors) and [Gemini troubleshooting](https://ai.google.dev/gemini-api/docs/troubleshooting).

One terminal `.completed` event is emitted only after successful protocol termination and JSON-object parsing for schema requests. `CommandValidator` remains the final command authorization boundary. Cancel closes the connection and produces no completed answer; as with the existing adapter, Swift's `AsyncThrowingStream` may end a cancelled consumer's iteration without throwing. Non-consumer transport failures normalize through `AIError`. No automatic retry, provider failover, prompt caching, Files API, tools or Vertex auth was added.

### Implementation, provenance and verification

- `service/Providers/AnthropicProvider.swift`: Messages builder and strict stream accumulator. Text/usage/event extraction derives from the inventoried `inspiration/src/server/api-stream.js @ 341e34d` and carries its AGPL-3.0-only provenance header.
- `GeminiProvider.swift`: original native Gemini builder, bounded schema projection, candidate/usage/safety handling; no matching Gemini code exists upstream.
- `NativeProviderSupport.swift`: shared native request validation, credential binding, factory and bounded runner; reuses the existing native SSE/URLSession transport.
- Catalog/settings, Ask AI factory call and Test connection route use the selected protocol. No document/schema migration or paid dependency.
- `tests/fixtures/providers/{anthropic,gemini}-*.sse`: original synthetic success, overload and safety fixtures. `NativeProviderTests` verifies native fields/auth/images/schema, fragmentation, completion/usage, HTTP and SSE errors, malformed/truncated/non-JSON output, cancellation, blocked/late-blocked output, thinking omission, credential/vision gates, endpoint changes, custom-model selection and generic Ask AI application.

Verification on 2026-11-04: **181 hosted tests in 14 suites passed**, including 14 native-provider test functions (with both-provider/HTTP-status parameter cases). The suite includes successful native adapter → generic Ask AI → one answer application for each provider. Debug test build and Release simulator build (arm64/x86_64) passed. The original OpenAI-compatible preset fixtures and no-logging source scan passed as part of the full suite.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -destination 'platform=iOS Simulator,name=iPad (A16)' -parallel-testing-enabled NO test
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project application/PencilEcho.xcodeproj -scheme PencilEcho -configuration Release -destination 'generic/platform=iOS Simulator' build
```

Logs: `/tmp/pencilecho-013-unit-final.log` and `/tmp/pencilecho-013-release-final.log`; result bundles remain in Xcode DerivedData. The first concurrent Release attempt hit the shared Xcode build database lock; its serialized rerun passed. Early test compilation/cancellation-assumption failures are not reported as green. Release retains the pre-existing editor `taskId` capture warning and AppIntents metadata-skipped warning. No owner documents, live keys, provider requests, physical installation or new UI screenshot/journey was used. Live-provider acceptance remains open independently.

### Owner live acceptance

For each provider the owner holds a key for: choose its native preset in AI Settings, save an endpoint-scoped key on the iPad, run Test connection, then write `2x + 3 = 11`, select it and tap Ask AI. Confirm an editable answer, one undo, successful reopen and manual cancellation/retry. Record provider/model, endpoint region, physical device and result here without keys, prompts, images or raw response bodies. Until separately recorded, both native providers remain **not verified**.
