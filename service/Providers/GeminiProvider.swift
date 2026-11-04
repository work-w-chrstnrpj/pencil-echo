import Foundation

/// Original native REST adapter. Gemini has no matching implementation upstream.
struct GeminiProvider: AIProvider {
    let preset: ProviderPreset
    var credentials: any ProviderCredentials = KeychainStore()
    var transport: any ProviderTransport = URLSessionProviderTransport()
    func capabilities(model: String) -> ModelCapabilities? { preset.defaultModels.first { $0.id == model }?.capabilities }
    func send(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        NativeProviderSupport.stream(request: request, transport: transport, accumulator: GeminiStreamAccumulator()) { try makeRequest(request) }
    }
    func makeRequest(_ request: AIRequest) throws -> URLRequest {
        guard preset.authStyle == .gemini else { throw AIError.invalidRequest }
        let (model, images, schema) = try NativeProviderSupport.validate(request, preset: preset)
        let identity = try ProviderIdentity(presetID: preset.id, baseURL: preset.baseURL)
        let endpoint = identity.baseURL.appendingPathComponent("models").appendingPathComponent(request.model + ":streamGenerateContent")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw AIError.invalidRequest }
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        guard let url = components.url else { throw AIError.invalidRequest }
        var parts: [[String: Any]] = images.map { ["inlineData": ["mimeType": "image/png", "data": $0]] }
        parts.append(["text": request.instruction])
        var config: [String: Any] = ["maxOutputTokens": 4_096]
        if let effort = request.reasoning, ReasoningLevel.supports(preset: preset.id, model: request.model) {
            config["thinkingConfig"] = ["thinkingBudget": effort.budget]
            config["maxOutputTokens"] = 4096 + effort.budget
        }
        if let schema, model.structuredOutput == .jsonSchema {
            config["responseMimeType"] = "application/json"
            config["responseSchema"] = try Self.responseSchema(schema)
        }
        let body: [String: Any] = ["systemInstruction": ["parts": [["text": NativeProviderSupport.system(request)]]],
                                  "contents": request.history.map { ["role": $0.role == .assistant ? "model" : "user", "parts": [["text": $0.text]]] as [String: Any] } + [["role": "user", "parts": parts]], "generationConfig": config]
        return try NativeProviderSupport.authorized(body, url: url, preset: preset, credentials: credentials)
    }

    /// Gemini Schema is OpenAPI-shaped, not arbitrary JSON Schema. Keep local
    /// CommandValidator authoritative for integer enum and object-field constraints.
    static func responseSchema(_ schema: [String: Any], depth: Int = 0) throws -> [String: Any] {
        guard depth < 20 else { throw AIError.invalidRequest }
        var result: [String: Any] = [:]
        if let types = schema["type"] as? [String] {
            guard types.count == 2, types.contains("null"), let type = types.first(where: { $0 != "null" }) else { throw AIError.invalidRequest }
            result["type"] = type.uppercased(); result["nullable"] = true
        } else if let type = schema["type"] as? String { result["type"] = type.uppercased() }
        if let value = schema["description"] as? String { result["description"] = value }
        if let values = schema["enum"] as? [String] { result["enum"] = values; result["format"] = "enum" }
        if let required = schema["required"] as? [String] { result["required"] = required }
        if let properties = schema["properties"] as? [String: [String: Any]] {
            result["properties"] = try properties.mapValues { try responseSchema($0, depth: depth + 1) }
        }
        if let items = schema["items"] as? [String: Any] { result["items"] = try responseSchema(items, depth: depth + 1) }
        if let anyOf = schema["anyOf"] as? [[String: Any]] { result["anyOf"] = try anyOf.map { try responseSchema($0, depth: depth + 1) } }
        guard !result.isEmpty else { throw AIError.invalidRequest }
        return result
    }
}

struct GeminiStreamAccumulator: NativeStreamAccumulator {
    private(set) var text = ""
    var done: Bool { false } // Gemini's stream terminates at EOF, not at a DONE marker.
    private var stopped = false
    mutating func accept(_ event: String) throws -> [AIEvent] {
        let root = try NativeProviderSupport.object(event)
        if root["error"] != nil { throw NativeProviderSupport.payloadError(root) }
        if let feedback = root["promptFeedback"] as? [String: Any],
           let reason = feedback["blockReason"] as? String, reason != "BLOCK_REASON_UNSPECIFIED" { throw AIError.safetyBlocked }
        var events: [AIEvent] = []
        if let candidates = root["candidates"] as? [[String: Any]] {
            guard candidates.count <= 1 else { throw AIError.invalidOutput }
            if let candidate = candidates.first {
                guard (candidate["index"] as? Int ?? 0) == 0, !stopped else { throw AIError.invalidOutput }
                if let reason = candidate["finishReason"] as? String {
                    if ["SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "RECITATION", "IMAGE_SAFETY"].contains(reason) { throw AIError.safetyBlocked }
                    guard reason == "STOP" else { throw AIError.invalidOutput }
                    stopped = true
                }
                if let content = candidate["content"] as? [String: Any] {
                    guard let parts = content["parts"] as? [[String: Any]] else { throw AIError.invalidOutput }
                    for part in parts {
                        if part["thought"] as? Bool == true { continue }
                        guard let value = part["text"] as? String else { throw AIError.invalidOutput }
                        events += try NativeProviderSupport.append(value, to: &text)
                    }
                }
            }
        }
        if let usage = root["usageMetadata"] as? [String: Any] {
            events.append(.usage(try AIUsage(promptTokens: NativeProviderSupport.count(usage["promptTokenCount"]),
                                            completionTokens: NativeProviderSupport.count(usage["candidatesTokenCount"]),
                                            totalTokens: NativeProviderSupport.count(usage["totalTokenCount"]))))
        }
        return events
    }
    func finish() throws {
        guard stopped, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidOutput }
    }
}
