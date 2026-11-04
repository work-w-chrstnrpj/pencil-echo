import Foundation
import Testing
@testable import PencilEcho

// Ticket 012: every preset against synthetic fixtures (no network), credential and
// endpoint isolation when switching providers, vision gating, settings, and /models parsing.

private final class SettingsFixtureBundle: NSObject {}

/// Keys by exact identity, like Keychain; records every read.
final class MemoryCredentials: ProviderCredentials, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [ProviderIdentity: String] = [:]
    private(set) var reads: [ProviderIdentity] = []
    func save(_ key: String, for identity: ProviderIdentity) { lock.withLock { keys[identity] = key } }
    func read(for identity: ProviderIdentity) throws -> String? {
        lock.withLock { reads.append(identity); return keys[identity] }
    }
}

final class RecordingTransport: ProviderTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    let status: Int, body: Data, contentType: String, pause: Bool
    init(status: Int = 200, body: Data, contentType: String = "text/event-stream", pause: Bool = false) {
        self.status = status; self.body = body; self.contentType = contentType; self.pause = pause
    }
    var recorded: [URLRequest] { lock.withLock { requests } }

    func open(_ request: URLRequest) -> ProviderHTTPStream {
        lock.withLock { requests.append(request) }
        let pair = AsyncThrowingStream<ProviderHTTPEvent, Error>.makeStream()
        let producer = Task { [status, body, contentType, pause] in
            pair.continuation.yield(.response(status: status, contentType: contentType))
            pair.continuation.yield(.data(body))
            if pause { try? await Task.sleep(for: .seconds(60)) }
            pair.continuation.finish()
        }
        return ProviderHTTPStream(events: pair.stream, cancel: { producer.cancel(); pair.continuation.finish(throwing: AIError.cancelled) })
    }
}

struct ModelListFixture: ModelListTransport {
    let status: Int
    let body: Data
    let seen: @Sendable (URLRequest) -> Void
    func get(_ request: URLRequest) async throws -> (status: Int, body: Data) { seen(request); return (status, body) }
}

struct ProviderSettingsTests {
    static let model = "fixture-vision-model"
    /// Every preset that works without user input; the custom one gets an endpoint.
    static let presetIDs = ProviderCatalog.all.filter { $0.authStyle == .bearer }.map(\.id)

    func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle(for: SettingsFixtureBundle.self).url(forResource: name, withExtension: ext, subdirectory: "providers"))
        return try Data(contentsOf: url)
    }

    /// Settings with `presetID` selected and a vision-enabled fixture model.
    func settings(_ presetID: String) -> AISettings {
        var settings = AISettings()
        settings.selectedPresetID = presetID
        settings.providers[presetID] = ProviderSettings(
            baseURLOverride: presetID == ProviderCatalog.customID ? "https://llm.example.test/v1" : nil,
            model: Self.model, visionOverrides: [Self.model: true])
        return settings
    }

    func provider(_ presetID: String, _ transport: RecordingTransport, keyed: Bool = true) throws -> (OpenAICompatibleProvider, MemoryCredentials) {
        let settings = settings(presetID)
        let credentials = MemoryCredentials()
        if keyed { credentials.save("key-for-\(presetID)", for: try #require(settings.identity(for: presetID))) }
        let preset = try settings.resolvedPreset(for: presetID)
        return (OpenAICompatibleProvider(preset: preset, credentials: credentials, transport: transport), credentials)
    }

    func request(image: Bool = false) -> AIRequest {
        AIRequest(model: Self.model, systemPrompt: "Return JSON.", instruction: "Solve.",
                  pngImages: image ? [Self.tinyPNG] : [])
    }

    static let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    func collect(_ provider: OpenAICompatibleProvider, _ request: AIRequest) async throws -> [AIEvent] {
        var events: [AIEvent] = []
        for try await event in provider.send(request) { events.append(event) }
        return events
    }

    // MARK: Fixtures per preset

    @Test(arguments: presetIDs)
    func streamedSuccess(_ presetID: String) async throws {
        let transport = RecordingTransport(body: try fixture("stream-success", "sse"))
        let (provider, _) = try provider(presetID, transport)
        let events = try await collect(provider, request(image: true))
        #expect(events.contains { if case .completed = $0 { true } else { false } })
        let sent = try #require(transport.recorded.first)
        let base = try #require(settings(presetID).baseURL(for: presetID))
        #expect(sent.url == base.appendingPathComponent("chat/completions"))
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer key-for-\(presetID)")
        let httpBody = try #require(sent.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        let preset = try #require(ProviderCatalog.preset(presetID))
        #expect((body["max_completion_tokens"] != nil) == preset.quirks.contains(.maxCompletionTokens))
        #expect((body["max_tokens"] != nil) == !preset.quirks.contains(.maxCompletionTokens))
        #expect((body["stream_options"] != nil) == !preset.quirks.contains(.noStreamUsage))
    }

    @Test(arguments: presetIDs)
    func authFailure(_ presetID: String) async throws {
        let transport = RecordingTransport(status: 401, body: try fixture("auth-error", "json"), contentType: "application/json")
        let (provider, _) = try provider(presetID, transport)
        await #expect(throws: AIError.invalidCredentials) { _ = try await collect(provider, request()) }
    }

    @Test(arguments: presetIDs)
    func rateLimit(_ presetID: String) async throws {
        let transport = RecordingTransport(status: 429, body: try fixture("rate-limit", "json"), contentType: "application/json")
        let (provider, _) = try provider(presetID, transport)
        await #expect(throws: AIError.rateLimited) { _ = try await collect(provider, request()) }
    }

    @Test(arguments: presetIDs)
    func malformedOutput(_ presetID: String) async throws {
        let transport = RecordingTransport(body: try fixture("malformed", "sse"))
        let (provider, _) = try provider(presetID, transport)
        await #expect(throws: AIError.invalidOutput) { _ = try await collect(provider, request()) }
    }

    @Test(arguments: presetIDs)
    func cancel(_ presetID: String) async throws {
        let transport = RecordingTransport(body: Data(), pause: true)
        let (provider, _) = try provider(presetID, transport)
        let value = request()
        // Cancellation either ends the stream or throws `cancelled`; it never completes.
        let task = Task { () -> [AIEvent] in
            var events: [AIEvent] = []
            do { for try await event in provider.send(value) { events.append(event) } }
            catch { #expect(AIError.normalized(error) == .cancelled) }
            return events
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let events = await task.value
        #expect(!events.contains { if case .completed = $0 { true } else { false } })
    }

    // MARK: Isolation and gating

    @Test func switchingProviderNeverReusesAnotherKeyOrEndpoint() async throws {
        var settings = settings("openai")
        let credentials = MemoryCredentials()
        credentials.save("openai-key", for: try #require(settings.identity(for: "openai")))

        // Switch to Groq: its request must not use OpenAI's key or URL.
        settings.selectedPresetID = "groq"
        settings.providers["groq"] = ProviderSettings(baseURLOverride: nil, model: Self.model, visionOverrides: [Self.model: true])
        let transport = RecordingTransport(body: try fixture("stream-success", "sse"))
        let groq = OpenAICompatibleProvider(preset: try settings.resolvedPreset(for: "groq"), credentials: credentials, transport: transport)
        await #expect(throws: AIError.invalidCredentials) { _ = try await collect(groq, request()) }
        #expect(transport.recorded.isEmpty)
        #expect(credentials.reads.last?.presetID == "groq")
        #expect(credentials.reads.last?.baseURL.host() == "api.groq.com")

        // Overriding OpenAI's endpoint makes its saved key unusable too.
        settings.providers["openai"]?.baseURLOverride = "https://proxy.example.test/v1"
        let moved = OpenAICompatibleProvider(preset: try settings.resolvedPreset(for: "openai"), credentials: credentials, transport: transport)
        await #expect(throws: AIError.invalidCredentials) { _ = try await collect(moved, request()) }
        #expect(transport.recorded.isEmpty)
    }

    @Test func imageToNonVisionModelFailsBeforeTheNetwork() async throws {
        var settings = settings("mistral")
        settings.providers["mistral"]?.visionOverrides[Self.model] = false
        let credentials = MemoryCredentials()
        credentials.save("k", for: try #require(settings.identity(for: "mistral")))
        let transport = RecordingTransport(body: try fixture("stream-success", "sse"))
        let provider = OpenAICompatibleProvider(preset: try settings.resolvedPreset(for: "mistral"), credentials: credentials, transport: transport)
        await #expect(throws: AIError.modelLacksVision) { _ = try await collect(provider, request(image: true)) }
        #expect(transport.recorded.isEmpty && credentials.reads.isEmpty)
        #expect(settings.askAIBlockedReason?.contains("vision") == true)
    }

    // MARK: Settings

    @Test func defaultsKeepTheQwenVisionModel() {
        let settings = AISettings()
        #expect(settings.selectedPresetID == "qwen-global")
        #expect(settings.settings(for: "qwen-global").model == "qwen3-vl-plus")
        #expect(settings.capabilities(for: "qwen-global", model: "qwen3-vl-plus").vision)
        #expect(settings.askAIBlockedReason == nil)
        #expect(settings.settings(for: "mistral").model == "mistral-medium-2508")
        #expect(settings.capabilities(for: "openai", model: "anything").vision == false)
    }

    @Test func customEndpointIsRequiredAndMustBeHTTPS() throws {
        var settings = AISettings()
        settings.selectedPresetID = ProviderCatalog.customID
        settings.providers[ProviderCatalog.customID] = ProviderSettings(baseURLOverride: nil, model: "m", visionOverrides: ["m": true])
        #expect(settings.baseURL(for: ProviderCatalog.customID) == nil)
        #expect(throws: AIError.invalidRequest) { try settings.resolvedPreset(for: ProviderCatalog.customID) }
        #expect(settings.askAIBlockedReason?.contains("endpoint") == true)
        for bad in ["http://plain.example.test/v1", "https://u:p@x.example.test/v1", "not a url"] {
            settings.providers[ProviderCatalog.customID]?.baseURLOverride = bad
            #expect(settings.baseURL(for: ProviderCatalog.customID) == nil)
        }
        settings.providers[ProviderCatalog.customID]?.baseURLOverride = "https://LLM.Example.test/v1/"
        #expect(settings.baseURL(for: ProviderCatalog.customID)?.absoluteString == "https://llm.example.test/v1")
        #expect(settings.askAIBlockedReason == nil)
    }

    @Test func resolvedPresetCarriesTheChosenModel() throws {
        var settings = AISettings()
        settings.providers["groq"] = ProviderSettings(baseURLOverride: nil, model: "typed/model", visionOverrides: ["typed/model": true])
        let preset = try settings.resolvedPreset(for: "groq")
        #expect(preset.defaultModels.first?.id == "typed/model" && preset.defaultModels.first?.capabilities.vision == true)
        #expect(preset.defaultModels.first?.capabilities.structuredOutput == ModelCapabilities.StructuredOutput.none)
        #expect(preset.quirks == ProviderCatalog.preset("groq")?.quirks)
    }

    @Test func settingsPersist() throws {
        let defaults = try #require(UserDefaults(suiteName: "ProviderSettingsTests-\(UUID().uuidString)"))
        var settings = AISettings()
        settings.selectedPresetID = "openrouter"
        settings.providers["openrouter"] = ProviderSettings(baseURLOverride: nil, model: "vendor/m", visionOverrides: ["vendor/m": true])
        settings.save(defaults)
        #expect(AISettings.load(defaults) == settings)
        defaults.set(Data("garbage".utf8), forKey: AISettings.defaultsKey)
        #expect(AISettings.load(defaults) == AISettings())
    }

    @Test func catalogCoversTheChosenProviders() {
        let ids = Set(ProviderCatalog.all.map(\.id))
        for id in ["qwen-global", "qwen-us", "qwen-china", "openai", "openrouter", "cerebras", "groq", "huggingface",
                   "mistral", "nvidia", "anthropic", "gemini", ProviderCatalog.customID] {
            #expect(ids.contains(id), "missing \(id)")
        }
        #expect(ids.count == ProviderCatalog.all.count)
        for preset in ProviderCatalog.all where preset.id != ProviderCatalog.customID {
            #expect((try? ProviderIdentity(presetID: preset.id, baseURL: preset.baseURL)) != nil)
        }
    }

    // MARK: Model discovery

    @Test func modelListParsesVisionMetadata() throws {
        let body = Data("""
        {"data":[
          {"id":"b/vision","architecture":{"input_modalities":["text","image"]}},
          {"id":"a/text","architecture":{"input_modalities":["text"]}},
          {"id":"mistral-x","capabilities":{"vision":true}},
          {"id":"plain"},
          {"id":"plain"},
          {"id":""}
        ]}
        """.utf8)
        let models = try ModelDiscovery.parse(body)
        #expect(models.map(\.id) == ["a/text", "b/vision", "mistral-x", "plain"])
        #expect(models.map(\.vision) == [false, true, true, nil])
        #expect(throws: AIError.invalidOutput) { try ModelDiscovery.parse(Data("{\"models\":[]}".utf8)) }
        #expect(throws: AIError.invalidOutput) { try ModelDiscovery.parse(Data("nope".utf8)) }
    }

    @Test func modelListSendsOnlyItsOwnKey() async throws {
        let settings = settings("openrouter")
        let preset = try settings.resolvedPreset(for: "openrouter")
        let credentials = MemoryCredentials()
        let unauthenticated = try ModelDiscovery.request(for: preset, credentials: credentials)
        #expect(unauthenticated.url?.absoluteString == "https://openrouter.ai/api/v1/models")
        #expect(unauthenticated.value(forHTTPHeaderField: "Authorization") == nil)

        credentials.save("other", for: try ProviderIdentity(presetID: "groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!))
        #expect(try ModelDiscovery.request(for: preset, credentials: credentials).value(forHTTPHeaderField: "Authorization") == nil)
        credentials.save("mine", for: try #require(settings.identity(for: "openrouter")))
        #expect(try ModelDiscovery.request(for: preset, credentials: credentials).value(forHTTPHeaderField: "Authorization") == "Bearer mine")

        let failing = ModelListFixture(status: 401, body: Data(), seen: { _ in })
        await #expect(throws: AIError.invalidCredentials) { _ = try await ModelDiscovery.fetch(preset, credentials: credentials, transport: failing) }
    }

    // MARK: Connection test and logging

    @Test func connectionTestReportsSuccessAndFailure() async throws {
        let ok = try provider("openai", RecordingTransport(body: try fixture("stream-success", "sse"))).0
        #expect(await ConnectionTest.run(ok, model: Self.model) == nil)
        let denied = try provider("openai", RecordingTransport(status: 401, body: Data(), contentType: "application/json")).0
        #expect(await ConnectionTest.run(denied, model: Self.model) == .invalidCredentials)
        let missingKey = try provider("openai", RecordingTransport(body: Data()), keyed: false).0
        #expect(await ConnectionTest.run(missingKey, model: Self.model) == .invalidCredentials)
    }

    @Test func providerAndSettingsSourcesDoNotLog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = ["service/Providers", "service/AI", "application/App/Settings", "application/App/AskAI"]
            .flatMap { folder in
                (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)) ?? []
            }
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 8)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for call in ["print(", "NSLog(", "os_log(", "Logger(", "debugPrint(", "dump("] {
                #expect(!text.contains(call), "\(file.lastPathComponent) contains \(call)")
            }
        }
    }
}

struct EditorToolbarProviderTests {
    @Test func legacyProviderSettingsStillDecode() throws {
        let data = Data(#"{"model":"old","visionOverrides":{}}"#.utf8)
        let settings = try JSONDecoder().decode(ProviderSettings.self, from: data)
        #expect(settings.reasoning == nil)
        #expect(!ReasoningLevel.supports(preset: "custom", model: "gpt-5.1"))
        #expect(!ReasoningLevel.supports(preset: "anthropic", model: "claude-sonnet-5-5"))
        #expect(!ReasoningLevel.supports(preset: "gemini", model: "gemini-3.8-flash"))
    }

    @Test(arguments: ReasoningLevel.allCases) func adapterReasoningMappings(_ effort: ReasoningLevel) throws {
        for (id, model) in [("openai", "gpt-5.1"), ("anthropic", "claude-sonnet-4-6"), ("gemini", "gemini-2.5-flash")] {
            var settings = AISettings()
            settings.providers[id] = ProviderSettings(model: model, visionOverrides: [model: true], reasoning: effort)
            let preset = try settings.resolvedPreset(for: id)
            let keys = MemoryCredentials()
            keys.save("synthetic", for: try ProviderIdentity(presetID: id, baseURL: preset.baseURL))
            let request = AIRequest(model: model, systemPrompt: "JSON", instruction: "Solve", reasoning: effort)
            let http: URLRequest
            switch id {
            case "anthropic": http = try AnthropicProvider(preset: preset, credentials: keys).makeRequest(request)
            case "gemini": http = try GeminiProvider(preset: preset, credentials: keys).makeRequest(request)
            default: http = try OpenAICompatibleProvider(preset: preset, credentials: keys).makeRequest(request)
            }
            let payload = try #require(http.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            if id == "openai" { #expect(body["reasoning_effort"] as? String == (effort == .off ? "none" : effort.rawValue)) }
            if id == "anthropic" {
                let thinking = try #require(body["thinking"] as? [String: Any])
                #expect(thinking["type"] as? String == (effort == .off ? "disabled" : "enabled"))
                #expect((body["max_tokens"] as? Int) == effort.budget + 4096)
            }
            if id == "gemini" {
                let config = try #require(body["generationConfig"] as? [String: Any])
                #expect((config["thinkingConfig"] as? [String: Int])?["thinkingBudget"] == effort.budget)
            }
        }
    }
}
