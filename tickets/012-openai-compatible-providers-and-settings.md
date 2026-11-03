# 012 — OpenAI-compatible provider presets and AI settings screen

Milestone: PE-002 · Status: In Progress — implemented and fixture-verified; owner real-provider runs pending · Owner: Claude (taken over to parallelize) · Depends on: 007

## What

Add presets for every OpenAI-compatible provider on top of the 007 adapter, plus the settings screen for provider, model, endpoint and keys.

## Why

Owner decision (2026-11-03): support Qwen, OpenAI, Anthropic, OpenRouter, Google Gemini, Cerebras, Groq, Hugging Face, Mistral and NVIDIA. Anthropic and Gemini get native adapters in ticket 013. Everything else goes through the OpenAI-compatible adapter.

## Providers in this ticket

Base URLs are starting points. Verify each against the provider's current official docs. Upstream presets in `inspiration/src/providers/api-presets.js` cover some of them.

| Preset | Starting base URL | Notes to verify |
|---|---|---|
| Qwen (3 regions) | from 007 | Done in 007 |
| OpenAI | `https://api.openai.com/v1` | Chat Completions vs Responses API. Chat Completions is enough for v1 |
| OpenRouter | `https://openrouter.ai/api/v1` | Optional `HTTP-Referer` / `X-Title` headers. Per-model vision flag from its models API |
| Cerebras | `https://api.cerebras.ai/v1` | Vision availability may be limited; mark text-only models |
| Groq | `https://api.groq.com/openai/v1` | Only some models support vision |
| Hugging Face | `https://router.huggingface.co/v1` | HF token. Model IDs may carry a provider suffix |
| Mistral | `https://api.mistral.ai/v1` | Vision models (Pixtral / Mistral Medium-class). Check `response_format` support |
| NVIDIA | `https://integrate.api.nvidia.com/v1` | NVIDIA API key. Vision per model |

For each provider, record these in `docs/api/providers.md`:
- auth header
- model list source (static default list vs `/models` call)
- image input format and limits
- streaming format and usage reporting
- JSON / structured output support
- error codes
- quirks flags

## Scope

- Preset catalog in `Services` with the table above, extendable without code changes elsewhere.
- Model handling:
  - Model list: fetch `/models` where supported and fall back to the preset defaults. Free-text model ID is always allowed.
  - Vision flag per model: from the provider's metadata where available, otherwise a user-editable toggle defaulting to off for unknown models.
- **Custom endpoint:** a "Custom (OpenAI-compatible)" preset with base URL + key, plus a base URL override on any preset. Keys are bound to preset ID + base URL and are never sent anywhere else.
- **Settings screen (SwiftUI):**
  - provider picker
  - model picker with free text and a vision badge
  - endpoint field
  - key field (Keychain, masked)
  - "Test connection" (a tiny text request)
  - a remote-processing notice stating what is sent where
- Ask AI is disabled with an explanation when the selected model lacks vision and the request includes handwriting.
- Requests use only the selected provider. Errors never trigger another provider.

## Exclusions

- Anthropic and Gemini native adapters (013).
- Cost/usage dashboards.
- OAuth sign-in.
- Provider-specific features beyond chat completions (tools, files, batch).

## Acceptance

- [x] Fixture tests per preset: streamed success, auth failure, rate limit, malformed output, cancel.
- [x] A unit test proves switching provider never reuses another provider's key or base URL.
- [x] A unit test proves an image request to a non-vision model fails before the network call.
- [ ] The owner runs one real Ask AI request per provider they hold a key for. Record each separately as real-provider evidence; untested providers are marked "not verified".
- [x] No keys or response bodies in logs.

## Implementation evidence — 2026-11-03 (Claude)

**Provider facts**

These were checked against each provider's docs on 2026-11-03 and recorded per preset (auth, model list, images, streaming/usage, JSON output, quirks, sources) in `docs/api/providers.md`.
- **GitHub Models was retired** on 2026-07-30 (GitHub Docs). The owner dropped it from the provider list on 2026-11-03.
- **OpenAI** gets a new `maxCompletionTokens` quirk, because reasoning models reject `max_tokens`.
- **Cerebras** can't stream `json_object`. That provider, and every one without documented streaming JSON, uses prompt-only JSON, still enforced by `CommandValidator`.

**Files**
- `service/Providers/ProviderCatalog.swift`: 8 new presets plus Custom, on top of the 3 Qwen presets. Default models are only documented vision models.
- `service/Providers/AISettings.swift`:
  - `AISettings` (UserDefaults; no keys), with the effective base URL, model, capabilities and why Ask AI is blocked.
  - `ModelDiscovery` (`GET /models`, ephemeral session, no redirects, 4 MB / 2,000-model caps, vision metadata parsing).
  - `ConnectionTest` (one tiny text request).
- `OpenAICompatibleProvider`: `max_completion_tokens` when the quirk is set; no other changes.
- `application/App/Settings/AISettingsView.swift`, opened from the library's gear button:
  - provider picker
  - endpoint field, with the effective URL shown
  - model ID with a vision toggle, suggested models, and fetched models with vision badges
  - masked key field (Keychain only; never read back)
  - Test connection
  - "What is sent" notice
- Ask AI reads the selected provider and model from these settings. It is disabled, with the reason shown, when the endpoint is missing, no model is chosen, or the model lacks vision. If the settings are unusable it gets a provider that refuses every request, so it never falls back to another provider.

**Verification**
- `ProviderSettingsTests`:
  - streamed success, 401, 429, malformed output and cancel for **each** of the 12 presets, including URL, key, `max_tokens` vs `max_completion_tokens`, and `stream_options`
  - provider switching and endpoint changes never reuse a key, and no transport is opened
  - an image to a non-vision model fails before any credential read or transport
  - defaults, custom-endpoint validation, persistence, catalog coverage, `/models` parsing and key scoping, connection test
  - a source scan finding no logging calls in provider, AI, settings or Ask AI code
- Documented test command: **157 tests in 12 suites passed** (iPad (A16) / iOS 27.0).
- Simulator: the settings sheet opens from the library. Screenshot: `tests/evidence/012/ai-settings.png`.

**Not done or not verified**
- Real requests for any provider. The owner should run Test connection and one Ask AI per provider they have a key for, and record each separately; until then every preset is "not verified".
- Optional OpenRouter attribution headers are not sent.
- The model list shows at most the first 200 fetched models.

