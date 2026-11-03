// Ported from PenEcho inspiration/src/server/api-stream.js @ 341e34d (AGPL-3.0-only).
import Foundation

struct OpenAICompatibleProvider: AIProvider {
    let preset: ProviderPreset
    var credentials: any ProviderCredentials = KeychainStore()
    var transport: any ProviderTransport = URLSessionProviderTransport()

    func capabilities(model: String) -> ModelCapabilities? {
        preset.defaultModels.first { $0.id == model }?.capabilities
    }

    func send(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(128)) { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let prepared = try makeRequest(request)
                    var parser = ProviderSSEParser()
                    var accumulator = ChatStreamAccumulator()
                    var status: Int?
                    var errorBody = Data()
                    func emit(_ event: AIEvent) throws {
                        try Task.checkCancellation()
                        switch continuation.yield(event) {
                        case .enqueued: break
                        case .dropped: throw AIError.invalidOutput
                        case .terminated: throw AIError.cancelled
                        @unknown default: throw AIError.cancelled
                        }
                    }
                    let connection = transport.open(prepared)
                    defer { connection.cancel() }
                    for try await event in connection.events {
                        try Task.checkCancellation()
                        switch event {
                        case .response(let code, let contentType):
                            guard status == nil else { throw AIError.invalidOutput }
                            status = code
                            if code != 200 {
                                // Only 400 needs a bounded safe-code lookup for unsupported models.
                                if code != 400 { throw AIError.http(code) }
                            } else {
                                guard contentType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "text/event-stream" else { throw AIError.invalidOutput }
                            }
                        case .data(let data):
                            guard let status else { throw AIError.invalidOutput }
                            if status == 400 {
                                guard errorBody.count + data.count <= 16 * 1_024 else { throw AIError.server(400) }
                                errorBody.append(data)
                            } else {
                                for value in try parser.feed(data) {
                                    for event in try accumulator.accept(value) { try emit(event) }
                                }
                            }
                        }
                        if accumulator.done { break }
                    }
                    if status == 400 {
                        let root = (try? JSONSerialization.jsonObject(with: errorBody)) as? [String: Any] ?? [:]
                        throw ChatStreamAccumulator.payloadError(root, fallback: .server(400))
                    }
                    guard status == 200 else { throw AIError.network }
                    for value in try parser.finish() {
                        for event in try accumulator.accept(value) { try emit(event) }
                    }
                    if request.jsonSchema != nil {
                        guard (try? JSONSerialization.jsonObject(with: Data(accumulator.text.utf8))) is [String: Any] else { throw AIError.invalidOutput }
                    }
                    try emit(accumulator.finish())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Task.isCancelled ? AIError.cancelled : AIError.normalized(error))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    /// Capability and size gates precede credential access and transport creation.
    func makeRequest(_ request: AIRequest) throws -> URLRequest {
        guard preset.authStyle == .bearer else { throw AIError.invalidRequest }
        guard let model = capabilities(model: request.model), model.streaming else { throw AIError.unsupportedModel }
        if !request.pngImages.isEmpty && !model.vision { throw AIError.modelLacksVision }
        guard request.pngImages.count <= 2, request.instruction.utf8.count <= 16 * 1_024,
              request.systemPrompt.utf8.count <= 64 * 1_024,
              !request.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidRequest }
        let quirks = preset.quirks.union(preset.defaultModels.first { $0.id == request.model }?.quirks ?? [])
        let images = try request.pngImages.map { try ModelContent.pngDataURL($0, maxBytes: model.maxImageBytes) }
        let identity = try ProviderIdentity(presetID: preset.id, baseURL: preset.baseURL)
        var body: [String: Any] = ["model": request.model, "stream": true, "n": 1]
        body[quirks.contains(.maxCompletionTokens) ? "max_completion_tokens" : "max_tokens"] = 4_096
        if !quirks.contains(.noStreamUsage) { body["stream_options"] = ["include_usage": true] }
        if quirks.contains(.disableThinking) { body["enable_thinking"] = false }
        var system = request.systemPrompt
        if let schema = request.jsonSchema {
            guard schema.count <= 64 * 1_024, let json = try? JSONSerialization.jsonObject(with: schema),
                  json is [String: Any], let schemaText = String(data: schema, encoding: .utf8) else { throw AIError.invalidRequest }
            system += "\nReturn exactly one JSON object matching this schema. No prose or code fences.\n" + schemaText
            if model.structuredOutput == .jsonSchema && !quirks.contains(.jsonModeOnly) {
                body["response_format"] = ["type": "json_schema", "json_schema": ["name": "canvas_answer", "strict": true, "schema": json]]
            } else if model.structuredOutput != .none {
                body["response_format"] = ["type": "json_object"]
            }
        }
        var content: [[String: Any]] = [["type": "text", "text": request.instruction]]
        content += images.map { ["type": "image_url", "image_url": ["url": $0]] }
        var messages: [[String: Any]] = []
        if quirks.contains(.noSystemRole) {
            content.insert(["type": "text", "text": system], at: 0)
        } else { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": content])
        body["messages"] = messages
        let payload = try JSONSerialization.data(withJSONObject: body)
        guard payload.count <= 14 * 1_024 * 1_024 else { throw AIError.invalidRequest }
        guard let key = try credentials.read(for: identity), !key.isEmpty, key.utf8.count <= 4_096,
              !key.contains("\r"), !key.contains("\n") else { throw AIError.invalidCredentials }
        var result = URLRequest(url: identity.baseURL.appendingPathComponent("chat/completions"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        result.httpMethod = "POST"
        result.httpBody = payload
        result.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return result
    }
}
