import Foundation
import PencilKit
import Testing
@testable import PencilEcho

private final class ChatRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AIRequest] = []
    func append(_ value: AIRequest) { lock.withLock { values.append(value) } }
    var requests: [AIRequest] { lock.withLock { values } }
}
private struct ChatFixture: AIProvider {
    let recorder: ChatRequestRecorder
    var delay: Duration = .zero
    var reply = #"{"version":2,"message":"Use conservation of energy.","operations":[{"op":"add_object","type":"text","source":"v = sqrt(2gh)","placement":"right_of_scope","frame":null},{"op":"draw_ink","width":100,"height":100,"strokes":[{"kind":"line","points":[[0,0],[100,100]],"closed":false,"color":"blue","size":3}],"placement":"below_scope","frame":null}]}"#
    func capabilities(model: String) -> ModelCapabilities? { ProviderCatalog.unverifiedCapabilities(vision: true) }
    func send(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        recorder.append(request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                // Deliberately ignores cancellation to exercise the controller generation gate.
                try? await Task.sleep(for: delay)
                continuation.yield(.textDelta(reply))
                continuation.yield(.completed(reply)); continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
struct AgentChatTests {
    let store: DocumentStore
    init() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ChatTests-" + UUID().uuidString)
        store = DocumentStore(rootURL: base.appendingPathComponent("Documents"), preMigrationURL: base.appendingPathComponent("PreMigration"))
    }
    func open() async throws -> EditorSession {
        let doc = try await store.create(type: .canvas)
        return EditorSession(loaded: try await store.load(id: doc.id), store: store)
    }
    private func controller(_ session: EditorSession, fixture: ChatFixture, selection: CGRect? = nil) -> AgentChatController {
        AgentChatController(session: session, region: { CGRect(x: 0, y: 0, width: 600, height: 500) }, selection: { selection }, provider: { (fixture, "fixture-vision") }, blocked: { nil })
    }
    func settle(_ chat: AgentChatController) async throws {
        for _ in 0..<400 where chat.isPending { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!chat.isPending)
        try await Task.sleep(for: .milliseconds(20))
    }

    @Test func selectionFollowUpAndDraftTransactionsSurviveReopen() async throws {
        let session = try await open(), recorder = ChatRequestRecorder()
        let chat = controller(session, fixture: ChatFixture(recorder: recorder), selection: CGRect(x: 76, y: 76, width: 200, height: 100))
        #expect(chat.effectiveScope == .selection)
        chat.input = "Solve the time of descent"
        chat.send(); try await settle(chat)
        #expect(chat.error == nil)
        #expect(session.objects.count == 1 && session.objects[0].isDraft == true)
        #expect(session.draftInk.count == 1 && session.drawing.strokes.count == 1)
        #expect(session.chatHistory.messages.count == 2)
        let first = try #require(recorder.requests.first)
        #expect(first.history.isEmpty && first.pngImages.count == 1)
        #expect(first.instruction.contains("76"))
        session.setChatPanelOpen(true)
        #expect(await session.saveNow())
        let reopened = EditorSession(loaded: try await store.load(id: session.documentId), store: store)
        // Saved dates keep milliseconds (ISO 8601), so compare createdAt to within 1 ms.
        let saved = session.chatHistory.messages, loaded = reopened.chatHistory.messages
        #expect(loaded.map(\.id) == saved.map(\.id) && loaded.map(\.role) == saved.map(\.role))
        #expect(loaded.map(\.text) == saved.map(\.text) && loaded.map(\.requestId) == saved.map(\.requestId))
        #expect(zip(loaded, saved).allSatisfy { abs($0.createdAt.timeIntervalSince($1.createdAt)) < 0.001 })
        #expect(reopened.manifest.chatPanelOpen == true && reopened.hasDrafts)
        #expect(reopened.drawing.strokes[0].path.creationDate == reopened.draftInk[0].strokeDate)

        reopened.acceptAllDrafts(); try await Task.sleep(for: .milliseconds(20))
        #expect(!reopened.hasDrafts && reopened.objects.count == 1 && reopened.drawing.strokes.count == 1)
        reopened.manager.undo(); try await Task.sleep(for: .milliseconds(20))
        #expect(reopened.hasDrafts)
        reopened.discardAllDrafts(); try await Task.sleep(for: .milliseconds(20))
        #expect(reopened.objects.isEmpty && reopened.drawing.strokes.isEmpty && !reopened.hasDrafts)
        reopened.manager.undo(); try await Task.sleep(for: .milliseconds(20))
        #expect(reopened.hasDrafts && reopened.objects.count == 1 && reopened.drawing.strokes.count == 1)

        chat.scope = .visiblePage
        #expect(chat.effectiveScope == .visiblePage)
        chat.input = "Why is the curved path faster?"; chat.send(); try await settle(chat)
        let followup = try #require(recorder.requests.last)
        #expect(followup.history.map(\.role) == [.user, .assistant])
        #expect(followup.history[1].text == "Use conservation of energy.")
        #expect(followup.pngImages.count == 1)
        chat.newChat()
        #expect(session.chatHistory.messages.isEmpty && session.hasDrafts)
        #expect(await session.saveNow())
        #expect(try await store.load(id: session.documentId).document.chat?.messages.isEmpty == true)
    }

    @Test func cancelAndStaleCapturePlaceNothing() async throws {
        let session = try await open(), recorder = ChatRequestRecorder()
        let chat = controller(session, fixture: ChatFixture(recorder: recorder, delay: .milliseconds(100)))
        #expect(chat.effectiveScope == .visiblePage)
        chat.input = "Solve"; chat.send(); chat.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(session.objects.isEmpty && session.chatHistory.messages.isEmpty && !session.hasDrafts)
        #expect(chat.input == "Solve")
        chat.send()
        var next = session.snapshot
        next.drawing.strokes.append(AskAITests.stroke([CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 150)]))
        session.commit(next, named: "Changed problem")
        try await settle(chat)
        #expect(session.objects.isEmpty && session.chatHistory.messages.isEmpty && session.drawing.strokes.count == 1)
        #expect(chat.error?.contains("changed") == true && chat.input == "Solve")
    }

    @Test func acceptedInkIsNeverDiscardedWithANewerDraftBatch() async throws {
        let session = try await open(), recorder = ChatRequestRecorder()
        let chat = controller(session, fixture: ChatFixture(recorder: recorder))
        chat.input = "First"; chat.send(); try await settle(chat)
        session.acceptAllDrafts(); try await Task.sleep(for: .milliseconds(20))
        chat.input = "Second"; chat.send(); try await settle(chat)
        #expect(session.drawing.strokes.count == 2)
        session.discardAllDrafts()
        #expect(session.drawing.strokes.count == 1 && session.objects.count == 1)
    }

    @Test func historyTrimsCompleteTurnsAndLegacyPackagesNeedNoMigration() async throws {
        var history = AgentChatHistory()
        for index in 0..<14 { history.append(user: "Question \(index)", assistant: "Answer \(index)", requestId: UUID(), at: Date()) }
        #expect(history.isValid && history.messages.count == 20)
        #expect(history.messages.first?.text == "Question 4")
        let session = try await open()
        #expect(session.chatHistory.messages.isEmpty && session.makeDocument().chat == nil)
        let package = await store.packageURL(for: session.documentId)
        try Data("{broken".utf8).write(to: package.appendingPathComponent("chat.json"))
        let loaded = try await store.load(id: session.documentId)
        #expect(loaded.document.chat == nil && loaded.issues.contains(.optionalFileUnreadable("chat.json")))
    }

    @Test func streamExtractionDoesNotLeakOperationsAndHandlesEscapes() {
        #expect(StreamingChatReply.message(in: #"{"version":2,"message":"Working"#) == "Working")
        #expect(StreamingChatReply.message(in: #"{"operations":[{"source":"fake \"message\": value"}],"message":"Answer\nnext"}"#) == "Answer\nnext")
        #expect(StreamingChatReply.message(in: #"{"operations":[{"source":"private content"}]}"#).isEmpty)
    }
}

struct AgentChatAdapterTests {
    @Test(arguments: ["openai", "anthropic", "gemini"]) func historyUsesNativeRolesAndOnlyCurrentImages(_ id: String) throws {
        let model = "fixture-vision"
        var settings = AISettings()
        settings.providers[id] = ProviderSettings(model: model, visionOverrides: [model: true])
        let preset = try settings.resolvedPreset(for: id), keys = MemoryCredentials()
        keys.save("synthetic", for: try ProviderIdentity(presetID: id, baseURL: preset.baseURL))
        let request = AIRequest(model: model, systemPrompt: "JSON", instruction: "Follow up", pngImages: [ProviderSettingsTests.tinyPNG], history: [.init(role: .user, text: "Question"), .init(role: .assistant, text: "Answer")])
        let http: URLRequest
        switch id {
        case "anthropic": http = try AnthropicProvider(preset: preset, credentials: keys).makeRequest(request)
        case "gemini": http = try GeminiProvider(preset: preset, credentials: keys).makeRequest(request)
        default: http = try OpenAICompatibleProvider(preset: preset, credentials: keys).makeRequest(request)
        }
        let payload = try #require(http.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let messages = try #require(body[id == "gemini" ? "contents" : "messages"] as? [[String: Any]])
        let offset = id == "openai" ? 1 : 0
        #expect(messages.count == 3 + offset)
        #expect(messages[offset]["role"] as? String == "user")
        #expect(messages[offset + 1]["role"] as? String == (id == "gemini" ? "model" : "assistant"))
        #expect(!String(decoding: try JSONSerialization.data(withJSONObject: Array(messages.dropLast())), as: UTF8.self).contains("base64"))
        #expect(String(decoding: payload, as: UTF8.self).contains("Question"))
        var oversized = request
        oversized.history = Array(repeating: request.history, count: 11).flatMap { $0 }
        #expect(throws: AIError.invalidRequest) { try AIChatMessage.validate(oversized.history) }
    }
}
