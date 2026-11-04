// Ported from PenEcho inspiration/src/server/api-stream.js @ 341e34d (AGPL-3.0-only).
import Foundation

struct AnthropicProvider: AIProvider {
    let preset: ProviderPreset
    var credentials: any ProviderCredentials = KeychainStore()
    var transport: any ProviderTransport = URLSessionProviderTransport()
    func capabilities(model: String) -> ModelCapabilities? { preset.defaultModels.first { $0.id == model }?.capabilities }
    func send(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        NativeProviderSupport.stream(request: request, transport: transport, accumulator: AnthropicStreamAccumulator()) { try makeRequest(request) }
    }
    func makeRequest(_ request: AIRequest) throws -> URLRequest {
        guard preset.authStyle == .anthropic else { throw AIError.invalidRequest }
        let (model, images, schema) = try NativeProviderSupport.validate(request, preset: preset)
        let identity = try ProviderIdentity(presetID: preset.id, baseURL: preset.baseURL)
        var content: [[String: Any]] = images.map { ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": $0]] }
        content.append(["type": "text", "text": request.instruction])
        var body: [String: Any] = ["model": request.model, "max_tokens": 4_096, "stream": true,
                                 "system": NativeProviderSupport.system(request), "messages": request.history.map { ["role": $0.role.rawValue, "content": $0.text] as [String: Any] } + [["role": "user", "content": content]]]
        if let effort = request.reasoning, ReasoningLevel.supports(preset: preset.id, model: request.model) {
            body["thinking"] = effort == .off ? ["type": "disabled"] : ["type": "enabled", "budget_tokens": effort.budget]
            body["max_tokens"] = 4096 + effort.budget
        }
        if let schema, model.structuredOutput == .jsonSchema {
            body["output_config"] = ["format": ["type": "json_schema", "schema": schema]]
        }
        return try NativeProviderSupport.authorized(body, url: identity.baseURL.appendingPathComponent("messages"), preset: preset, credentials: credentials)
    }
}

/// Text/usage extraction is ported; strict block ordering, terminal checks and
/// bounds are native hardening. Thinking/signature data never reaches AIEvent.
struct AnthropicStreamAccumulator: NativeStreamAccumulator {
    private(set) var text = ""
    private(set) var done = false
    private var started = false
    private var stopped = false
    private var nextIndex = 0
    private var block: String?
    private var inputTokens: Int?
    private var outputTokens: Int?

    mutating func accept(_ event: String) throws -> [AIEvent] {
        guard !done else { throw AIError.invalidOutput }
        let root = try NativeProviderSupport.object(event)
        guard let type = root["type"] as? String else { throw AIError.invalidOutput }
        if type == "error" { throw NativeProviderSupport.payloadError(root) }
        switch type {
        case "ping": return []
        case "message_start":
            guard !started, let message = root["message"] as? [String: Any],
                  (message["content"] as? [Any])?.isEmpty == true else { throw AIError.invalidOutput }
            started = true
            return try usage(message["usage"])
        case "content_block_start":
            guard started, !stopped, block == nil, root["index"] as? Int == nextIndex,
                  let value = root["content_block"] as? [String: Any], let kind = value["type"] as? String,
                  ["text", "thinking", "redacted_thinking"].contains(kind) else { throw AIError.invalidOutput }
            block = kind
            if kind == "text" {
                guard let initial = value["text"] as? String else { throw AIError.invalidOutput }
                return try NativeProviderSupport.append(initial, to: &text)
            }
        case "content_block_delta":
            guard started, !stopped, let block, root["index"] as? Int == nextIndex,
                  let delta = root["delta"] as? [String: Any] else { throw AIError.invalidOutput }
            if block == "text" {
                guard delta["type"] as? String == "text_delta", let value = delta["text"] as? String else { throw AIError.invalidOutput }
                return try NativeProviderSupport.append(value, to: &text)
            }
            guard ["thinking_delta", "signature_delta"].contains(delta["type"] as? String ?? "") else { throw AIError.invalidOutput }
        case "content_block_stop":
            guard started, block != nil, root["index"] as? Int == nextIndex else { throw AIError.invalidOutput }
            block = nil; nextIndex += 1
        case "message_delta":
            guard started, block == nil, let delta = root["delta"] as? [String: Any] else { throw AIError.invalidOutput }
            if (delta["stop_details"] as? [String: Any])?["type"] as? String == "refusal" { throw AIError.safetyBlocked }
            if let reason = delta["stop_reason"] as? String {
                if reason == "refusal" { throw AIError.safetyBlocked }
                guard reason == "end_turn", !stopped else { throw AIError.invalidOutput }
                stopped = true
            }
            return try usage(root["usage"])
        case "message_stop":
            guard started, stopped, block == nil else { throw AIError.invalidOutput }
            done = true
        default: break // Future event types may be added by the provider.
        }
        return []
    }
    private mutating func usage(_ value: Any?) throws -> [AIEvent] {
        guard let usage = value as? [String: Any] else { return [] }
        inputTokens = try NativeProviderSupport.count(usage["input_tokens"]) ?? inputTokens
        outputTokens = try NativeProviderSupport.count(usage["output_tokens"]) ?? outputTokens
        return [.usage(AIUsage(promptTokens: inputTokens, completionTokens: outputTokens,
                               totalTokens: inputTokens.flatMap { input in outputTokens.map { input + $0 } }))]
    }
    func finish() throws {
        guard done, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidOutput }
    }
}
