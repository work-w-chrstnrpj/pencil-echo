import Foundation
import Observation
import PencilKit

@MainActor
@Observable
final class AgentChatController {
    enum Scope: String { case selection = "Selection", visiblePage = "Visible page" }
    let session: EditorSession
    var input = ""
    var isOtherRequestPending = false
    var scope: Scope = .selection
    private(set) var isPending = false
    private(set) var streamingReply = ""
    private(set) var pendingInstruction = ""
    private(set) var error: String?
    private(set) var pendingRegion: CGRect?
    private let region: () -> CGRect
    private let selection: () -> CGRect?
    private let provider: () -> (any AIProvider, String)
    private let blocked: () -> String?
    private var generation = 0
    private var task: Task<Void, Never>?

    init(session: EditorSession, region: @escaping () -> CGRect, selection: @escaping () -> CGRect?,
         provider: @escaping () -> (any AIProvider, String) = AskAIController.configuredProvider,
         blocked: @escaping () -> String? = AskAIController.configuredBlockedReason) {
        self.session = session; self.region = region; self.selection = selection
        self.provider = provider; self.blocked = blocked
    }
    var effectiveScope: Scope { scope == .selection && selection() != nil ? .selection : .visiblePage }
    var canSend: Bool { !session.isReadOnly && !isPending && !isOtherRequestPending && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func send() {
        guard canSend else { return }
        if let reason = blocked() { error = reason; return }
        let instruction = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard instruction.utf8.count <= DocumentLimits.maxMessageBytes else { error = "Keep the message under 16 KB."; return }
        let captureController = AskAIController(document: session, region: region, selection: selection)
        let selectedRegion = effectiveScope == .selection ? selection() ?? region() : region()
        guard var capture = captureController.makeCapture(documentRegion: selectedRegion) else { error = "Select a visible part of the page first."; return }
        capture.instruction = instruction
        let (provider, model) = provider()
        guard provider.capabilities(model: model)?.vision == true else { error = AIError.modelLacksVision.localizedDescription; return }
        let settings = AISettings.load()
        let history = session.chatHistory.messages.map { AIChatMessage(role: $0.role == .user ? .user : .assistant, text: $0.text) }
        let request = AIRequest(requestId: capture.context.requestId, model: model, systemPrompt: CanvasCommandPrompt.chatSystem,
                                instruction: CanvasCommandPrompt.instruction(instruction, context: capture.context, imageScale: capture.imageScale, focusFrame: capture.focusFrame),
                                pngImages: [capture.png], jsonSchema: AskAIController.bundledSchema,
                                reasoning: settings.settings(for: settings.selectedPresetID).reasoning, history: history)
        generation += 1
        let current = generation
        isPending = true; error = nil; streamingReply = ""; pendingInstruction = instruction; pendingRegion = selectedRegion
        task = Task { [weak self] in
            do {
                var raw = "", completed: String?
                for try await event in provider.send(request) {
                    guard let self, generation == current, !Task.isCancelled else { return }
                    switch event {
                    case .textDelta(let delta):
                        guard raw.utf8.count + delta.utf8.count <= 512 * 1024 else { throw AIError.invalidOutput }
                        raw += delta
                        streamingReply = StreamingChatReply.message(in: raw)
                    case .completed(let final): completed = final
                    case .usage: break
                    }
                }
                guard let self, generation == current, !Task.isCancelled else { return }
                guard let completed else { throw AIError.invalidOutput }
                try receive(completed, capture: capture, captureController: captureController)
                if error == nil { input = "" }
                finish()
            } catch {
                guard let self, generation == current, !Task.isCancelled else { return }
                self.error = AIError.normalized(error).localizedDescription
                finish()
            }
        }
    }

    private func receive(_ text: String, capture: AskAICapture, captureController: AskAIController) throws {
        let raw = Data(CanvasCommandPrompt.stripCodeFence(text).utf8)
        let checked = CommandValidator.validate(raw, context: capture.context, state: captureController.validationState(for: capture))
        guard case .valid(let operations) = checked else {
            if case .needsReview = checked {
                error = "The captured work changed. Nothing was placed. Send again with the current page."
                return
            }
            throw AIError.invalidOutput
        }
        guard !session.isReadOnly,
              var next = AnswerApplier.apply(operations, to: session.snapshot, layout: session.layout, capture: capture, date: Date()) else { throw AIError.invalidOutput }
        DraftMarker.mark(&next, comparedTo: session.snapshot, requestId: capture.context.requestId)
        let root = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        let message = (root?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? operations.compactMap { if case .addObject(_, let source, _, _) = $0 { return source }; return nil }.joined(separator: "\n\n")
        var history = session.chatHistory
        history.append(user: capture.instruction, assistant: message.isEmpty ? "Added editable drafts to the canvas." : message,
                       requestId: capture.context.requestId, at: Date())
        history.draftInk = next.draftInk
        guard next.objects.count <= DocumentLimits.maxObjects, history.isValid,
              try DocumentCoding.encoder().encode(history).count <= AgentChatHistory.maxFileBytes else { throw AIError.invalidOutput }
        session.applyChatAnswer(next, history: history, requestId: capture.context.requestId)
    }

    private func finish() { isPending = false; streamingReply = ""; pendingInstruction = ""; pendingRegion = nil; task = nil }
    func cancel() { generation += 1; task?.cancel(); finish() }
    func newChat() { cancel(); error = nil; session.clearChat() }
}

/// Extract only the envelope's top-level message string, including a partial string.
/// Never display operation JSON or an escaped "message" inside editable object source.
enum StreamingChatReply {
    static func message(in raw: String) -> String {
        let bytes = Array(raw.utf8)
        var depth = 0, start: Int?, escaped = false, messageValue = false, expectingValue = false
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if let begin = start {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 {
                    let token = Data(bytes[begin...index])
                    if messageValue { return (try? JSONDecoder().decode(String.self, from: token)) ?? "" }
                    if depth == 1, let key = try? JSONDecoder().decode(String.self, from: token), key == "message" {
                        var next = index + 1
                        while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                        expectingValue = next < bytes.count && bytes[next] == 58
                    }
                    start = nil
                }
            } else {
                if byte == 34 { start = index; messageValue = expectingValue; expectingValue = false }
                else if byte == 123 || byte == 91 { depth += 1 }
                else if byte == 125 || byte == 93 { depth -= 1 }
                else if byte == 44 { expectingValue = false }
            }
            index += 1
        }
        guard messageValue, let start else { return "" }
        var partial = Array(bytes[start...])
        // A streamed chunk may end inside a UTF-8 scalar, escape or surrogate pair.
        for _ in 0..<14 {
            if let result = try? JSONDecoder().decode(String.self, from: Data(partial + [34])) { return result }
            if partial.count <= 1 { break }
            partial.removeLast()
        }
        return ""
    }
}
