import Testing
import Foundation
import Security
@testable import PencilEcho

private final class ProviderFixtureBundle: NSObject {}

private struct FixtureCredentials: ProviderCredentials {
    let identity: ProviderIdentity
    func read(for identity: ProviderIdentity) throws -> String? { self.identity == identity ? "synthetic-test-key" : nil }
}

/// Counters are lock-protected; the fixture never opens a network connection.
private final class FixtureTransport: ProviderTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var cancelCount = 0
    let status: Int
    let body: Data
    let contentType: String
    let pause: Bool
    let failure: AIError?

    init(status: Int = 200, body: Data, contentType: String = "text/event-stream", pause: Bool = false, failure: AIError? = nil) {
        self.status = status; self.body = body; self.contentType = contentType; self.pause = pause; self.failure = failure
    }
    var recorded: [URLRequest] { lock.withLock { requests } }
    var cancelled: Bool { lock.withLock { cancelCount > 0 } }

    func open(_ request: URLRequest) -> ProviderHTTPStream {
        lock.withLock { requests.append(request) }
        let pair = AsyncThrowingStream<ProviderHTTPEvent, Error>.makeStream()
        let producer = Task {
            pair.continuation.yield(.response(status: status, contentType: contentType))
            pair.continuation.yield(.data(body))
            if pause {
                do { try await Task.sleep(for: .seconds(120)) }
                catch { pair.continuation.finish(throwing: AIError.cancelled); return }
            }
            if let failure { pair.continuation.finish(throwing: failure) }
            else { pair.continuation.finish() }
        }
        return ProviderHTTPStream(events: pair.stream, cancel: { [self] in
            lock.withLock { cancelCount += 1 }
            producer.cancel()
            pair.continuation.finish(throwing: AIError.cancelled)
        })
    }
}

private actor EventRecorder {
    var events: [AIEvent] = []
    func append(_ event: AIEvent) { events.append(event) }
}

struct ProviderAdapterTests {
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle(for: ProviderFixtureBundle.self).url(forResource: name, withExtension: ext, subdirectory: "providers"))
        return try Data(contentsOf: url)
    }
    private func request(images: Bool = false, model: String = "qwen-vl-plus") throws -> AIRequest {
        let png = try images ? Data(contentsOf: #require(Bundle.main.url(forResource: "handwritten-equation", withExtension: "png"))) : Data()
        return AIRequest(model: model, systemPrompt: "Return JSON.", instruction: "Solve the equation.", pngImages: images ? [png] : [])
    }
    private func provider(_ transport: FixtureTransport, preset: ProviderPreset = QwenPresets.all[0]) throws -> OpenAICompatibleProvider {
        let identity = try ProviderIdentity(presetID: preset.id, baseURL: preset.baseURL)
        return OpenAICompatibleProvider(preset: preset, credentials: FixtureCredentials(identity: identity), transport: transport)
    }
    private func collect(_ provider: OpenAICompatibleProvider, _ request: AIRequest) async throws -> [AIEvent] {
        var result: [AIEvent] = []
        for try await event in provider.send(request) { result.append(event) }
        return result
    }

    @Test func streamedFixtureProducesDeltasUsageAndOneCompletion() async throws {
        let transport = FixtureTransport(body: try fixture("stream-success", "sse"))
        let events = try await collect(provider(transport), request(images: true))
        let chunks = events.compactMap { if case .textDelta(let text) = $0 { return text }; return nil }
        let complete = events.compactMap { if case .completed(let text) = $0 { return text }; return nil }
        #expect(complete == [chunks.joined()])
        #expect(events.contains(.usage(AIUsage(promptTokens: 12, completionTokens: 30, totalTokens: 42))))
        #expect(transport.recorded.count == 1)
        #expect(transport.cancelled)
        let sent = try #require(transport.recorded.first)
        #expect(sent.url?.absoluteString == "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-key")
        let data = try #require(sent.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.last?["content"] as? [[String: Any]])
        #expect((content.last?["image_url"] as? [String: String])?["url"]?.hasPrefix("data:image/png;base64,") == true)
    }

    @Test(arguments: [401, 403, 404, 408, 429, 500, 504, 302])
    func statusErrorsAreNormalizedWithoutBodyText(_ status: Int) async throws {
        let body = try fixture(status == 429 ? "rate-limit" : "auth-error", "json")
        let transport = FixtureTransport(status: status, body: body, contentType: "application/json")
        do { _ = try await collect(provider(transport), request()); Issue.record("Expected a normalized error") }
        catch { #expect(error as? AIError == AIError.http(status)) }
        #expect(transport.recorded.count == 1)
        #expect(transport.cancelled)
    }

    @Test func safe400ModelCodeMapsWithoutLeakingBody() async throws {
        let transport = FixtureTransport(status: 400, body: Data(#"{"error":{"code":"model_not_found","message":"private provider detail"}}"#.utf8))
        do { _ = try await collect(provider(transport), request()); Issue.record("Expected unsupportedModel") }
        catch { #expect(error as? AIError == .unsupportedModel) }
    }

    @Test func malformedSSEJSONIsRejected() async throws {
        let transport = FixtureTransport(body: try fixture("malformed", "sse"))
        do { _ = try await collect(provider(transport), request()); Issue.record("Expected invalidOutput") }
        catch { #expect(error as? AIError == .invalidOutput) }
    }

    @Test func imageToTextOnlyModelFailsBeforeTransport() async throws {
        let transport = FixtureTransport(body: Data())
        do { _ = try await collect(provider(transport), request(images: true, model: "qwen-turbo")); Issue.record("Expected modelLacksVision") }
        catch { #expect(error as? AIError == .modelLacksVision) }
        #expect(transport.recorded.isEmpty)
    }

    @Test func unknownModelFailsClosedBeforeTransport() async throws {
        let transport = FixtureTransport(body: Data())
        do { _ = try await collect(provider(transport), request(model: "unknown-vision-name")); Issue.record("Expected unsupportedModel") }
        catch { #expect(error as? AIError == .unsupportedModel) }
        #expect(transport.recorded.isEmpty)
    }

    @Test func credentialCannotCrossRegionOrEndpoint() throws {
        let global = QwenPresets.all[0]
        let identity = try ProviderIdentity(presetID: global.id, baseURL: global.baseURL)
        let credentials = FixtureCredentials(identity: identity)
        for preset in QwenPresets.all.dropFirst() {
            let other = OpenAICompatibleProvider(preset: preset, credentials: credentials)
            #expect(throws: AIError.invalidCredentials) { try other.makeRequest(request()) }
        }
        let changed = ProviderPreset(id: global.id, displayName: "Changed", baseURL: URL(string: "https://example.invalid/v1")!,
                                     authStyle: .bearer, defaultModels: global.defaultModels)
        #expect(throws: AIError.invalidCredentials) { try OpenAICompatibleProvider(preset: changed, credentials: credentials).makeRequest(request()) }
        #expect(try ProviderIdentity(presetID: global.id, baseURL: URL(string: global.baseURL.absoluteString + "/")!) == identity)
    }

    @Test func keychainRoundTripIsThisDeviceOnlyAndIsolated() throws {
        let id = UUID().uuidString
        let identity = try ProviderIdentity(presetID: "fixture-" + id, baseURL: URL(string: "https://example.invalid/" + id)!)
        let other = try ProviderIdentity(presetID: identity.presetID, baseURL: URL(string: "https://example.invalid/other")!)
        let store = KeychainStore()
        defer { try? store.delete(for: identity) }
        try store.save("synthetic-fixture-a", for: identity)
        #expect(try store.read(for: identity) == "synthetic-fixture-a")
        #expect(try store.read(for: other) == nil)
        try store.save("synthetic-fixture-b", for: identity)
        #expect(try store.read(for: identity) == "synthetic-fixture-b")
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "com.chrixcrusher.pencilecho.ai-keys",
                                   kSecAttrAccount as String: identity.account, kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect((attributes[kSecAttrAccessible as String] as? String) == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String))
        try store.delete(for: identity)
        #expect(try store.read(for: identity) == nil)
    }

    @Test func schemaModeAndQuirksAreDataDriven() throws {
        let capabilities = ModelCapabilities(vision: true, streaming: true, structuredOutput: .jsonSchema, maxImageBytes: 5_000_000)
        var preset = ProviderPreset(id: "fixture", displayName: "Fixture", baseURL: URL(string: "https://example.invalid/v1")!,
                                    authStyle: .bearer, defaultModels: [ProviderModel(id: "fixture-model", capabilities: capabilities)])
        var value = try request(model: "fixture-model")
        value.jsonSchema = Data(#"{"type":"object","properties":{},"required":[],"additionalProperties":false}"#.utf8)
        let mock = FixtureTransport(body: Data())
        func body(_ preset: ProviderPreset) throws -> [String: Any] {
            let data = try #require(provider(mock, preset: preset).makeRequest(value).httpBody)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        #expect((try body(preset)["response_format"] as? [String: Any])?["type"] as? String == "json_schema")
        preset.quirks = [.jsonModeOnly, .noStreamUsage, .noSystemRole, .disableThinking]
        let changed = try body(preset)
        #expect((changed["response_format"] as? [String: Any])?["type"] as? String == "json_object")
        #expect(changed["stream_options"] == nil)
        #expect(changed["enable_thinking"] as? Bool == false)
        #expect((changed["messages"] as? [[String: Any]])?.count == 1)
        preset.defaultModels.forEach { #expect($0.id == "fixture-model") }
    }

    @Test func qwenNonThinkingFlagIsModelSpecific() throws {
        let adapter = try provider(FixtureTransport(body: Data()))
        let current = try adapter.makeRequest(request(model: "qwen3-vl-plus"))
        let currentData = try #require(current.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        #expect(body["enable_thinking"] as? Bool == false)
        let legacy = try adapter.makeRequest(request(model: "qwen-vl-plus"))
        let legacyData = try #require(legacy.httpBody)
        let legacyBody = try #require(JSONSerialization.jsonObject(with: legacyData) as? [String: Any])
        #expect(legacyBody["enable_thinking"] == nil)
    }

    @Test func promptOnlySchemaFallbackDoesNotClaimStructuredSupport() throws {
        let preset = ProviderPreset(id: "fixture", displayName: "Fixture", baseURL: URL(string: "https://example.invalid/v1")!,
                                    authStyle: .bearer, defaultModels: [ProviderModel(id: "fixture-model", capabilities: ModelCapabilities(vision: true, streaming: true, structuredOutput: .none, maxImageBytes: 1_000))])
        var value = try request(model: "fixture-model")
        value.jsonSchema = Data(#"{"type":"object"}"#.utf8)
        let sent = try provider(FixtureTransport(body: Data()), preset: preset).makeRequest(value)
        let data = try #require(sent.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["response_format"] == nil)
        #expect((body["messages"] as? [[String: Any]])?.first?["content"] as? String != value.systemPrompt)
    }

    @Test func midStreamCancellationStopsTransportAndNeverCompletes() async throws {
        let chunk = Data("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}]}\n\n".utf8)
        let transport = FixtureTransport(body: chunk, pause: true)
        let adapter = try provider(transport)
        let value = try request()
        let recorder = EventRecorder()
        let consumer = Task {
            do { for try await event in adapter.send(value) { await recorder.append(event) } }
            catch { #expect(AIError.normalized(error) == .cancelled) }
        }
        for _ in 0..<100 {
            if await recorder.events.contains(.textDelta("partial")) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await recorder.events.contains(.textDelta("partial")))
        consumer.cancel()
        await consumer.value
        for _ in 0..<100 {
            if transport.cancelled { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(transport.cancelled)
        #expect(await !recorder.events.contains { if case .completed = $0 { return true }; return false })
    }

    @Test func fragmentedUTF8MultilineCommentsAndCRLF() throws {
        let wire = Data("\u{FEFF}: comment\r\ndata: {\"choices\":\r\ndata: [{\"delta\":{\"content\":\"解答\"},\"finish_reason\":\"stop\"}]}\r\n\r\ndata: [DONE]".utf8)
        var parser = ProviderSSEParser(), accumulator = ChatStreamAccumulator()
        var events: [AIEvent] = []
        for byte in wire {
            for event in try parser.feed(Data([byte])) { events += try accumulator.accept(event) }
        }
        for event in try parser.finish() { events += try accumulator.accept(event) }
        #expect(events == [.textDelta("解答")])
        #expect(try accumulator.finish() == .completed("解答"))
    }

    @Test func truncatedLengthRefusalAndOversizeOutputFailClosed() throws {
        for payload in [
            #"{"choices":[{"delta":{"content":"partial"},"finish_reason":"length"}]}"#,
            #"{"choices":[{"delta":{"refusal":"no"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"tool_calls":[]},"finish_reason":"stop"}]}"#
        ] {
            var accumulator = ChatStreamAccumulator()
            #expect(throws: AIError.invalidOutput) { try accumulator.accept(payload) }
        }
        var unfinished = ChatStreamAccumulator()
        _ = try unfinished.accept(#"{"choices":[{"delta":{"content":"unfinished"},"finish_reason":null}]}"#)
        #expect(throws: AIError.invalidOutput) { try unfinished.finish() }
        #expect(throws: AIError.invalidOutput) { try unfinished.accept("[DONE]") }
        var parser = ProviderSSEParser()
        #expect(throws: AIError.invalidOutput) { try parser.feed(Data(repeating: 65, count: ProviderSSEParser.maxLineBytes + 1)) }
        var large = ChatStreamAccumulator()
        let root: [String: Any] = ["choices": [["delta": ["content": String(repeating: "x", count: 256 * 1_024 + 1)], "finish_reason": "stop"]]]
        let payload = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        #expect(throws: AIError.invalidOutput) { try large.accept(payload) }
    }

    @Test func schemaRequestRejectsMalformedFinalJSON() async throws {
        let wire = Data("data: {\"choices\":[{\"delta\":{\"content\":\"not JSON\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8)
        var value = try request()
        value.jsonSchema = Data("{}".utf8)
        do { _ = try await collect(provider(FixtureTransport(body: wire)), value); Issue.record("Expected invalidOutput") }
        catch { #expect(error as? AIError == .invalidOutput) }
    }

    @Test func wrongContentTypeAndTimeoutAreNormalized() async throws {
        for transport in [FixtureTransport(body: Data(), contentType: "text/html"),
                          FixtureTransport(body: Data(), failure: .timeout)] {
            do { _ = try await collect(provider(transport), request()); Issue.record("Expected error") }
            catch { #expect(error as? AIError == (transport.failure ?? .invalidOutput)) }
        }
    }

    @Test func invalidPNGAndOversizeFailBeforeSending() throws {
        let transport = FixtureTransport(body: Data())
        var value = try request()
        value.pngImages = [Data("not an image".utf8)]
        #expect(throws: AIError.invalidRequest) { try provider(transport).makeRequest(value) }
        value.pngImages = [Data(repeating: 0, count: 5_000_001)]
        #expect(throws: AIError.imageTooLarge) { try provider(transport).makeRequest(value) }
        #expect(transport.recorded.isEmpty)
    }

    @Test(arguments: ["http://example.invalid/v1", "https://user:password@example.invalid/v1", "https://example.invalid/v1?q=x", "https://example.invalid/v1#x"])
    func unsafeEndpointsAreRejected(_ value: String) throws {
        #expect(throws: AIError.invalidRequest) { try ProviderIdentity(presetID: "fixture", baseURL: #require(URL(string: value))) }
    }
    @Test func productionTransportStreamsAndClosesAfterDONE() async throws {
        let base = URL(string: "https://fixture.invalid/" + UUID().uuidString)!
        let endpoint = base.appendingPathComponent("chat/completions")
        FixtureURLProtocol.registry.add(endpoint, body: try fixture("stream-success", "sse"))
        defer { FixtureURLProtocol.registry.remove(endpoint) }
        let preset = ProviderPreset(id: "transport-test", displayName: "Fixture", baseURL: base, authStyle: .bearer,
                                    defaultModels: QwenPresets.all[0].defaultModels)
        var adapter = try provider(FixtureTransport(body: Data()), preset: preset)
        adapter.transport = URLSessionProviderTransport { $0.protocolClasses = [FixtureURLProtocol.self] }
        let events = try await collect(adapter, request())
        #expect(events.contains { if case .completed = $0 { return true }; return false })
        for _ in 0..<100 {
            if FixtureURLProtocol.registry.wasStopped(endpoint) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FixtureURLProtocol.registry.wasStopped(endpoint))
    }

    @Test func productionTransportCancellationReachesURLSessionTask() async throws {
        let base = URL(string: "https://fixture.invalid/" + UUID().uuidString)!
        let endpoint = base.appendingPathComponent("chat/completions")
        let partial = Data("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}]}\n\n".utf8)
        FixtureURLProtocol.registry.add(endpoint, body: partial)
        defer { FixtureURLProtocol.registry.remove(endpoint) }
        let preset = ProviderPreset(id: "transport-test", displayName: "Fixture", baseURL: base, authStyle: .bearer,
                                    defaultModels: QwenPresets.all[0].defaultModels)
        var adapter = try provider(FixtureTransport(body: Data()), preset: preset)
        adapter.transport = URLSessionProviderTransport { $0.protocolClasses = [FixtureURLProtocol.self] }
        let providerToRead = adapter
        let value = try request()
        let recorder = EventRecorder()
        let consumer = Task {
            do { for try await event in providerToRead.send(value) { await recorder.append(event) } }
            catch { #expect(AIError.normalized(error) == .cancelled) }
        }
        for _ in 0..<100 {
            if await recorder.events.contains(.textDelta("partial")) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await recorder.events.contains(.textDelta("partial")))
        consumer.cancel()
        await consumer.value
        for _ in 0..<100 {
            if FixtureURLProtocol.registry.wasStopped(endpoint) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FixtureURLProtocol.registry.wasStopped(endpoint))
        #expect(await !recorder.events.contains { if case .completed = $0 { return true }; return false })
    }

}


/// Uses URLSession's real delegate/cancellation path while intercepting only
/// fixture.invalid. It sends no packets and intentionally leaves responses open.
private final class FixtureURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = Registry()
    final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [URL: Data] = [:]
        private var stopped: Set<URL> = []
        func add(_ url: URL, body: Data) { lock.withLock { bodies[url] = body } }
        func data(_ url: URL) -> Data? { lock.withLock { bodies[url] } }
        func markStopped(_ url: URL) { _ = lock.withLock { stopped.insert(url) } }
        func wasStopped(_ url: URL) -> Bool { lock.withLock { stopped.contains(url) } }
        func remove(_ url: URL) { lock.withLock { bodies.removeValue(forKey: url); stopped.remove(url) } }
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let body = Self.registry.data(url),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
    }
    override func stopLoading() { if let url = request.url { Self.registry.markStopped(url) } }
}
