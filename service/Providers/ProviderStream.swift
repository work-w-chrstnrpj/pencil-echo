// Ported from PenEcho inspiration/src/server/api-stream.js @ 341e34d (AGPL-3.0-only).
import Foundation

/// Original bounded SSE framing, not a port of the eventsource-parser dependency.
/// Handles arbitrary byte fragmentation, UTF-8 boundaries, CR/LF, comments and
/// multiline data. Limits apply before decoding or accumulating untrusted text.
struct ProviderSSEParser {
    private var line = Data()
    private var fields: [String] = []
    private var eventBytes = 0
    private var wireBytes = 0
    private var skipLF = false
    private var firstLine = true
    static let maxLineBytes = 64 * 1_024
    static let maxEventBytes = 128 * 1_024
    static let maxWireBytes = 2 * 1_024 * 1_024

    mutating func feed(_ data: Data) throws -> [String] {
        wireBytes += data.count
        guard wireBytes <= Self.maxWireBytes else { throw AIError.invalidOutput }
        var events: [String] = []
        for byte in data {
            if skipLF { skipLF = false; if byte == 10 { continue } }
            if byte == 10 || byte == 13 {
                if let event = try endLine() { events.append(event) }
                skipLF = byte == 13
            } else {
                line.append(byte)
                guard line.count <= Self.maxLineBytes else { throw AIError.invalidOutput }
            }
        }
        return events
    }

    mutating func finish() throws -> [String] {
        var events: [String] = []
        if !line.isEmpty, let event = try endLine() { events.append(event) }
        if !fields.isEmpty { events.append(fields.joined(separator: "\n")) }
        fields = []
        eventBytes = 0
        return events
    }

    private mutating func endLine() throws -> String? {
        guard var value = String(data: line, encoding: .utf8) else { throw AIError.invalidOutput }
        line.removeAll(keepingCapacity: true)
        if firstLine { firstLine = false; if value.hasPrefix("\u{FEFF}") { value.removeFirst() } }
        if value.isEmpty {
            defer { fields = []; eventBytes = 0 }
            return fields.isEmpty ? nil : fields.joined(separator: "\n")
        }
        if value.hasPrefix(":") { return nil }
        let split = value.firstIndex(of: ":")
        let field = split.map { String(value[..<$0]) } ?? value
        var content = split.map { String(value[value.index(after: $0)...]) } ?? ""
        if content.hasPrefix(" ") { content.removeFirst() }
        if field == "data" {
            eventBytes += content.utf8.count + 1
            guard eventBytes <= Self.maxEventBytes else { throw AIError.invalidOutput }
            fields.append(content)
        }
        return nil
    }
}

struct ChatStreamAccumulator {
    private(set) var text = ""
    private var byteCount = 0
    private var stopped = false
    private(set) var done = false

    mutating func accept(_ event: String) throws -> [AIEvent] {
        guard !done else { throw AIError.invalidOutput }
        if event == "[DONE]" {
            guard stopped, !text.isEmpty else { throw AIError.invalidOutput }
            done = true
            return []
        }
        guard let root = (try? JSONSerialization.jsonObject(with: Data(event.utf8))) as? [String: Any] else { throw AIError.invalidOutput }
        if root["error"] != nil { throw Self.payloadError(root, fallback: .invalidOutput) }
        guard let choices = root["choices"] as? [[String: Any]], choices.count <= 1 else { throw AIError.invalidOutput }
        var events: [AIEvent] = []
        if let usage = root["usage"] as? [String: Any] {
            func count(_ key: String) throws -> Int? {
                guard let value = usage[key], !(value is NSNull) else { return nil }
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue >= 0,
                      number.doubleValue <= Double(Int32.max), number.doubleValue.rounded() == number.doubleValue else { throw AIError.invalidOutput }
                return number.intValue
            }
            events.append(.usage(try AIUsage(promptTokens: count("prompt_tokens"), completionTokens: count("completion_tokens"), totalTokens: count("total_tokens"))))
        }
        if let choice = choices.first {
            guard (choice["index"] as? Int ?? 0) == 0,
                  let delta = choice["delta"] as? [String: Any] else { throw AIError.invalidOutput }
            if let refusal = delta["refusal"], !(refusal is NSNull) { throw AIError.invalidOutput }
            if let tools = delta["tool_calls"], !(tools is NSNull) { throw AIError.invalidOutput }
            if let value = delta["content"], !(value is NSNull) {
                guard let part = value as? String, !stopped || part.isEmpty else { throw AIError.invalidOutput }
                byteCount += part.utf8.count
                guard byteCount <= 256 * 1_024 else { throw AIError.invalidOutput }
                text += part
                if !part.isEmpty { events.append(.textDelta(part)) }
            }
            if let reason = choice["finish_reason"], !(reason is NSNull) {
                guard (reason as? String) == "stop", !stopped else { throw AIError.invalidOutput }
                stopped = true
            }
        }
        return events
    }

    func finish() throws -> AIEvent {
        guard stopped, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidOutput }
        return .completed(text)
    }

    static func payloadError(_ root: [String: Any], fallback: AIError) -> AIError {
        let error = root["error"] as? [String: Any] ?? root
        let code = (error["code"] as? String ?? error["type"] as? String ?? "").lowercased()
        switch code {
        case "invalid_api_key", "invalidapikey", "authentication_error": return .invalidCredentials
        case "model_not_found", "modelnotfound", "unsupported_model": return .unsupportedModel
        case "rate_limit_exceeded", "throttling", "rate_limit_error": return .rateLimited
        default: return fallback
        }
    }
}
