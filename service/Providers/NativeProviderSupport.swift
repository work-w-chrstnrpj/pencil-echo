import Foundation
import CoreFoundation

/// Protocol dispatch is shared by Ask AI and Test connection; neither knows wire formats.
enum ProviderFactory {
    static func make(_ preset: ProviderPreset, credentials: any ProviderCredentials = KeychainStore(),
                     transport: any ProviderTransport = URLSessionProviderTransport()) -> any AIProvider {
        switch preset.authStyle {
        case .bearer: OpenAICompatibleProvider(preset: preset, credentials: credentials, transport: transport)
        case .anthropic: AnthropicProvider(preset: preset, credentials: credentials, transport: transport)
        case .gemini: GeminiProvider(preset: preset, credentials: credentials, transport: transport)
        }
    }
}

protocol NativeStreamAccumulator: Sendable {
    var text: String { get }
    var done: Bool { get }
    mutating func accept(_ event: String) throws -> [AIEvent]
    func finish() throws
}

enum NativeProviderSupport {
    /// All untrusted request checks precede credentials and networking.
    static func validate(_ request: AIRequest, preset: ProviderPreset) throws -> (ModelCapabilities, [String], [String: Any]?) {
        try AIChatMessage.validate(request.history)
        guard let model = preset.defaultModels.first(where: { $0.id == request.model })?.capabilities,
              model.streaming else { throw AIError.unsupportedModel }
        guard request.model.utf8.count <= 256, !request.model.isEmpty,
              request.model.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-._".unicodeScalars.contains($0) }),
              request.model != ".", request.model != "..",
              request.pngImages.count <= 2, request.instruction.utf8.count <= 16 * 1_024,
              request.systemPrompt.utf8.count <= 64 * 1_024,
              !request.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidRequest }
        if !request.pngImages.isEmpty && !model.vision { throw AIError.modelLacksVision }
        let images = try request.pngImages.map { data -> String in
            _ = try ModelContent.pngDataURL(data, maxBytes: min(model.maxImageBytes, 5_000_000))
            return data.base64EncodedString()
        }
        var schema: [String: Any]?
        if let data = request.jsonSchema {
            guard data.count <= 64 * 1_024, let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.invalidRequest }
            schema = value
            schema?.removeValue(forKey: "$schema")
            schema?.removeValue(forKey: "$id")
        }
        return (model, images, schema)
    }

    static func authorized(_ body: [String: Any], url: URL, preset: ProviderPreset,
                           credentials: any ProviderCredentials) throws -> URLRequest {
        let identity = try ProviderIdentity(presetID: preset.id, baseURL: preset.baseURL)
        let data = try JSONSerialization.data(withJSONObject: body)
        guard data.count <= 14 * 1_024 * 1_024 else { throw AIError.invalidRequest }
        guard let key = try credentials.read(for: identity), !key.isEmpty, key.utf8.count <= 4_096,
              !key.contains("\r"), !key.contains("\n") else { throw AIError.invalidCredentials }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(key, forHTTPHeaderField: preset.authStyle == .anthropic ? "x-api-key" : "x-goog-api-key")
        if preset.authStyle == .anthropic { request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    static func system(_ request: AIRequest) -> String {
        guard let schema = request.jsonSchema, let text = String(data: schema, encoding: .utf8) else { return request.systemPrompt }
        return request.systemPrompt + "\nReturn exactly one JSON object matching this schema, without prose or fences.\n" + text
    }

    /// Reuses the bounded framing and the no-redirect ephemeral transport from 007.
    static func stream<A: NativeStreamAccumulator>(request: AIRequest, transport: any ProviderTransport,
                                                   accumulator: A, prepare: @escaping @Sendable () throws -> URLRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(128)) { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let prepared = try prepare()
                    let connection = transport.open(prepared)
                    defer { connection.cancel() }
                    var parser = ProviderSSEParser(), accumulator = accumulator
                    var status: Int?
                    var errorBody = Data()
                    func emit(_ event: AIEvent) throws {
                        try Task.checkCancellation()
                        switch continuation.yield(event) {
                        case .enqueued: break
                        case .dropped: throw AIError.invalidOutput
                        default: throw AIError.cancelled
                        }
                    }
                    for try await event in connection.events {
                        try Task.checkCancellation()
                        switch event {
                        case .response(let code, let type):
                            guard status == nil else { throw AIError.invalidOutput }
                            status = code
                            if code == 400 { continue }
                            guard code == 200 else { throw AIError.http(code) }
                            guard type.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "text/event-stream" else { throw AIError.invalidOutput }
                        case .data(let data):
                            guard status != nil else { throw AIError.invalidOutput }
                            if status == 400 {
                                guard errorBody.count + data.count <= 16 * 1_024 else { throw AIError.invalidRequest }
                                errorBody.append(data)
                                continue
                            }
                            for value in try parser.feed(data) {
                                for event in try accumulator.accept(value) { try emit(event) }
                            }
                        }
                        // Anthropic has a terminal message_stop. Gemini has no DONE;
                        // drain to EOF so late safety errors and usage cannot be lost.
                        if accumulator.done { break }
                    }
                    if status == 400 {
                        let root = (try? JSONSerialization.jsonObject(with: errorBody)) as? [String: Any] ?? [:]
                        throw payloadError(root, fallback: .invalidRequest)
                    }
                    guard status == 200 else { throw AIError.network }
                    for value in try parser.finish() {
                        for event in try accumulator.accept(value) { try emit(event) }
                    }
                    try accumulator.finish()
                    if request.jsonSchema != nil {
                        guard (try? JSONSerialization.jsonObject(with: Data(accumulator.text.utf8))) is [String: Any] else { throw AIError.invalidOutput }
                    }
                    try emit(.completed(accumulator.text))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? AIError.cancelled : AIError.normalized(error))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    static func object(_ text: String) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw AIError.invalidOutput }
        return root
    }
    static func count(_ value: Any?) throws -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue >= 0, n.doubleValue <= Double(Int32.max), n.doubleValue.rounded() == n.doubleValue else { throw AIError.invalidOutput }
        return n.intValue
    }
    static func append(_ part: String, to text: inout String) throws -> [AIEvent] {
        guard text.utf8.count + part.utf8.count <= 256 * 1_024 else { throw AIError.invalidOutput }
        text += part
        return part.isEmpty ? [] : [.textDelta(part)]
    }
    static func payloadError(_ root: [String: Any], fallback: AIError = .invalidOutput) -> AIError {
        let error = root["error"] as? [String: Any] ?? [:]
        if let details = error["details"] as? [[String: Any]], details.contains(where: {
            ["API_KEY_INVALID", "API_KEY_EXPIRED", "API_KEY_SERVICE_BLOCKED"].contains($0["reason"] as? String ?? "")
        }) { return .invalidCredentials }
        switch error["type"] as? String ?? error["status"] as? String ?? "" {
        case "authentication_error", "permission_error", "UNAUTHENTICATED", "PERMISSION_DENIED": return .invalidCredentials
        case "rate_limit_error", "RESOURCE_EXHAUSTED": return .rateLimited
        case "overloaded_error": return .server(529)
        case "api_error", "INTERNAL": return .server(500)
        case "UNAVAILABLE": return .server(503)
        case "NOT_FOUND", "not_found_error": return .unsupportedModel
        case "invalid_request_error", "INVALID_ARGUMENT": return .invalidRequest
        case "timeout_error", "DEADLINE_EXCEEDED": return .timeout
        case "request_too_large": return .imageTooLarge
        default: return fallback
        }
    }
}
