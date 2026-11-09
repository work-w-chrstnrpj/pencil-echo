// Ported from PenEcho inspiration/src/providers/api-presets.js @ 341e34d (AGPL-3.0-only).
import Foundation

/// Region URLs ported from upstream; capabilities independently checked against
/// Alibaba's official docs on 2026-11-03. Availability still needs an account test.
enum QwenPresets {
    /// Vision models that Alibaba's free-quota and pricing pages (read 2026-11-09) list
    /// with a separate new-user free quota in Singapore, best answers first. Each alias and
    /// dated snapshot has its own quota. Alibaba stopped granting new quota for most
    /// of these on 2026-10-29, but quota already granted lasts until it expires or runs
    /// out, so an older account may still hold some. Thinking-only and omni models are left out.
    static let freeQuotaVisionModels = [
        "qwen3-vl-plus", "qwen3-vl-plus-2025-12-19", "qwen3-vl-plus-2025-09-23",
        "qwen-vl-max", "qwen-vl-max-latest", "qwen-vl-max-2025-08-13", "qwen-vl-max-2025-04-08",
        "qwen3-vl-235b-a22b-instruct", "qwen3-vl-32b-instruct",
        "qwen3-vl-flash", "qwen3-vl-flash-2026-01-22", "qwen3-vl-flash-2025-10-15",
        "qwen-vl-plus", "qwen-vl-plus-latest", "qwen-vl-plus-2025-08-15", "qwen-vl-plus-2025-05-07",
        "qwen3-vl-30b-a3b-instruct", "qwen3-vl-8b-instruct",
    ]

    private static func model(_ id: String) -> ProviderModel {
        // Open-weight models: schema goes in the prompt, CommandValidator enforces it.
        let openWeight = id.hasSuffix("-instruct")
        let capabilities = ModelCapabilities(vision: true, streaming: true,
                                             structuredOutput: openWeight ? .none : .jsonObject, maxImageBytes: 5_000_000)
        // qwen3-vl-plus and qwen3-vl-flash think by default; Ask AI needs fast answers.
        let hybrid = id.hasPrefix("qwen3-vl-plus") || id.hasPrefix("qwen3-vl-flash")
        return ProviderModel(id: id, capabilities: capabilities, quirks: hybrid ? [.disableThinking] : [])
    }

    private static let models = freeQuotaVisionModels.map(model) + [
        ProviderModel(id: "qwen-turbo", capabilities: ModelCapabilities(vision: false, streaming: true, structuredOutput: .jsonObject, maxImageBytes: 0))
    ]
    static let all: [ProviderPreset] = [
        preset("qwen-global", "Qwen · Singapore", "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"),
        preset("qwen-us", "Qwen · US (Virginia)", "https://dashscope-us.aliyuncs.com/compatible-mode/v1"),
        preset("qwen-china", "Qwen · China (Beijing)", "https://dashscope.aliyuncs.com/compatible-mode/v1")
    ]

    /// Only the Singapore endpoint gives international accounts a free quota.
    static let freeQuotaPresetID = "qwen-global"

    private static func preset(_ id: String, _ name: String, _ url: String) -> ProviderPreset {
        ProviderPreset(id: id, displayName: name, baseURL: URL(string: url)!, authStyle: .bearer,
                       defaultModels: models, quirks: [.jsonModeOnly])
    }
}

// MARK: - Free quota fallback

/// Whether Ask AI moves to the next free-quota vision model, and which models Alibaba
/// has said are used up. Non-secret, stored in UserDefaults.
struct QwenFreeQuotaState: Codable, Equatable, Sendable {
    /// Off by default: the fallback is only free when "Free Quota Only" is on for every
    /// model in the Model Studio console. Otherwise a fallback model may be billed.
    var enabled = false
    var exhausted: [String: Date] = [:]
}

final class QwenFreeQuotaLedger: @unchecked Sendable {
    static let defaultsKey = "ai.qwenFreeQuota.v1"
    private static let lock = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var state: QwenFreeQuotaState {
        Self.lock.withLock {
            defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(QwenFreeQuotaState.self, from: $0) } ?? QwenFreeQuotaState()
        }
    }

    func update(_ change: (inout QwenFreeQuotaState) -> Void) {
        Self.lock.withLock {
            var value = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(QwenFreeQuotaState.self, from: $0) } ?? QwenFreeQuotaState()
            change(&value)
            if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.defaultsKey) }
        }
    }

    func markExhausted(_ model: String, at date: Date = Date()) { update { $0.exhausted[model] = date } }
}

/// Sends with the selected model, then, each time Alibaba answers that a model's free
/// quota is used up (`AllocationQuota.FreeTierOnly`), records it and retries the same
/// request with the next free-quota vision model on the same provider and key.
/// It never retries after any text has streamed, and never switches provider.
struct QwenFreeQuotaProvider: AIProvider {
    let base: any AIProvider
    var candidates: [String] = QwenPresets.freeQuotaVisionModels
    var ledger = QwenFreeQuotaLedger()

    /// Wraps `provider` only for the Singapore preset with the fallback turned on.
    static func wrap(_ provider: any AIProvider, presetID: String, ledger: QwenFreeQuotaLedger = QwenFreeQuotaLedger()) -> any AIProvider {
        guard presetID == QwenPresets.freeQuotaPresetID, ledger.state.enabled else { return provider }
        return QwenFreeQuotaProvider(base: provider, ledger: ledger)
    }

    func capabilities(model: String) -> ModelCapabilities? { base.capabilities(model: model) }

    /// The models a request will try, in order: the selected one, then the list.
    func chain(for request: AIRequest) -> [String] {
        let exhausted = ledger.state.exhausted
        var seen = Set<String>()
        return ([request.model] + candidates).filter { model in
            guard seen.insert(model).inserted, exhausted[model] == nil,
                  let capabilities = base.capabilities(model: model) else { return false }
            return request.pngImages.isEmpty || capabilities.vision
        }
    }

    func send(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(128)) { continuation in
            let task = Task {
                for (index, model) in chain(for: request).enumerated() {
                    var attempt = request
                    attempt.model = model
                    var started = false
                    do {
                        for try await event in base.send(attempt) {
                            started = true
                            switch continuation.yield(event) {
                            case .enqueued: break
                            case .dropped: continuation.finish(throwing: AIError.invalidOutput); return
                            case .terminated: return
                            @unknown default: return
                            }
                        }
                        continuation.finish()
                        return
                    } catch AIError.freeQuotaExhausted where !started {
                        ledger.markExhausted(model)
                    } catch AIError.unsupportedModel where !started && index > 0 {
                        // This account can't use a fallback model; try the next one.
                    } catch {
                        continuation.finish(throwing: AIError.normalized(error))
                        return
                    }
                }
                continuation.finish(throwing: AIError.freeQuotaExhausted)
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
