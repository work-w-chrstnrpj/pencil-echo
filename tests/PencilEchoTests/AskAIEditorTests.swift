import Foundation
import PencilKit
import Testing
@testable import PencilEcho

// Ticket 010 acceptance against the real EditorSession and DocumentStore: one undo
// removes the whole answer, redo restores it, and save/reopen keeps a retained answer
// without resurrecting an undone one. The provider is a fake; no network.
@MainActor
final class AskAIEditorTests {
    let base: URL
    let store: DocumentStore

    init() {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("AskAIEditorTests-\(UUID().uuidString)")
        store = DocumentStore(rootURL: base.appendingPathComponent("Documents", isDirectory: true),
                              preMigrationURL: base.appendingPathComponent("PreMigration", isDirectory: true), appVersion: "test")
    }

    deinit { try? FileManager.default.removeItem(at: base) }

    static let twoObjects = #"{"version":1,"operations":[{"op":"latex","type":"latex","source":"x = 4","placement":"right_of_scope","frame":null}],"message":null}"#
        .replacingOccurrences(of: #""op":"latex""#, with: #""op":"add_object""#)
        .replacingOccurrences(of: #"],"message""#, with: #",{"op":"add_object","type":"markdown","source":"Subtract 3, then divide by 2.","placement":"right_of_scope","frame":null}],"message""#)

    func nextEvent() async throws { try await Task.sleep(for: .milliseconds(20)) }

    func settle(_ controller: AskAIController) async throws {
        for _ in 0..<300 where controller.isPending { try await Task.sleep(for: .milliseconds(10)) }
    }

    /// A notebook with a handwritten problem on page 1, open in a session.
    func openNotebook() async throws -> EditorSession {
        let created = try await store.create(type: .notebook)
        let session = EditorSession(loaded: try await store.load(id: created.id), store: store)
        session.autosaveDelay = .seconds(60)
        let origin = session.layout.pageRect(0).origin
        let stroke = AskAITests.stroke([CGPoint(x: origin.x + 60, y: origin.y + 80), CGPoint(x: origin.x + 260, y: origin.y + 110)])
        var next = session.snapshot
        next.drawing.strokes.append(stroke)
        session.commit(next, named: "Stroke")
        try await nextEvent()
        return session
    }

    func ask(_ session: EditorSession, answer: String = twoObjects) async throws -> AskAIController {
        let origin = session.layout.pageRect(0).origin
        let region = CGRect(x: origin.x + 36, y: origin.y + 56, width: 248, height: 80)
        let controller = AskAIController(document: session, region: { region },
                                         provider: { (FakeProvider(result: .success(answer)), "fake-vision") },
                                         blocked: { nil }, schema: Data("{}".utf8))
        controller.ask()
        try await settle(controller)
        try await nextEvent()
        return controller
    }

    @Test func oneUndoRemovesTheWholeAnswerAndRedoRestoresIt() async throws {
        let session = try await openNotebook()
        let revisionBefore = session.revision
        let controller = try await ask(session)
        #expect(controller.phase == .idle)
        #expect(session.objects.count == 2 && session.objects.allSatisfy {
            if case .ai = $0.createdBy { true } else { false }
        })
        #expect(session.revision == revisionBefore + 1)
        #expect(session.manager.undoActionName == "AI Answer")

        session.manager.undo()
        try await nextEvent()
        #expect(session.objects.isEmpty && session.drawing.strokes.count == 1)
        // The applied request is remembered even though the answer was undone.
        #expect(session.conversation.appliedRequests.count == 1)

        session.manager.redo()
        try await nextEvent()
        #expect(session.objects.count == 2)
    }

    @Test func aDrawingAndItsLabelsAreOneUndoStep() async throws {
        let answer = #"{"version":3,"operations":[{"op":"draw_ink","width":120,"height":80,"strokes":[{"kind":"line","points":[[10,40],[110,40]],"closed":false,"color":"black","size":3,"arrow":"end"}],"labels":[{"kind":"latex","text":"\\gamma","x":50,"y":24}],"placement":"right_of_scope","frame":null}],"message":"Labeled."}"#
        let session = try await openNotebook()
        let before = session.drawing.strokes.count
        _ = try await ask(session, answer: answer)
        #expect(session.objects.count == 1 && session.objects[0].type == .latex && session.objects[0].source == #"\gamma"#)
        #expect(session.drawing.strokes.count > before)
        #expect(session.manager.undoActionName == "AI Answer")
        session.manager.undo()
        try await nextEvent()
        #expect(session.objects.isEmpty && session.drawing.strokes.count == before)
    }

    @Test func savedAnswerReopensAndUndoneAnswerStaysGone() async throws {
        let session = try await openNotebook()
        _ = try await ask(session)
        #expect(await session.saveNow())
        let reopened = try await store.load(id: session.documentId).document
        #expect(reopened.objects.count == 2)
        #expect(reopened.conversation?.appliedRequests.count == 1)
        #expect(reopened.conversation?.messages.first?.text == CanvasCommandPrompt.defaultInstruction)

        session.manager.undo()
        try await nextEvent()
        #expect(await session.saveNow())
        let afterUndo = try await store.load(id: session.documentId).document
        #expect(afterUndo.objects.isEmpty)
        #expect(afterUndo.conversation?.appliedRequests.count == 1)
    }

    @Test func answersNeverOverlapTheProblemInk() async throws {
        let session = try await openNotebook()
        _ = try await ask(session)
        let page = session.layout.pageRect(0)
        let ink = session.drawing.strokes[0].renderBounds.offsetBy(dx: -page.minX, dy: -page.minY)
        for object in session.objects {
            let frame = AskAIController.rect(object.frame)
            #expect(!frame.intersects(ink))
            #expect(frame.maxX <= page.width && frame.maxY <= page.height)
        }
    }

    @Test func readOnlySessionIgnoresAnswers() async throws {
        let created = try await store.create(type: .canvas)
        let session = EditorSession(loaded: try await store.load(id: created.id), store: store, readOnlyReason: "Open elsewhere")
        let controller = try await ask(session)
        #expect(!controller.canAsk && session.objects.isEmpty)
    }
}
