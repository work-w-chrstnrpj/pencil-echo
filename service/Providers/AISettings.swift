import Foundation

/// Per-provider choices. Keys are not stored here: they live in Keychain, bound to
/// the preset ID and the exact effective base URL (`ProviderIdentity`).
struct ProviderSettings: Codable, Equatable, Sendable {
    /// Replaces the preset's base URL. Required for the custom preset.
    var baseURLOverride: String?
    var model: String
    /// User-set vision support per model ID; wins over preset and fetched metadata.
    var visionOverrides: [String: Bool] = [:]
    var reasoning: ReasoningLevel? = nil
}

/// AI provider settings (ticket 012). Non-secret, stored in UserDefaults.
struct AISettings: Codable, Equatable, Sendable {
    static let defaultsKey = "ai.settings.v1"
    static let defaultPresetID = "qwen-global"

    var selectedPresetID = AISettings.defaultPresetID
    var providers: [String: ProviderSettings] = [:]

    static func load(_ defaults: UserDefaults = .standard) -> AISettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AISettings.self, from: data) else { return AISettings() }
        return settings
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    func settings(for presetID: String) -> ProviderSettings {
        if let saved = providers[presetID] { return saved }
        let preset = ProviderCatalog.preset(presetID)
        // qwen3-vl-plus stays the Qwen default from ticket 007.
        let model = presetID.hasPrefix("qwen") ? "qwen3-vl-plus" : preset?.defaultModels.first?.id ?? ""
        return ProviderSettings(baseURLOverride: nil, model: model)
    }

    /// The base URL requests and keys use, or nil when the endpoint isn't usable.
    func baseURL(for presetID: String) -> URL? {
        guard let preset = ProviderCatalog.preset(presetID) else { return nil }
        let override = settings(for: presetID).baseURLOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return URL(string: override).flatMap { try? ProviderIdentity(presetID: presetID, baseURL: $0) }?.baseURL
        }
        return presetID == ProviderCatalog.customID ? nil : preset.baseURL
    }

    func identity(for presetID: String) -> ProviderIdentity? {
        baseURL(for: presetID).flatMap { try? ProviderIdentity(presetID: presetID, baseURL: $0) }
    }

    /// The model's capabilities: user override, then preset entry, then off.
    func capabilities(for presetID: String, model: String) -> ModelCapabilities {
        let known = ProviderCatalog.preset(presetID)?.defaultModels.first { $0.id == model }?.capabilities
        var capabilities = known ?? ProviderCatalog.unverifiedCapabilities(vision: false)
        if let vision = settings(for: presetID).visionOverrides[model] {
            capabilities.vision = vision
            if vision && capabilities.maxImageBytes == 0 { capabilities.maxImageBytes = 5_000_000 }
        }
        return capabilities
    }

    /// The preset as requests should see it: effective base URL, and the selected
    /// model present with its effective capabilities. Throws when the endpoint isn't set.
    func resolvedPreset(for presetID: String) throws -> ProviderPreset {
        guard let preset = ProviderCatalog.preset(presetID), let baseURL = baseURL(for: presetID) else {
            throw AIError.invalidRequest
        }
        let model = settings(for: presetID).model.trimmingCharacters(in: .whitespacesAndNewlines)
        var models = preset.defaultModels
        if !model.isEmpty {
            let entry = ProviderModel(id: model, capabilities: capabilities(for: presetID, model: model),
                                      quirks: models.first { $0.id == model }?.quirks ?? [])
            models.removeAll { $0.id == model }
            models.insert(entry, at: 0)
        }
        return ProviderPreset(id: preset.id, displayName: preset.displayName, baseURL: baseURL,
                              authStyle: preset.authStyle, defaultModels: models, quirks: preset.quirks)
    }

    /// Why Ask AI can't run with these settings, or nil when it can.
    var askAIBlockedReason: String? {
        let model = settings(for: selectedPresetID).model.trimmingCharacters(in: .whitespacesAndNewlines)
        if baseURL(for: selectedPresetID) == nil { return "Set this provider's endpoint in AI Settings." }
        if model.isEmpty { return "Choose a model in AI Settings." }
        if !capabilities(for: selectedPresetID, model: model).vision {
            return "\(model) can't read handwriting. Choose a vision model in AI Settings."
        }
        return nil
    }
}

/// Auto Ask (ticket 014): ask after the pen pauses, like PenEcho's Auto AI.
/// Stored apart from `AISettings` so older saved provider settings still decode.
struct AutoAskSettings: Codable, Equatable, Sendable {
    static let defaultsKey = "ai.autoAsk.v1"
    static let delayRange = 1.0...10.0

    var enabled = true
    var delaySeconds = 2.0

    static func load(_ defaults: UserDefaults = .standard) -> AutoAskSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              var settings = try? JSONDecoder().decode(AutoAskSettings.self, from: data) else { return AutoAskSettings() }
        settings.delaySeconds = min(max(settings.delaySeconds, delayRange.lowerBound), delayRange.upperBound)
        return settings
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

// MARK: - Model discovery

struct DiscoveredModel: Equatable, Sendable, Identifiable {
    let id: String
    /// From provider metadata; nil when the provider doesn't say.
    let vision: Bool?
}

protocol ModelListTransport: Sendable {
    func get(_ request: URLRequest) async throws -> (status: Int, body: Data)
}

/// Ephemeral, no cookies or cache, and no redirects, like the 007 chat transport.
struct URLSessionModelListTransport: ModelListTransport {
    func get(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}

enum ModelDiscovery {
    static let maxBytes = 4 * 1_024 * 1_024
    static let maxModels = 2_000

    /// `GET <base>/models`. The key goes only to the identity it is bound to; without a
    /// saved key the request is sent unauthenticated (OpenRouter lists models publicly).
    static func request(for preset: ProviderPreset, credentials: any ProviderCredentials) throws -> URLRequest {
        guard preset.authStyle == .bearer else { throw AIError.invalidRequest }
        let identity = try ProviderIdentity(presetID: preset.id, baseURL: preset.baseURL)
        var request = URLRequest(url: identity.baseURL.appendingPathComponent("models"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = try credentials.read(for: identity), !key.isEmpty {
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func fetch(_ preset: ProviderPreset, credentials: any ProviderCredentials = KeychainStore(),
                      transport: any ModelListTransport = URLSessionModelListTransport()) async throws -> [DiscoveredModel] {
        if preset.authStyle != .bearer {
            return preset.defaultModels.map { DiscoveredModel(id: $0.id, vision: $0.capabilities.vision) }
        }
        let (status, body) = try await transport.get(request(for: preset, credentials: credentials))
        guard status == 200 else { throw AIError.http(status) }
        return try parse(body)
    }

    /// Reads `data[].id` and any image-input metadata. Unknown shapes fail closed.
    static func parse(_ body: Data) throws -> [DiscoveredModel] {
        guard body.count <= maxBytes,
              let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let items = root["data"] as? [[String: Any]] else { throw AIError.invalidOutput }
        var seen = Set<String>()
        var models: [DiscoveredModel] = []
        for item in items.prefix(maxModels) {
            guard let id = item["id"] as? String, !id.isEmpty, id.utf8.count <= 256, seen.insert(id).inserted else { continue }
            models.append(DiscoveredModel(id: id, vision: vision(in: item)))
        }
        return models.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private static func vision(in item: [String: Any]) -> Bool? {
        // OpenRouter: architecture.input_modalities; some routers put it at the top level.
        let modalities = ((item["architecture"] as? [String: Any])?["input_modalities"] ?? item["input_modalities"]) as? [Any]
        if let modalities {
            return modalities.contains { ($0 as? String) == "image" || (($0 as? [String: Any])?["type"] as? String) == "image" }
        }
        // Mistral-style capabilities.vision.
        if let vision = (item["capabilities"] as? [String: Any])?["vision"] as? Bool { return vision }
        return nil
    }
}

// MARK: - Connection test

enum ConnectionTest {
    /// A tiny text-only request on the selected provider and model. No image, no schema.
    static func run(_ provider: any AIProvider, model: String) async -> AIError? {
        let request = AIRequest(model: model, systemPrompt: "Reply with the single word OK.", instruction: "Connection test.")
        do {
            for try await event in provider.send(request) {
                if case .completed = event { return nil }
            }
            return .invalidOutput
        } catch {
            return AIError.normalized(error)
        }
    }
}

struct CanvasAISettings: Codable, Equatable, Sendable {
    static let key = "ai.canvas.v1"
    var appearance = AIAnswerAppearance()
    var thinkingIndicator = true
    static func load(_ defaults: UserDefaults = .standard) -> Self {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

enum ReasoningLevel: String, Codable, CaseIterable, Sendable {
    case off, low, medium, high
    var budget: Int { switch self { case .off: 0; case .low: 1024; case .medium: 4096; case .high: 8192 } }
    // Explicit model gates: routers and unknown/new models do not inherit API claims.
    static func supports(preset: String, model: String) -> Bool {
        switch preset {
        case "openai": ["gpt-5.1", "gpt-5.2"].contains(model)
        case "anthropic": ["claude-sonnet-4-5", "claude-sonnet-4-6", "claude-opus-4-5"].contains(model)
        case "gemini": ["gemini-2.5-flash", "gemini-2.5-flash-lite"].contains(model)
        default: false
        }
    }
}
