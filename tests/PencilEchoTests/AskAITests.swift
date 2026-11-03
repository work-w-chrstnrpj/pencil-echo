import Foundation
import PencilKit
import Testing
import UIKit
@testable import PencilEcho

// Ticket 010: prompt, placement, stale detection, conversation and the Ask AI
// lifecycle, with a fake provider and a fake document (no network, no editor UI).

struct FakeProvider: AIProvider {
    var result: Result<String, AIError>
    var vision = true
    var delay: Duration = .zero

    func capabilities(model: String) -> ModelCapabilities? {
        ModelCapabilities(vision: vision, streaming: true, structuredOutput: .jsonObject, maxImageBytes: 5_000_000)
    }

    func send(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                if delay != .zero { try? await Task.sleep(for: delay) }
                switch result {
                case .success(let text): continuation.yield(.completed(text)); continuation.finish()
                case .failure(let error): continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@MainActor
final class FakeAskDocument: AskAIDocument {
    let documentId = UUID()
    var isReadOnly = false
    var revision = 1
    let type: DocumentType
    var snapshot: EditorSnapshot
    var conversation = Conversation()
    private(set) var applyCount = 0
    private(set) var lastActionName: String?

    init(type: DocumentType, pages: [Page], strokes: [PKStroke] = [], objects: [DocumentObject] = []) {
        self.type = type
        snapshot = EditorSnapshot(pages: pages, drawing: PKDrawing(strokes: strokes), objects: objects)
    }

    var layout: EditorLayout { EditorLayout(type: type, pages: snapshot.pages) }

    func applyAIAnswer(_ next: EditorSnapshot, conversation: Conversation, named name: String) {
        snapshot = next
        self.conversation = conversation
        applyCount += 1
        revision += 1
        lastActionName = name
    }

    /// A content edit while a request is pending.
    func edit(_ change: (inout EditorSnapshot) -> Void) {
        change(&snapshot)
        revision += 1
    }
}

@MainActor
struct AskAITests {
    static func stroke(_ points: [CGPoint]) -> PKStroke {
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) / 60, size: CGSize(width: 4, height: 4),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
                        path: PKStrokePath(controlPoints: controls, creationDate: Date(timeIntervalSince1970: 0)))
    }

    static let answer = #"{"version":1,"operations":[{"op":"add_object","type":"markdown","source":"**x = 4**","placement":"right_of_scope","frame":null}],"message":"Solved for x."}"#

    let canvasPage = Page(id: UUID(), size: PageSize(width: 2_000, height: 2_000), background: .blank)
    /// "2x + 3 = 11" as one stroke from (100,100) to (300,140).
    var equation: PKStroke { Self.stroke([CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 140), CGPoint(x: 300, y: 120)]) }
    let region = CGRect(x: 76, y: 76, width: 248, height: 88)

    func canvasDocument() -> FakeAskDocument {
        FakeAskDocument(type: .canvas, pages: [canvasPage], strokes: [equation])
    }

    func controller(_ document: FakeAskDocument, _ provider: FakeProvider, region: CGRect? = nil) -> AskAIController {
        let region = region ?? self.region
        return AskAIController(document: document, region: { region }, provider: { (provider, "fake-vision") },
                               blocked: { nil }, schema: Data("{}".utf8), now: { Date(timeIntervalSince1970: 1_000) })
    }

    func settle(_ controller: AskAIController) async throws {
        for _ in 0..<300 where controller.isPending { try await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: Prompt

    @Test func instructionCarriesGeometryAndDefault() {
        let context = CommandRequestContext(requestId: UUID(), documentId: UUID(), pageId: UUID(), capturedRevision: 3,
                                            scopeFrame: CommandFrame(x: 10, y: 20, width: 100, height: 50), scopeObjectIds: [],
                                            pageBounds: CommandFrame(x: 0, y: 0, width: 595, height: 842), allowReplace: false)
        let text = CanvasCommandPrompt.instruction("  ", context: context, imageScale: 2)
        #expect(text.hasPrefix("Instruction: Answer the newest handwriting\nRequest: {"))
        #expect(text.contains(#""captureFrame":{"height":50,"width":100,"x":10,"y":20}"#))
        #expect(text.contains(#""allowReplace":false"#) && text.contains(#""imageScale":2"#))
        #expect(CanvasCommandPrompt.system.contains("3+2=") && CanvasCommandPrompt.system.contains("allowReplace"))
    }

    @Test func codeFenceStripping() {
        #expect(CanvasCommandPrompt.stripCodeFence("```json\n{\"a\":1}\n```") == "{\"a\":1}")
        #expect(CanvasCommandPrompt.stripCodeFence("```\n{}\n```") == "{}")
        #expect(CanvasCommandPrompt.stripCodeFence("  {\"a\":1} ") == "{\"a\":1}")
        // Prose around JSON is not recovered; the validator rejects it.
        #expect(CanvasCommandPrompt.stripCodeFence("Here: {}") == "Here: {}")
    }

    // MARK: Placement

    @Test func placesRightThenBelowThenGivesUp() {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let scope = CGRect(x: 40, y: 40, width: 200, height: 80)
        let size = CGSize(width: 240, height: 60)
        let right = AnswerPlacement.freeRect(size: size, scope: scope, page: page, occupied: [scope])
        #expect(right == CGRect(x: 256, y: 40, width: 240, height: 60))

        let blockedRight = [scope, CGRect(x: 300, y: 0, width: 295, height: 842)]
        let below = AnswerPlacement.freeRect(size: size, scope: scope, page: page, occupied: blockedRight)
        #expect(below.map { $0.minX == 40 && $0.minY >= scope.maxY + AnswerPlacement.gap } == true)
        #expect(below.map { !blockedRight.contains(where: $0.intersects) } == true)

        #expect(AnswerPlacement.freeRect(size: size, scope: scope, page: page, occupied: [page]) == nil)
        #expect(AnswerPlacement.freeRect(size: CGSize(width: 700, height: 60), scope: scope, page: page, occupied: []) == nil)
    }

    @Test func stackingAndSizes() {
        let sizes = [CGSize(width: 240, height: 44), CGSize(width: 300, height: 80)]
        #expect(AnswerPlacement.blockSize(sizes) == CGSize(width: 300, height: 44 + 80 + AnswerPlacement.gap))
        let frames = AnswerPlacement.stack(sizes, in: CGRect(x: 10, y: 10, width: 300, height: 140))
        #expect(Double(frames[1].minY) == Double(frames[0].maxY) + AnswerPlacement.gap)
        let short = AnswerPlacement.size(type: .text, source: "4", scope: .zero, pageWidth: 595)
        let long = AnswerPlacement.size(type: .markdown, source: String(repeating: "word ", count: 120), scope: .zero, pageWidth: 595)
        #expect(Double(short.width) == AnswerPlacement.minWidth && long.height > short.height)
        #expect(Double(AnswerPlacement.size(type: .latex, source: "x", scope: CGRect(x: 0, y: 0, width: 900, height: 10),
                                            pageWidth: 2_000).width) == AnswerPlacement.maxWidth)
    }

    // MARK: Stale detection

    @Test func fingerprintIgnoresChangesOutsideScope() {
        let scope = CGRect(x: 76, y: 76, width: 248, height: 88)
        let base = ScopeFingerprint.make(strokes: [equation], objects: [], pageId: canvasPage.id, scope: scope, pageOrigin: .zero)
        let far = Self.stroke([CGPoint(x: 1_500, y: 1_500), CGPoint(x: 1_600, y: 1_600)])
        #expect(ScopeFingerprint.make(strokes: [equation, far], objects: [], pageId: canvasPage.id, scope: scope, pageOrigin: .zero) == base)
        let near = Self.stroke([CGPoint(x: 120, y: 150), CGPoint(x: 160, y: 150)])
        #expect(ScopeFingerprint.make(strokes: [equation, near], objects: [], pageId: canvasPage.id, scope: scope, pageOrigin: .zero) != base)
    }

    // MARK: Conversation

    @Test func conversationRecordsOnceAndKeepsLimits() {
        let id = UUID(), date = Date(timeIntervalSince1970: 5)
        var conversation = Conversation().recordingAnswer(requestId: id, instruction: "Solve", message: "Done", at: date)
        conversation = conversation.recordingAnswer(requestId: id, instruction: "Solve", message: nil, at: date)
        #expect(conversation.appliedRequests.map(\.requestId) == [id])
        #expect(conversation.messages.map(\.role) == [.user, .assistant, .user])
        let long = Conversation().recordingAnswer(requestId: UUID(), instruction: String(repeating: "é", count: 20_000),
                                                  message: nil, at: date)
        #expect(long.messages[0].text.utf8.count <= DocumentLimits.maxMessageBytes)
    }

    // MARK: Lifecycle

    @Test func validAnswerIsPlacedBesideTheProblemAsOneStep() async throws {
        let document = canvasDocument()
        let ask = controller(document, FakeProvider(result: .success("```json\n\(Self.answer)\n```")))
        ask.ask()
        try await settle(ask)

        #expect(ask.phase == .idle && document.applyCount == 1 && document.lastActionName == "AI Answer")
        let added = try #require(document.snapshot.objects.first)
        guard case .ai(let requestId) = added.createdBy else { Issue.record("not tagged as AI"); return }
        #expect(added.type == .markdown && added.source == "**x = 4**")
        let frame = AskAIController.rect(added.frame)
        #expect(!frame.intersects(equation.renderBounds) && frame.minX > equation.renderBounds.maxX)
        #expect(document.conversation.appliedRequests.map(\.requestId) == [requestId])
        #expect(document.conversation.messages.map(\.text) == [CanvasCommandPrompt.defaultInstruction, "Solved for x."])
    }

    @Test func editingTheProblemWhilePendingNeedsReview() async throws {
        let document = canvasDocument()
        let ask = controller(document, FakeProvider(result: .success(Self.answer), delay: .milliseconds(150)))
        ask.ask()
        document.edit { $0.drawing.strokes.append(Self.stroke([CGPoint(x: 120, y: 150), CGPoint(x: 180, y: 150)])) }
        try await settle(ask)
        guard case .review = ask.phase else { Issue.record("expected review, got \(ask.phase)"); return }
        #expect(document.applyCount == 0)

        ask.placeAnyway()
        #expect(ask.phase == .idle && document.applyCount == 1)
    }

    @Test func discardingAReviewChangesNothing() async throws {
        let document = canvasDocument()
        let ask = controller(document, FakeProvider(result: .success(Self.answer), delay: .milliseconds(100)))
        ask.ask()
        document.edit { $0.drawing.strokes.append(Self.stroke([CGPoint(x: 120, y: 150), CGPoint(x: 180, y: 150)])) }
        try await settle(ask)
        ask.dismiss()
        #expect(ask.phase == .idle && document.applyCount == 0 && document.conversation.appliedRequests.isEmpty)
    }

    @Test func editingElsewhereDoesNotNeedReview() async throws {
        let document = canvasDocument()
        let ask = controller(document, FakeProvider(result: .success(Self.answer), delay: .milliseconds(100)))
        ask.ask()
        document.edit { $0.drawing.strokes.append(Self.stroke([CGPoint(x: 1_500, y: 1_500), CGPoint(x: 1_600, y: 1_600)])) }
        try await settle(ask)
        #expect(ask.phase == .idle && document.applyCount == 1)
    }

    @Test func cancelDiscardsTheLateResponse() async throws {
        let document = canvasDocument()
        let ask = controller(document, FakeProvider(result: .success(Self.answer), delay: .milliseconds(100)))
        ask.ask()
        #expect(ask.isPending)
        ask.cancel()
        try await Task.sleep(for: .milliseconds(250))
        #expect(ask.phase == .idle && document.applyCount == 0)
    }

    @Test func networkErrorKeepsTheRequestForManualRetry() async throws {
        let document = canvasDocument()
        var provider = FakeProvider(result: .failure(.network))
        let ask = AskAIController(document: document, region: { region }, provider: { (provider, "fake-vision") },
                                  blocked: { nil }, schema: Data("{}".utf8))
        ask.ask()
        try await settle(ask)
        guard case .failed(let capture, let message) = ask.phase else { Issue.record("expected failure"); return }
        #expect(message == AIError.network.localizedDescription && document.applyCount == 0)
        #expect(document.snapshot.drawing.strokes.count == 1)

        provider = FakeProvider(result: .success(Self.answer))
        ask.retry()
        try await settle(ask)
        #expect(document.applyCount == 1)
        #expect(document.conversation.appliedRequests.map(\.requestId) == [capture.context.requestId])
    }

    @Test func invalidOutputChangesNothing() async throws {
        let document = canvasDocument()
        let before = document.snapshot
        let ask = controller(document, FakeProvider(result: .success(#"{"version":1,"operations":[{"op":"draw"}],"message":null}"#)))
        ask.ask()
        try await settle(ask)
        guard case .failed = ask.phase else { Issue.record("expected failure"); return }
        #expect(document.snapshot == before && document.applyCount == 0)
    }

    @Test func duplicateResponseIsIgnored() throws {
        let document = canvasDocument()
        let ask = controller(document, FakeProvider(result: .success(Self.answer)))
        let capture = try #require(ask.makeCapture(documentRegion: region))
        ask.receive(Self.answer, capture: capture)
        ask.receive(Self.answer, capture: capture)
        #expect(document.applyCount == 1 && document.snapshot.objects.count == 1)
    }

    @Test func modelWithoutVisionIsRefusedBeforeSending() async throws {
        let document = canvasDocument()
        let ask = controller(document, FakeProvider(result: .success(Self.answer), vision: false))
        ask.ask()
        guard case .failed(_, let message) = ask.phase else { Issue.record("expected failure"); return }
        #expect(message == AIError.modelLacksVision.localizedDescription && document.applyCount == 0)
    }

    @Test func readOnlyDocumentCannotAsk() {
        let document = canvasDocument()
        document.isReadOnly = true
        let ask = controller(document, FakeProvider(result: .success(Self.answer)))
        ask.ask()
        #expect(!ask.canAsk && ask.phase == .idle)
    }

    // MARK: Placement in documents

    @Test func fullNotebookPageOverflowsToANewPage() async throws {
        let page = Page(id: UUID(), size: DocumentSchema.a4, background: PageBackground(style: .lined, spacing: 24))
        let layout = EditorLayout(type: .notebook, pages: [page])
        let origin = layout.pageRect(0).origin
        // Ink covering the whole page except the problem's own area.
        let blocker = DocumentObject(id: UUID(), pageId: page.id, type: .text, frame: PageRect(x: 0, y: 0, width: 595, height: 842),
                                     zIndex: 0, source: "", assetRefs: [], createdBy: .user, createdAt: .now, updatedAt: .now)
        let document = FakeAskDocument(type: .notebook, pages: [page],
                                       strokes: [Self.stroke([CGPoint(x: origin.x + 100, y: origin.y + 100),
                                                              CGPoint(x: origin.x + 300, y: origin.y + 130)])],
                                       objects: [blocker])
        let ask = controller(document, FakeProvider(result: .success(Self.answer)),
                             region: CGRect(x: origin.x + 76, y: origin.y + 76, width: 248, height: 80))
        ask.ask()
        try await settle(ask)
        #expect(document.applyCount == 1 && document.snapshot.pages.count == 2)
        let added = try #require(document.snapshot.objects.last)
        #expect(added.pageId == document.snapshot.pages[1].id && added.frame.y == AnswerApplier.newPageMargin)
        #expect(document.snapshot.pages[1].background == page.background)
    }

    @Test func fullCanvasGrows() async throws {
        let page = Page(id: UUID(), size: PageSize(width: 600, height: 400), background: .blank)
        let filler = DocumentObject(id: UUID(), pageId: page.id, type: .text, frame: PageRect(x: 0, y: 0, width: 600, height: 400),
                                    zIndex: 0, source: "", assetRefs: [], createdBy: .user, createdAt: .now, updatedAt: .now)
        let document = FakeAskDocument(type: .canvas, pages: [page], objects: [filler])
        let ask = controller(document, FakeProvider(result: .success(Self.answer)), region: CGRect(x: 50, y: 50, width: 200, height: 100))
        ask.ask()
        try await settle(ask)
        let added = try #require(document.snapshot.objects.last)
        #expect(document.snapshot.pages[0].size.height > 400 && added.frame.y >= 400)
        #expect(added.frame.y + added.frame.height <= document.snapshot.pages[0].size.height)
    }

    @Test func atFrameIsKeptWhenFreeAndFallsBackWhenOnInk() async throws {
        let free = #"{"version":1,"operations":[{"op":"add_object","type":"latex","source":"5","placement":"at_frame","frame":{"x":320,"y":100,"width":40,"height":40}}],"message":null}"#
        let document = canvasDocument()
        let ask = controller(document, FakeProvider(result: .success(free)))
        ask.ask()
        try await settle(ask)
        // Ticket 011 preserves the requested origin/width, measuring rich content height.
        let nativeHeight = RichTextRenderer.height(source: "5", type: .latex, width: 40, handwritten: true)
        #expect(document.snapshot.objects.last?.frame == PageRect(x: 320, y: 100, width: 40, height: nativeHeight))

        let onInk = free.replacingOccurrences(of: #""x":320"#, with: #""x":150"#)
        let second = canvasDocument()
        let ask2 = controller(second, FakeProvider(result: .success(onInk)))
        ask2.ask()
        try await settle(ask2)
        let placed = try #require(second.snapshot.objects.last)
        #expect(!AskAIController.rect(placed.frame).intersects(equation.renderBounds))
    }

    @Test func measuredFormulaHeightParticipatesInCollisionChecks() async throws {
        let document = canvasDocument()
        let obstacle = DocumentObject(id: UUID(), pageId: canvasPage.id, type: .text,
                                      frame: PageRect(x: 320, y: 120, width: 100, height: 100), zIndex: 0,
                                      source: "Existing work", assetRefs: [], createdBy: .user, createdAt: .now, updatedAt: .now)
        document.snapshot.objects.append(obstacle)
        let response = #"{"version":1,"operations":[{"op":"add_object","type":"latex","source":"\\frac{a}{b}","placement":"at_frame","frame":{"x":320,"y":100,"width":100,"height":8}}],"message":null}"#
        let ask = controller(document, FakeProvider(result: .success(response)))
        ask.ask()
        try await settle(ask)
        let added = try #require(document.snapshot.objects.last)
        #expect(added.id != obstacle.id)
        #expect(!AskAIController.rect(added.frame).intersects(AskAIController.rect(obstacle.frame)))
        #expect(abs(added.frame.height - Double(RichTextRenderer.height(source: #"\frac{a}{b}"#, type: .latex, width: added.frame.width))) < 0.01)
    }

    // MARK: Capture

    @Test func captureIsClippedToThePageAndRendered() throws {
        let document = canvasDocument()
        let ask = controller(document, FakeProvider(result: .success(Self.answer)))
        let capture = try #require(ask.makeCapture(documentRegion: CGRect(x: -50, y: -50, width: 400, height: 250)))
        #expect(capture.context.scopeFrame == CommandFrame(x: 0, y: 0, width: 350, height: 200))
        #expect(capture.context.capturedRevision == 1 && !capture.context.allowReplace)
        let image = try #require(UIImage(data: capture.png))
        #expect(image.size == CGSize(width: 700, height: 400) && capture.imageScale == 2)
        #expect(ask.makeCapture(documentRegion: CGRect(x: 5_000, y: 5_000, width: 10, height: 10)) == nil)
    }
}

// Ticket 014: newest-ink capture, Auto Ask on pause and handwritten answer sizes.
@MainActor
struct AutoAskTests {
    static func stroke(_ points: [CGPoint], at date: Date) -> PKStroke {
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) / 60, size: CGSize(width: 4, height: 4),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: controls, creationDate: date))
    }

    let page = Page(id: UUID(), size: PageSize(width: 2_000, height: 2_000), background: .blank)
    let viewport = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    let old = Date(timeIntervalSince1970: 100)
    /// "2+2=" written after the document opened.
    var problem: PKStroke { Self.stroke([CGPoint(x: 600, y: 500), CGPoint(x: 700, y: 530)], at: Date(timeIntervalSince1970: 200)) }

    func document() -> FakeAskDocument {
        FakeAskDocument(type: .canvas, pages: [page],
                        strokes: [Self.stroke([CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 80)], at: old)])
    }

    func controller(_ document: FakeAskDocument, auto: AutoAskSettings = AutoAskSettings(enabled: true, delaySeconds: 0.05),
                    selection: CGRect? = nil, delay: Duration = .milliseconds(300)) -> AskAIController {
        let viewport = viewport
        return AskAIController(document: document, region: { viewport }, selection: { selection }, autoAsk: { auto },
                               provider: { (FakeProvider(result: .success(AskAITests.answer), delay: delay), "fake-vision") },
                               blocked: { nil }, schema: Data("{}".utf8))
    }

    func scope(_ ask: AskAIController) -> CGRect? {
        if case .pending(let capture) = ask.phase { AskAIController.rect(capture.context.scopeFrame) } else { nil }
    }

    @Test func inkFromBeforeOpeningIsNotNewest() {
        let ask = controller(document())
        #expect(ask.newestInkRegion == nil)
    }

    @Test func askCapturesOnlyTheNewestInk() {
        let document = document()
        let ask = controller(document)
        document.edit { $0.drawing.strokes.append(problem) }
        let expected = problem.renderBounds.insetBy(dx: -AskAIController.captureMargin, dy: -AskAIController.captureMargin)
        #expect(ask.newestInkRegion == expected)
        ask.ask()
        #expect(scope(ask) == expected)
        // Captured ink is no longer new; the next Ask reuses its region while it has ink.
        #expect(ask.newestInkRegion == nil)
        ask.cancel()
        ask.ask()
        #expect(scope(ask) == expected)
        ask.cancel()
    }

    @Test func selectionWinsOverNewestInk() {
        let document = document()
        let selection = CGRect(x: 30, y: 30, width: 200, height: 100)
        let ask = controller(document, selection: selection)
        document.edit { $0.drawing.strokes.append(problem) }
        ask.ask()
        #expect(scope(ask) == selection)
        ask.cancel()
    }

    @Test func withoutNewInkAskUsesTheFallbackRegion() {
        let ask = controller(document())
        ask.ask()
        #expect(scope(ask) == viewport)
        ask.cancel()
    }

    @Test func pauseAfterInkAsksOnce() async throws {
        let document = document()
        let ask = controller(document, delay: .zero)
        document.edit { $0.drawing.strokes.append(problem) }
        ask.toolEnded(inked: true)
        #expect(ask.isAutoAskScheduled && !ask.isPending)
        for _ in 0..<100 where document.applyCount == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(document.applyCount == 1)
        // No new ink: another pause asks nothing.
        ask.toolEnded(inked: true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(document.applyCount == 1)
    }

    @Test func writingAgainRestartsThePause() async throws {
        let document = document()
        let ask = controller(document, auto: AutoAskSettings(enabled: true, delaySeconds: 0.15))
        document.edit { $0.drawing.strokes.append(problem) }
        ask.toolEnded(inked: true)
        try await Task.sleep(for: .milliseconds(80))
        ask.toolBegan()
        #expect(!ask.isAutoAskScheduled)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!ask.isPending)
        ask.cancel()
    }

    @Test func autoAskSkipsWhenOffErasingSelectingOrReadOnly() async throws {
        let document = document()
        document.edit { $0.drawing.strokes.append(problem) }
        let off = controller(document, auto: AutoAskSettings(enabled: false, delaySeconds: 1))
        off.toolEnded(inked: true)
        #expect(!off.isAutoAskScheduled)

        let erasing = controller(document)
        document.edit { $0.drawing.strokes.append(Self.stroke([CGPoint(x: 900, y: 900), CGPoint(x: 950, y: 920)], at: .now)) }
        erasing.toolEnded(inked: false)
        #expect(!erasing.isAutoAskScheduled)

        let selecting = controller(document, selection: CGRect(x: 0, y: 0, width: 100, height: 100))
        selecting.autoAskNow()
        #expect(!selecting.isPending)

        let readOnly = controller(document)
        document.isReadOnly = true
        readOnly.autoAskNow()
        #expect(!readOnly.isPending)
    }

    @Test func autoAskSettingsDefaultOnAndClampDelay() throws {
        let defaults = try #require(UserDefaults(suiteName: "auto-ask-\(UUID())"))
        #expect(AutoAskSettings.load(defaults) == AutoAskSettings(enabled: true, delaySeconds: 2))
        AutoAskSettings(enabled: false, delaySeconds: 60).save(defaults)
        #expect(AutoAskSettings.load(defaults) == AutoAskSettings(enabled: false, delaySeconds: 10))
    }

    @Test func handwrittenAnswersFitTheirTextAndKeepTheLine() {
        let short = RichTextRenderer.fittingWidth(source: "4", type: .text, maxWidth: 480, handwritten: true)
        let long = RichTextRenderer.fittingWidth(source: String(repeating: "word ", count: 60), type: .text, maxWidth: 480, handwritten: true)
        #expect(short < 100 && long == 480)
        let requested = CGRect(x: 320, y: 100, width: 20, height: 30)
        let frame = AnswerApplier.measuredFrame(.text, "4", requested)
        #expect(frame.minX == 320 && frame.width >= short && abs(frame.midY - requested.midY) < 0.5)
        #expect(frame.height == RichTextRenderer.height(source: "4", type: .text, width: frame.width, handwritten: true))
    }
}

// Ticket 016: placing plot objects and native ink answers.
@MainActor
struct VisualAnswerTests {
    let base = AskAITests()

    @Test func inkAnswerBecomesStrokesBesideTheProblem() async throws {
        let cat = #"{"version":2,"operations":[{"op":"draw_ink","width":200,"height":160,"strokes":[{"kind":"ellipse","points":[[40,40],[160,150]],"closed":true,"color":"black","size":3},{"kind":"polyline","points":[[50,60],[60,10],[90,45]],"closed":false,"color":"black","size":3},{"kind":"smooth","points":[[80,100],[100,110],[120,100]],"closed":false,"color":"pink","size":2}],"placement":"right_of_scope","frame":null}],"message":"A cat."}"#
        let document = base.canvasDocument()
        let ask = base.controller(document, FakeProvider(result: .success(cat)))
        ask.ask()
        try await base.settle(ask)
        #expect(document.applyCount == 1 && document.snapshot.objects.isEmpty)
        let added = Array(document.snapshot.drawing.strokes.dropFirst())
        #expect(added.count == 3)
        let bounds = added.dropFirst().reduce(added[0].renderBounds) { $0.union($1.renderBounds) }
        // Right of the problem, without covering it, and at the natural size (longest side 200 pt).
        #expect(!bounds.intersects(base.equation.renderBounds) && bounds.minX > base.region.maxX)
        #expect(bounds.width < 200 && bounds.width > 100)
        #expect(added.allSatisfy { $0.path.creationDate == InkAnswer.creationDate })
        #expect(ask.newestInkRegion == nil)
    }

    @Test func inkAtFrameMayOverlapForAnnotations() async throws {
        let circle = #"{"version":2,"operations":[{"op":"draw_ink","width":100,"height":50,"strokes":[{"kind":"ellipse","points":[[0,0],[100,50]],"closed":true,"color":"red","size":3}],"placement":"at_frame","frame":{"x":90,"y":90,"width":220,"height":60}}],"message":null}"#
        let document = base.canvasDocument()
        let ask = base.controller(document, FakeProvider(result: .success(circle)))
        ask.ask()
        try await base.settle(ask)
        let added = try #require(document.snapshot.drawing.strokes.last)
        #expect(document.snapshot.drawing.strokes.count == 2 && added.renderBounds.intersects(base.equation.renderBounds))
    }

    @Test func plotAnswerIsAMeasuredObject() async throws {
        let plot = #"{"version":2,"operations":[{"op":"add_object","type":"plot","source":"y = x^2\nx: -3 .. 3","placement":"below_scope","frame":null}],"message":null}"#
        let document = base.canvasDocument()
        let ask = base.controller(document, FakeProvider(result: .success(plot)))
        ask.ask()
        try await base.settle(ask)
        let object = try #require(document.snapshot.objects.last)
        #expect(object.type == .plot && object.rendersHandwritten)
        #expect(object.frame.y >= Double(base.region.maxY))
        #expect(object.frame.height == Double(RichTextRenderer.height(source: object.source, type: .plot,
                                                                      width: object.frame.width, handwritten: true)))
        #expect(!RichTextRenderer.build(source: object.source, type: .plot, width: object.frame.width).warning)
        #expect(RichTextRenderer.build(source: "y = nope(x)", type: .plot, width: 300).warning)
    }

    @Test func reviewReencodesInkAnswers() throws {
        let drawing = InkDrawing(width: 100, height: 50, strokes: [
            InkStrokeSpec(kind: .line, points: [CommandPoint(x: 0, y: 0), CommandPoint(x: 100, y: 50)], closed: false, color: .blue, size: 3)])
        let operations: [CanvasOperation] = [.drawInk(drawing, placement: .rightOfScope, frame: nil)]
        let context = CommandRequestContext(requestId: UUID(), documentId: UUID(), pageId: UUID(), capturedRevision: 1,
                                            scopeFrame: CommandFrame(x: 0, y: 0, width: 100, height: 100), scopeObjectIds: [],
                                            pageBounds: CommandFrame(x: 0, y: 0, width: 595, height: 842), allowReplace: false)
        let state = DocumentValidationState(currentRevision: 1, scopeChanged: false, existingObjectIds: [], appliedRequestIds: [])
        #expect(CommandValidator.validate(AskAIController.encode(operations), context: context, state: state) == .valid(operations))
    }

    @Test func smoothAndClosedPaths() {
        let square = InkStrokeSpec(kind: .polyline, points: [CommandPoint(x: 0, y: 0), CommandPoint(x: 60, y: 0), CommandPoint(x: 60, y: 60)],
                                   closed: true, color: .black, size: 3)
        let path = InkAnswer.path(square)
        #expect(path.first == path.last && path.count > 20)
        let curve = InkStrokeSpec(kind: .smooth, points: [CommandPoint(x: 0, y: 0), CommandPoint(x: 50, y: 40), CommandPoint(x: 100, y: 0)],
                                  closed: false, color: .black, size: 3)
        let smooth = InkAnswer.path(curve)
        #expect(smooth.first == CGPoint(x: 0, y: 0) && smooth.last == CGPoint(x: 100, y: 0))
        #expect(smooth.contains { abs($0.x - 50) < 0.01 && abs($0.y - 40) < 0.01 })
    }
}
