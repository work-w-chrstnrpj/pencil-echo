import Foundation

/// OpenAI-compatible (012) and native Anthropic/Gemini (013) presets.
/// Facts and sources are in docs/api/providers.md; ProviderFactory owns wire dispatch.
///
/// Default model lists hold only models whose vision support the provider documents.
/// Anything else is entered by ID or fetched from `/models`, with vision off until the
/// provider's metadata or the user says otherwise (`AISettings`).
enum ProviderCatalog {
    static let customID = "custom"

    /// Unknown models: streaming, no structured-output claim (the schema goes in the
    /// prompt and `CommandValidator` enforces it), and the 007 image cap.
    static func unverifiedCapabilities(vision: Bool) -> ModelCapabilities {
        ModelCapabilities(vision: vision, streaming: true, structuredOutput: .none, maxImageBytes: 5_000_000)
    }

    private static func vision(_ id: String) -> ProviderModel {
        ProviderModel(id: id, capabilities: unverifiedCapabilities(vision: true))
    }

    private static func nativeVision(_ id: String) -> ProviderModel {
        ProviderModel(id: id, capabilities: ModelCapabilities(vision: true, streaming: true, structuredOutput: .jsonSchema, maxImageBytes: 5_000_000))
    }

    static let all: [ProviderPreset] = QwenPresets.all + [
        ProviderPreset(id: "openai", displayName: "OpenAI", baseURL: URL(string: "https://api.openai.com/v1")!,
                       authStyle: .bearer, defaultModels: [], quirks: [.maxCompletionTokens]),
        ProviderPreset(id: "openrouter", displayName: "OpenRouter", baseURL: URL(string: "https://openrouter.ai/api/v1")!,
                       authStyle: .bearer, defaultModels: []),
        ProviderPreset(id: "cerebras", displayName: "Cerebras", baseURL: URL(string: "https://api.cerebras.ai/v1")!,
                       authStyle: .bearer, defaultModels: [vision("qwen-3.8-27b")], quirks: [.noStreamUsage]),
        ProviderPreset(id: "groq", displayName: "Groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                       authStyle: .bearer, defaultModels: [vision("qwen/qwen3.8-27b")], quirks: [.noStreamUsage]),
        ProviderPreset(id: "huggingface", displayName: "Hugging Face", baseURL: URL(string: "https://router.huggingface.co/v1")!,
                       authStyle: .bearer, defaultModels: [], quirks: [.noStreamUsage]),
        ProviderPreset(id: "mistral", displayName: "Mistral", baseURL: URL(string: "https://api.mistral.ai/v1")!,
                       authStyle: .bearer,
                       defaultModels: ["mistral-medium-2508", "mistral-small-2506", "mistral-large-2512",
                                       "ministral-14b-2512", "ministral-8b-2512"].map(vision),
                       quirks: [.noStreamUsage]),
        ProviderPreset(id: "nvidia", displayName: "NVIDIA", baseURL: URL(string: "https://integrate.api.nvidia.com/v1")!,
                       authStyle: .bearer, defaultModels: [], quirks: [.noStreamUsage]),
        ProviderPreset(id: "anthropic", displayName: "Anthropic (native)", baseURL: URL(string: "https://api.anthropic.com/v1")!,
                       authStyle: .anthropic, defaultModels: ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"].map(nativeVision)),
        ProviderPreset(id: "gemini", displayName: "Google Gemini (native)", baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
                       authStyle: .gemini, defaultModels: ["gemini-3.8-flash", "gemini-4-argon"].map(nativeVision)),
        // The base URL is a placeholder: a custom endpoint must be set before use.
        ProviderPreset(id: customID, displayName: "Custom (OpenAI-compatible)", baseURL: URL(string: "https://custom.invalid/v1")!,
                       authStyle: .bearer, defaultModels: [], quirks: [.noStreamUsage]),
    ]

    static func preset(_ id: String) -> ProviderPreset? { all.first { $0.id == id } }

    /// What the key is called on each provider's site, for the settings field.
    static func keyName(_ id: String) -> String {
        switch id {
        case "huggingface": "Hugging Face access token"
        case let id where id.hasPrefix("qwen"): "Model Studio API key"
        default: "API key"
        }
    }
}
