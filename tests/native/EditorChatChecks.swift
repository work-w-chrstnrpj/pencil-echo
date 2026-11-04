// Synthetic native contract/model checks. No networking or real credentials.
import Foundation

struct SyntheticKeys: ProviderCredentials {
    func read(for identity: ProviderIdentity) throws -> String? { "synthetic-only" }
}
struct NativeProviderChecks {
    static func run() throws {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool) {
            if !condition() { FileHandle.standardError.write(Data("Provider contract check failed: \(assertions + 1)\n".utf8)); Darwin.exit(1) }; assertions += 1
        }
        for (id, model) in [("openai", "gpt-5.1"), ("anthropic", "claude-sonnet-4-6"), ("gemini", "gemini-2.5-flash")] {
            for effort in ReasoningLevel.allCases {
                var settings = AISettings()
                settings.providers[id] = ProviderSettings(model: model, visionOverrides: [model: true])
                let preset = try settings.resolvedPreset(for: id)
                let request = AIRequest(model: model, systemPrompt: "JSON", instruction: "Now", reasoning: effort,
                                        history: [.init(role: .user, text: "Previous question"), .init(role: .assistant, text: "Previous answer")])
                let http: URLRequest
                switch id {
                case "anthropic": http = try AnthropicProvider(preset: preset, credentials: SyntheticKeys()).makeRequest(request)
                case "gemini": http = try GeminiProvider(preset: preset, credentials: SyntheticKeys()).makeRequest(request)
                default: http = try OpenAICompatibleProvider(preset: preset, credentials: SyntheticKeys()).makeRequest(request)
                }
                let body = try JSONSerialization.jsonObject(with: http.httpBody!) as! [String: Any]
                let messages = body[id == "gemini" ? "contents" : "messages"] as! [[String: Any]]
                let offset = id == "openai" ? 1 : 0
                check(messages.count == 3 + offset)
                check(messages[offset]["role"] as? String == "user")
                check(messages[offset+1]["role"] as? String == (id == "gemini" ? "model" : "assistant"))
                if id == "openai" { check(body["reasoning_effort"] as? String == (effort == .off ? "none" : effort.rawValue)) }
                if id == "anthropic" {
                    check((body["thinking"] as? [String: Any])?["type"] as? String == (effort == .off ? "disabled" : "enabled"))
                    check(body["max_tokens"] as? Int == 4096 + effort.budget)
                }
                if id == "gemini" {
                    let config = body["generationConfig"] as! [String: Any]
                    check((config["thinkingConfig"] as? [String: Int])?["thinkingBudget"] == effort.budget)
                }
            }
        }
        var history = AgentChatHistory()
        for i in 0..<15 { history.append(user: "Question \(i)", assistant: "Answer \(i)", requestId: UUID(), at: Date(timeIntervalSince1970: 1000)) }
        check(history.isValid && history.messages.count == 20)
        check(history.messages.first?.text == "Question 5")
        let roundtrip = try DocumentCoding.decoder().decode(AgentChatHistory.self, from: DocumentCoding.encoder().encode(history))
        check(roundtrip == history)
        let old = try JSONDecoder().decode(ProviderSettings.self, from: Data(#"{"model":"old","visionOverrides":{}}"#.utf8))
        check(old.reasoning == nil)
        check(!ReasoningLevel.supports(preset: "anthropic", model: "claude-sonnet-5-5"))
        check(!ReasoningLevel.supports(preset: "custom", model: "gpt-5.1"))
        check(StreamingChatReply.message(in: #"{"message":"Working"#) == "Working")
        check(StreamingChatReply.message(in: #"{"operations":[{"source":"fake \"message\": value"}],"message":"Answer\nnext"}"#) == "Answer\nnext")
        check(StreamingChatReply.message(in: #"{"operations":[{"source":"hidden"}]}"#).isEmpty)
        print("Passed \(assertions) native contract assertions against repository provider/model sources.")
    }
}

import Foundation
import PencilKit
import AppKit
import Darwin

// Native compatibility for EditorGeometry; these checks do not exercise lasso UI.
typealias UIBezierPath = NSBezierPath
extension NSBezierPath { func addLine(to point: CGPoint) { line(to: point) } }

// Rendering is outside this native model check; the unchanged iPad renderer is verified by iPad builds/UI tests.
@MainActor enum RichTextRenderer {
    static func height(source: String, type: ObjectType, width: CGFloat, handwritten: Bool) -> CGFloat { 80 }
}
@MainActor enum ThumbnailRenderer {
    static func render(_ document: Document, assetsURL: URL?) -> Data? { nil }
}
extension DocumentObject { var rendersHandwritten: Bool { if case .ai = createdBy { true } else { false } } }

struct NativeSessionChecks {
    @MainActor static func run() async throws {
        var assertions = 0
        func check(_ condition: Bool) { if !condition { FileHandle.standardError.write(Data("Native session check failed: \(assertions + 1)\n".utf8)); Darwin.exit(1) }; assertions += 1 }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NativeChatModel-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentStore(rootURL: root.appendingPathComponent("Documents"), preMigrationURL: root.appendingPathComponent("PreMigration"))
        FileHandle.standardError.write(Data("Creating synthetic package\n".utf8))
        let created = try await store.create(type: .canvas)
        FileHandle.standardError.write(Data("Opening EditorSession\n".utf8))
        let session = EditorSession(loaded: try await store.load(id: created.id), store: store)
        session.manager.groupsByEvent = false
        session.autosaveDelay = .seconds(60)
        let originalRevision = session.revision
        check(session.chatHistory.messages.isEmpty && session.makeDocument().chat == nil)
        check(session.rename(to: "  Native title  "))
        check(!session.rename(to: " "))
        session.setGridVisible(false); session.setChatPanelOpen(true)
        check(session.revision == originalRevision && session.hasUnsavedChanges)
        FileHandle.standardError.write(Data("Saving session state\n".utf8))
        check(await session.saveNow())
        check(!session.hasUnsavedChanges)
        var next = session.snapshot
        let id = UUID(), requestId = UUID(), date = Date(timeIntervalSince1970: 1000)
        next.objects.append(DocumentObject(id: id, pageId: session.pages[0].id, type: .text, frame: PageRect(x: 200, y: 200, width: 120, height: 60), zIndex: 1, source: "Answer", assetRefs: [], createdBy: .ai(requestId: requestId), createdAt: date, updatedAt: date, aiAppearance: AIAnswerAppearance(ink: .purple, font: .rounded), isDraft: true))
        func stroke(_ marker: Double) -> PKStroke {
            let points = [CGPoint(x: 20, y: 20), CGPoint(x: 120, y: 100)].enumerated().map { i, p in PKStrokePoint(location: p, timeOffset: Double(i), size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2) }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: marker)))
        }
        next.drawing = PKDrawing(strokes: [stroke(0), stroke(-1)])
        next.draftInk = [DraftInkBatch(requestId: requestId, strokeDate: Date(timeIntervalSince1970: -1))]
        var history = AgentChatHistory()
        history.append(user: "Question", assistant: "Answer", requestId: requestId, at: date)
        session.applyChatAnswer(next, history: history, requestId: requestId)
        check(session.hasDrafts && session.objects.count == 1 && session.drawing.strokes.count == 2)
        FileHandle.standardError.write(Data("Saving session state\n".utf8))
        check(await session.saveNow())
        let loaded = try await store.load(id: created.id)
        let reopened = EditorSession(loaded: loaded, store: store)
        reopened.manager.groupsByEvent = false
        check(reopened.manifest.title == "Native title" && reopened.manifest.gridVisible == false && reopened.manifest.chatPanelOpen == true)
        check(reopened.objects[0].aiAppearance == AIAnswerAppearance(ink: .purple, font: .rounded))
        check(reopened.drawing.strokes[1].path.creationDate == reopened.draftInk[0].strokeDate)
        check(reopened.chatHistory.messages.count == 2)
        reopened.discardAllDrafts()
        check(!reopened.hasDrafts && reopened.objects.isEmpty && reopened.drawing.strokes.count == 1)
        reopened.manager.undo()
        check(reopened.hasDrafts && reopened.objects.count == 1 && reopened.drawing.strokes.count == 2)
        reopened.acceptAllDrafts()
        check(!reopened.hasDrafts && reopened.objects.count == 1 && reopened.drawing.strokes.count == 2)
        reopened.manager.undo()
        check(reopened.hasDrafts)
        reopened.clearChat()
        check(reopened.chatHistory.messages.isEmpty && reopened.hasDrafts)
        check(await reopened.saveNow())
        let cleared = try await store.load(id: created.id).document
        check(cleared.chat?.messages.isEmpty == true && cleared.chat?.draftInk.count == 1)
        print("Passed \(assertions) native PencilKit/session persistence and undo assertions; rendering stubbed.")
    }
}

@main struct EditorChatChecks {
    @MainActor static func main() async throws {
        FileHandle.standardError.write(Data("Starting native provider/model checks\n".utf8))
        try NativeProviderChecks.run()
        FileHandle.standardError.write(Data("Provider checks passed; starting PencilKit/session checks\n".utf8))
        try await NativeSessionChecks.run()
    }
}
