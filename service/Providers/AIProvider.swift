import Foundation

struct ModelCapabilities: Equatable, Sendable {
    enum StructuredOutput: Sendable { case none, jsonObject, jsonSchema }
    var vision: Bool
    var streaming: Bool
    var structuredOutput: StructuredOutput
    var maxImageBytes: Int
}

struct ProviderModel: Identifiable, Sendable {
    let id: String
    let capabilities: ModelCapabilities
    var quirks: ProviderQuirks = []
}

struct ProviderQuirks: OptionSet, Sendable {
    let rawValue: Int
    static let noStreamUsage = Self(rawValue: 1 << 0)
    static let jsonModeOnly = Self(rawValue: 1 << 1)
    static let noSystemRole = Self(rawValue: 1 << 2)
    static let disableThinking = Self(rawValue: 1 << 3)
    /// Send `max_completion_tokens`; OpenAI reasoning models reject the deprecated `max_tokens`.
    static let maxCompletionTokens = Self(rawValue: 1 << 4)
}

struct ProviderPreset: Identifiable, Sendable {
    enum AuthStyle: Sendable { case bearer, anthropic, gemini }
    let id: String
    let displayName: String
    let baseURL: URL
    let authStyle: AuthStyle
    let defaultModels: [ProviderModel]
    var quirks: ProviderQuirks = []
}

/// Immutable, app-generated request identity. No credentials in this value.
struct AIRequest: Sendable {
    var requestId = UUID()
    var model: String
    var systemPrompt: String
    var instruction: String
    var pngImages: [Data] = []
    var jsonSchema: Data? = nil
    var reasoning: ReasoningLevel? = nil
    /// Text only, oldest first; the current image and instruction follow these turns.
    var history: [AIChatMessage] = []
}

struct AIUsage: Equatable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
}

enum AIEvent: Equatable, Sendable {
    case textDelta(String)
    case completed(String)
    case usage(AIUsage)
}

/// Fixed diagnostics only: never include server text, credentials or URLs.
enum AIError: Error, Equatable, Sendable, LocalizedError {
    case invalidCredentials, unsupportedModel, modelLacksVision, rateLimited
    case timeout, network, cancelled, invalidOutput, safetyBlocked
    case server(Int)
    case invalidRequest, imageTooLarge, keychain(Int32)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "The selected provider's key is missing or was rejected."
        case .unsupportedModel: "This model is unavailable or has no verified capability entry."
        case .modelLacksVision: "This model cannot receive handwriting images. Choose a vision model."
        case .rateLimited: "The provider rate limit was reached. Retry manually later."
        case .timeout: "The request timed out. You can retry manually."
        case .network: "The provider could not be reached. Check connectivity and retry manually."
        case .cancelled: "Request cancelled."
        case .invalidOutput: "The provider returned incomplete or invalid output."
        case .safetyBlocked: "The selected provider blocked this request or answer. Revise the instruction and retry manually."
        case .server(let status): "The provider returned HTTP \(status)."
        case .invalidRequest: "The request or endpoint is invalid."
        case .imageTooLarge: "The image exceeds this model's local upload limit."
        case .keychain: "The key could not be accessed securely on this device."
        }
    }

    static func normalized(_ error: any Error) -> AIError {
        if let error = error as? AIError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError {
            if error.code == .cancelled { return .cancelled }
            if error.code == .timedOut { return .timeout }
        }
        return .network
    }

    static func http(_ status: Int) -> AIError {
        switch status {
        case 401, 403: .invalidCredentials
        case 404: .unsupportedModel
        case 408, 504: .timeout
        case 429: .rateLimited
        default: .server(status)
        }
    }
}

protocol AIProvider: Sendable {
    func capabilities(model: String) -> ModelCapabilities?
    func send(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error>
}

struct AIChatMessage: Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var text: String
    static func validate(_ history: [Self]) throws {
        guard history.count <= AgentChatHistory.maxTurns * 2,
              history.count.isMultiple(of: 2),
              history.enumerated().allSatisfy({ $0.element.role == ($0.offset.isMultiple(of: 2) ? .user : .assistant) && $0.element.text.utf8.count <= DocumentLimits.maxMessageBytes }) else { throw AIError.invalidRequest }
    }
}
