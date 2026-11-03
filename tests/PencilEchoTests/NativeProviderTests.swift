import Foundation
import Testing
@testable import PencilEcho

private final class NativeBundle: NSObject {}
private final class NativeKeys: ProviderCredentials, @unchecked Sendable {
    private let lock = NSLock()
    private var identities: [ProviderIdentity] = []
    let identity: ProviderIdentity
    init(_ preset: ProviderPreset) throws { identity = try ProviderIdentity(presetID: preset.id, baseURL: preset.baseURL) }
    var reads: Int { lock.withLock { identities.count } }
    func read(for identity: ProviderIdentity) throws -> String? {
        lock.withLock { identities.append(identity) }
        return identity == self.identity ? "synthetic-native-key" : nil
    }
}
private final class NativeTransport: ProviderTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var cancels = 0
    let body: Data
    let status: Int
    let pause: Bool
    var recorded: [URLRequest] { lock.withLock { requests } }
    var cancelled: Bool { lock.withLock { cancels > 0 } }
    init(_ body: Data, status: Int = 200, pause: Bool = false) { self.body = body; self.status = status; self.pause = pause }
    func open(_ request: URLRequest) -> ProviderHTTPStream {
        lock.withLock { requests.append(request) }
        let pair = AsyncThrowingStream<ProviderHTTPEvent, Error>.makeStream()
        let producer = Task {
            pair.continuation.yield(.response(status: status, contentType: status == 200 ? "text/event-stream; charset=utf-8" : "application/json"))
            // Split every UTF-8/JSON/SSE boundary; no socket or real credential is used.
            for index in stride(from: 0, to: body.count, by: 5) {
                pair.continuation.yield(.data(body.subdata(in: index..<min(index + 5, body.count))))
            }
            if pause {
                do { try await Task.sleep(for: .seconds(120)) }
                catch { pair.continuation.finish(throwing: AIError.cancelled); return }
            }
            pair.continuation.finish()
        }
        return ProviderHTTPStream(events: pair.stream, cancel: { [self] in
            lock.withLock { cancels += 1 }; producer.cancel(); pair.continuation.finish(throwing: AIError.cancelled)
        })
    }
}

struct NativeProviderTests {
    static let ids = ["anthropic", "gemini"]
    func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: NativeBundle.self).url(forResource: name, withExtension: "sse", subdirectory: "providers"))
        return try Data(contentsOf: url)
    }
    private func setup(_ id: String, body: Data? = nil, status: Int = 200, pause: Bool = false) throws -> (any AIProvider, NativeTransport, NativeKeys, AIRequest) {
        let preset = try #require(ProviderCatalog.preset(id))
        let transport = NativeTransport(try body ?? fixture(id + "-success"), status: status, pause: pause)
        let keys = try NativeKeys(preset)
        let request = AIRequest(model: preset.defaultModels[0].id, systemPrompt: "Return a canvas answer.", instruction: "Solve this.", jsonSchema: AskAIController.bundledSchema)
        return (ProviderFactory.make(preset, credentials: keys, transport: transport), transport, keys, request)
    }
    func collect(_ provider: any AIProvider, _ request: AIRequest) async throws -> [AIEvent] {
        var events: [AIEvent] = []
        for try await event in provider.send(request) { events.append(event) }
        return events
    }

    @Test(arguments: ids) func streamedSuccessAndNativeWireRequest(_ id: String) async throws {
        let (provider, transport, keys, original) = try setup(id)
        var request = original
        request.pngImages = [try Data(contentsOf: #require(Bundle.main.url(forResource: "handwritten-equation", withExtension: "png")))]
        let events = try await collect(provider, request)
        let deltas = events.compactMap { if case .textDelta(let text) = $0 { return text }; return nil }
        let completions = events.compactMap { if case .completed(let text) = $0 { return text }; return nil }
        #expect(completions == [deltas.joined()])
        #expect(!deltas.joined().contains("reasoning"))
        #expect(events.contains(.usage(AIUsage(promptTokens: 12, completionTokens: 30, totalTokens: 42))))
        #expect(keys.reads == 1 && transport.recorded.count == 1 && transport.cancelled)
        let sent = try #require(transport.recorded.first)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent.url?.query?.contains("key") != true)
        let payload = try #require(sent.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        if id == "anthropic" {
            #expect(sent.url?.absoluteString == "https://api.anthropic.com/v1/messages")
            #expect(sent.value(forHTTPHeaderField: "x-api-key") == "synthetic-native-key")
            #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
            let messages = try #require(body["messages"] as? [[String: Any]])
            let content = try #require(messages[0]["content"] as? [[String: Any]])
            let image = try #require(content[0]["source"] as? [String: String])
            #expect(image["type"] == "base64" && image["media_type"] == "image/png")
            #expect(Data(base64Encoded: image["data"] ?? "") == request.pngImages[0])
            let format = (body["output_config"] as? [String: Any])?["format"] as? [String: Any]
            #expect(format?["type"] as? String == "json_schema")
            #expect(format?["schema"] is [String: Any])
        } else {
            #expect(sent.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/\(request.model):streamGenerateContent?alt=sse")
            #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == "synthetic-native-key")
            let contents = try #require(body["contents"] as? [[String: Any]])
            let parts = try #require(contents[0]["parts"] as? [[String: Any]])
            let image = try #require(parts[0]["inlineData"] as? [String: String])
            #expect(image["mimeType"] == "image/png")
            #expect(Data(base64Encoded: image["data"] ?? "") == request.pngImages[0])
            let config = try #require(body["generationConfig"] as? [String: Any])
            #expect(config["responseMimeType"] as? String == "application/json")
            #expect(config["candidateCount"] == nil) // Unsupported on current Gemini 3/4.
            let schema = try #require(config["responseSchema"] as? [String: Any])
            #expect(schema["type"] as? String == "OBJECT")
            let properties = try #require(schema["properties"] as? [String: [String: Any]])
            #expect(properties["message"]?["nullable"] as? Bool == true)
            #expect(properties["version"]?["enum"] == nil)
            #expect(schema["additionalProperties"] == nil)
        }
    }
    @Test(arguments: ids, [401, 403, 404, 429, 500, 503, 529, 504])
    func httpErrorsAreFixedAndNeverRetry(_ id: String, _ status: Int) async throws {
        let (provider, transport, _, request) = try setup(id, status: status)
        do { _ = try await collect(provider, request); Issue.record("Expected HTTP error") }
        catch { #expect(error as? AIError == AIError.http(status)) }
        #expect(transport.recorded.count == 1 && transport.cancelled)
    }
    @Test func geminiBadKeyHTTP400UsesOnlySafeReasonCode() async throws {
        for reason in ["API_KEY_INVALID", "API_KEY_EXPIRED", "OTHER"] {
            let body = try JSONSerialization.data(withJSONObject: ["error": ["status": "INVALID_ARGUMENT", "details": [["reason": reason]], "message": "private synthetic diagnostic"]])
            let (provider, _, _, request) = try setup("gemini", body: body, status: 400)
            do { _ = try await collect(provider, request); Issue.record("Expected safe 400 error") }
            catch { #expect(error as? AIError == (reason == "OTHER" ? .invalidRequest : .invalidCredentials)) }
        }
    }
    @Test(arguments: ids) func inStreamOverload(_ id: String) async throws {
        let (provider, transport, _, request) = try setup(id, body: fixture(id + "-overloaded"))
        do { _ = try await collect(provider, request); Issue.record("Expected overload error") }
        catch { #expect(error as? AIError == .server(id == "anthropic" ? 529 : 503)) }
        #expect(transport.cancelled)
    }
    @Test(arguments: ids) func malformedAndMissingTerminalFail(_ id: String) async throws {
        for data in [Data("data: not-json\n\n".utf8), Data("data: {}\n\n".utf8), Data()] {
            let (provider, transport, _, request) = try setup(id, body: data)
            do { _ = try await collect(provider, request); Issue.record("Expected invalid output") }
            catch { #expect(error as? AIError == .invalidOutput) }
            #expect(transport.cancelled)
        }
        var source = String(decoding: try fixture(id + "-success"), as: UTF8.self)
        source = source.replacingOccurrences(of: id == "anthropic" ? "end_turn" : "STOP", with: "MAX_TOKENS")
        let (provider, _, _, request) = try setup(id, body: Data(source.utf8))
        do { _ = try await collect(provider, request); Issue.record("Expected truncation error") }
        catch { #expect(error as? AIError == .invalidOutput) }
    }
    private func reply(_ id: String, text: String) throws -> Data {
        let values: [[String: Any]] = id == "anthropic" ? [
            ["type": "message_start", "message": ["content": []]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": text]],
            ["type": "content_block_stop", "index": 0],
            ["type": "message_delta", "delta": ["stop_reason": "end_turn"]], ["type": "message_stop"]
        ] : [["candidates": [["index": 0, "content": ["parts": [["text": text]]], "finishReason": "STOP"]]]]
        return try values.reduce(into: Data()) { result, value in
            result.append(Data("data: ".utf8)); result.append(try JSONSerialization.data(withJSONObject: value)); result.append(Data("\n\n".utf8))
        }
    }
    @Test(arguments: ids) func schemaRequestsRejectCompleteNonJSON(_ id: String) async throws {
        let (provider, _, _, request) = try setup(id, body: reply(id, text: "Not JSON"))
        var events: [AIEvent] = []
        do { for try await event in provider.send(request) { events.append(event) }; Issue.record("Expected invalid JSON") }
        catch { #expect(error as? AIError == .invalidOutput) }
        #expect(!events.contains { if case .completed = $0 { true } else { false } })
    }
    @Test(arguments: ids) func streamErrorTypesAndRequestBounds(_ id: String) async throws {
        let codes = id == "anthropic" ? ["authentication_error", "rate_limit_error", "api_error"] : ["UNAUTHENTICATED", "RESOURCE_EXHAUSTED", "INTERNAL"]
        for (index, code) in codes.enumerated() {
            let payload: [String: Any] = id == "anthropic" ? ["type": "error", "error": ["type": code, "message": "private synthetic detail"]] : ["error": ["status": code, "message": "private synthetic detail"]]
            let body = Data("data: ".utf8) + (try JSONSerialization.data(withJSONObject: payload)) + Data("\n\n".utf8)
            let (provider, _, _, request) = try setup(id, body: body)
            do { _ = try await collect(provider, request); Issue.record("Expected stream error") }
            catch { #expect(error as? AIError == [AIError.invalidCredentials, .rateLimited, .server(500)][index]) }
        }
        let (provider, transport, keys, original) = try setup(id)
        var request = original; request.instruction = String(repeating: "x", count: 16 * 1_024 + 1)
        do { _ = try await collect(provider, request); Issue.record("Expected request bound") }
        catch { #expect(error as? AIError == .invalidRequest) }
        #expect(keys.reads == 0 && transport.recorded.isEmpty)
    }
    @Test func anthropicThinkingUsageRefusalAndBlockOrdering() throws {
        var stream = AnthropicStreamAccumulator()
        _ = try stream.accept(#"{"type":"message_start","message":{"content":[]}}"#)
        _ = try stream.accept(#"{"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}"#)
        #expect(try stream.accept(#"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"private synthetic text"}}"#).isEmpty)
        _ = try stream.accept(#"{"type":"content_block_stop","index":0}"#)
        #expect(throws: AIError.safetyBlocked) { try stream.accept(#"{"type":"message_delta","delta":{"stop_reason":"end_turn","stop_details":{"type":"refusal"}}}"#) }
        var badIndex = AnthropicStreamAccumulator()
        _ = try badIndex.accept(#"{"type":"message_start","message":{"content":[]}}"#)
        #expect(throws: AIError.invalidOutput) { try badIndex.accept(#"{"type":"content_block_start","index":3,"content_block":{"type":"text","text":"bad order"}}"#) }
        var invalidUsage = GeminiStreamAccumulator()
        #expect(throws: AIError.invalidOutput) { try invalidUsage.accept(#"{"usageMetadata":{"promptTokenCount":true}}"#) }
    }

    @Test(arguments: ids) func cancellationClosesConnectionWithoutCompletion(_ id: String) async throws {
        let (provider, transport, _, request) = try setup(id, body: Data(), pause: true)
        let task = Task { try await collect(provider, request) }
        for _ in 0..<100 where transport.recorded.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(transport.recorded.count == 1)
        task.cancel()
        // AsyncThrowingStream may end iteration normally when its consumer is
        // cancelled; neither that path nor the throwing path may complete an answer.
        do {
            let events = try await task.value
            #expect(!events.contains { if case .completed = $0 { true } else { false } })
        } catch { #expect(error as? AIError == .cancelled) }
        for _ in 0..<100 where !transport.cancelled { try await Task.sleep(for: .milliseconds(5)) }
        #expect(transport.cancelled)
    }
    @Test func geminiSafetyAndLateSafetyAreErrors() async throws {
        for data in [try fixture("gemini-safety"), try fixture("gemini-success") + fixture("gemini-safety")] {
            let (provider, _, _, request) = try setup("gemini", body: data)
            do { _ = try await collect(provider, request); Issue.record("Expected safety error") }
            catch { #expect(error as? AIError == .safetyBlocked) }
        }
    }
    @Test(arguments: ids) func invalidImagesAndUnknownModelsFailBeforeKeyRead(_ id: String) async throws {
        let (provider, transport, keys, original) = try setup(id)
        var request = original
        request.pngImages = [Data("not PNG".utf8)]
        do { _ = try await collect(provider, request); Issue.record("Expected invalid image") }
        catch { #expect(error as? AIError == .invalidRequest) }
        request = original; request.model = "not-a-listed-model"
        do { _ = try await collect(provider, request); Issue.record("Expected unsupported model") }
        catch { #expect(error as? AIError == .unsupportedModel) }
        #expect(keys.reads == 0 && transport.recorded.isEmpty)
    }
    @Test(arguments: ids) func switchingEndpointNeverReusesKey(_ id: String) async throws {
        let preset = try #require(ProviderCatalog.preset(id))
        let keys = try NativeKeys(preset)
        var settings = AISettings()
        settings.providers[id] = ProviderSettings(baseURLOverride: "https://native-fixture.invalid/v1", model: preset.defaultModels[0].id)
        let moved = try settings.resolvedPreset(for: id)
        let transport = NativeTransport(Data())
        let provider = ProviderFactory.make(moved, credentials: keys, transport: transport)
        do { _ = try await collect(provider, AIRequest(model: moved.defaultModels[0].id, systemPrompt: "", instruction: "Hi")); Issue.record("Expected missing scoped key") }
        catch { #expect(error as? AIError == .invalidCredentials) }
        #expect(transport.recorded.isEmpty)
    }
    @Test(arguments: ids) func customModelVisionIsOptInAndNativeDiscoveryIsLocal(_ id: String) async throws {
        var settings = AISettings()
        settings.selectedPresetID = id
        settings.providers[id] = ProviderSettings(model: "custom-vision-model")
        #expect(settings.askAIBlockedReason != nil)
        let textOnly = try settings.resolvedPreset(for: id)
        let textKeys = try NativeKeys(textOnly)
        let textTransport = NativeTransport(Data())
        let textProvider = ProviderFactory.make(textOnly, credentials: textKeys, transport: textTransport)
        var handwriting = AIRequest(model: "custom-vision-model", systemPrompt: "", instruction: "Read this")
        handwriting.pngImages = [Data()]
        do { _ = try await collect(textProvider, handwriting); Issue.record("Expected vision gate") }
        catch { #expect(error as? AIError == .modelLacksVision) }
        #expect(textKeys.reads == 0 && textTransport.recorded.isEmpty)
        settings.providers[id]?.visionOverrides["custom-vision-model"] = true
        #expect(settings.askAIBlockedReason == nil)
        let preset = try settings.resolvedPreset(for: id)
        let keys = try NativeKeys(preset)
        #expect(throws: AIError.invalidRequest) { try ModelDiscovery.request(for: preset, credentials: keys) }
        #expect(keys.reads == 0)
        let models = try await ModelDiscovery.fetch(preset, credentials: keys)
        #expect(models.contains { $0.id == "custom-vision-model" && $0.vision == true })
        let transport = NativeTransport(try fixture(id + "-success"))
        let provider = ProviderFactory.make(preset, credentials: keys, transport: transport)
        #expect(await ConnectionTest.run(provider, model: "custom-vision-model") == nil)
    }
    @Test(arguments: ids) @MainActor
    func nativeAdapterAppliesThroughUnmodifiedAskAIFlow(_ id: String) async throws {
        let (provider, transport, _, request) = try setup(id)
        let page = Page(id: UUID(), size: PageSize(width: 2_000, height: 2_000), background: .blank)
        let document = FakeAskDocument(type: .canvas, pages: [page])
        let ask = AskAIController(document: document, region: { CGRect(x: 100, y: 100, width: 200, height: 100) },
                                  provider: { (provider, request.model) }, blocked: { nil })
        ask.ask()
        for _ in 0..<300 where ask.isPending { try await Task.sleep(for: .milliseconds(10)) }
        #expect(ask.phase == .idle)
        #expect(document.applyCount == 1 && document.lastActionName == "AI Answer")
        #expect(document.snapshot.objects.first?.source == "x=4")
        #expect(document.snapshot.objects.first?.type == .latex)
        #expect(document.conversation.appliedRequests.count == 1)
        #expect(transport.recorded.count == 1)
    }

}
