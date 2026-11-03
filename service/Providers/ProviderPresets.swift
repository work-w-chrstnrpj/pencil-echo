// Ported from PenEcho inspiration/src/providers/api-presets.js @ 341e34d (AGPL-3.0-only).
import Foundation

/// Region URLs ported from upstream; capabilities independently checked against
/// Alibaba's official docs on 2026-11-03. Availability still needs an account test.
enum QwenPresets {
    private static let models = [
        ProviderModel(id: "qwen3-vl-plus", capabilities: ModelCapabilities(vision: true, streaming: true, structuredOutput: .jsonObject, maxImageBytes: 5_000_000), quirks: [.disableThinking]),
        ProviderModel(id: "qwen-vl-plus", capabilities: ModelCapabilities(vision: true, streaming: true, structuredOutput: .jsonObject, maxImageBytes: 5_000_000)),
        ProviderModel(id: "qwen-vl-max", capabilities: ModelCapabilities(vision: true, streaming: true, structuredOutput: .jsonObject, maxImageBytes: 5_000_000)),
        ProviderModel(id: "qwen-turbo", capabilities: ModelCapabilities(vision: false, streaming: true, structuredOutput: .jsonObject, maxImageBytes: 0))
    ]
    static let all: [ProviderPreset] = [
        preset("qwen-global", "Qwen · Singapore", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"),
        preset("qwen-us", "Qwen · US (Virginia)", "https://dashscope-us.aliyuncs.com/compatible-mode/v1"),
        preset("qwen-china", "Qwen · China (Beijing)", "https://dashscope.aliyuncs.com/compatible-mode/v1")
    ]

    private static func preset(_ id: String, _ name: String, _ url: String) -> ProviderPreset {
        ProviderPreset(id: id, displayName: name, baseURL: URL(string: url)!, authStyle: .bearer,
                       defaultModels: models, quirks: [.jsonModeOnly])
    }
}
