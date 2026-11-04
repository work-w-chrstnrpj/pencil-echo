import Foundation
import PencilKit
import Testing
@testable import PencilEcho

// Ticket 008: save/reopen, revision, unified undo, pages, canvas growth and autosave.
// Native PencilKit stroke undo needs the device; strokes here are committed as
// snapshots, the same path every non-native edit takes. The undo manager groups by
// event, so tests that count undo steps let the run loop turn between edits, as
// separate user actions would.
@MainActor
struct EditorSessionTests {
    let store: DocumentStore

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("EditorSessionTests-\(UUID().uuidString)")
        store = DocumentStore(rootURL: base.appendingPathComponent("Documents", isDirectory: true),
                              preMigrationURL: base.appendingPathComponent("PreMigration", isDirectory: true), appVersion: "test")
    }

    static func stroke(from start: CGPoint, to end: CGPoint) -> PKStroke {
        let points = (0...8).map { step in
            let t = CGFloat(step) / 8
            return PKStrokePoint(location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                                 timeOffset: Double(step) / 60, size: CGSize(width: 4, height: 4), opacity: 1,
                                 force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)))
    }

    func open(_ id: UUID) async throws -> EditorSession {
        EditorSession(loaded: try await store.load(id: id), store: store)
    }

    /// Ends the current run-loop event, closing its undo group.
    func nextEvent() async throws { try await Task.sleep(for: .milliseconds(20)) }

    /// Content fields only; dates round-trip at millisecond precision.
    func content(_ objects: [DocumentObject]) -> [String] {
        objects.map { "\($0.id) \($0.pageId) \($0.type) \($0.frame) \($0.zIndex) \($0.source) \($0.createdBy)" }
    }

    func addStroke(_ session: EditorSession, from start: CGPoint, to end: CGPoint) {
        var next = session.snapshot
        next.drawing = PKDrawing(strokes: next.drawing.strokes + [Self.stroke(from: start, to: end)])
        session.commit(next, named: "Stroke")
    }

    // MARK: Save and reopen

    @Test func notebookRoundTripKeepsInkObjectsBackgroundsAndPageOrder() async throws {
        let created = try await store.create(type: .notebook)
        let session = try await open(created.id)
        let second = try #require(session.addPage(after: 0))
        session.setBackground(.grid, page: second)
        session.setBackground(.lined, page: 0)
        let pageTwo = session.layout.pageRect(second)
        addStroke(session, from: CGPoint(x: pageTwo.minX + 100, y: pageTwo.minY + 100),
                  to: CGPoint(x: pageTwo.minX + 300, y: pageTwo.minY + 120))
        let textId = try #require(session.addTextObject(at: CGPoint(x: pageTwo.midX, y: pageTwo.minY + 400), source: "Test text"))
        #expect(await session.saveNow())

        let reopened = try await open(created.id)
        #expect(reopened.pages.map(\.id) == session.pages.map(\.id))
        #expect(reopened.pages.map(\.background.style) == [.lined, .grid])
        #expect(content(reopened.objects) == content(session.objects))
        let text = try #require(reopened.objects.first { $0.id == textId })
        #expect(text.pageId == session.pages[1].id)
        #expect(text.source == "Test text")
        #expect(reopened.revision == session.revision)
        #expect(reopened.drawing.strokes.count == 1)
        // Composed back into the same document-space position.
        let bounds = reopened.drawing.bounds, original = session.drawing.bounds
        #expect(abs(bounds.minX - original.minX) < 0.5 && abs(bounds.minY - original.minY) < 0.5)

        // On disk the ink belongs to page two and is page-relative.
        let document = try await store.load(id: created.id).document
        #expect(document.ink[session.pages[0].id] == nil)
        let pageInk = try PKDrawing(data: try #require(document.ink[session.pages[1].id]))
        #expect(pageInk.bounds.minY < 200)
        #expect(document.thumbnail != nil)
    }

    @Test func canvasGrowsNearEdgesAndKeepsSizeAfterReopen() async throws {
        let created = try await store.create(type: .canvas)
        let session = try await open(created.id)
        #expect(session.pages[0].size == DocumentSchema.newCanvasSize)
        var drawing = session.drawing
        drawing.strokes.append(Self.stroke(from: CGPoint(x: 1_500, y: 100), to: CGPoint(x: 1_900, y: 150)))
        session.inkDidChange(drawing)
        #expect(session.pages[0].size.width == 3_000)
        #expect(session.pages[0].size.height == 2_000)
        #expect(await session.saveNow())
        let reopened = try await open(created.id)
        #expect(reopened.pages[0].size == PageSize(width: 3_000, height: 2_000))
    }

    @Test func canvasGrowthStopsAtTheSchemaCap() {
        let bounds = CGRect(x: 19_900, y: 0, width: 50, height: 50)
        let size = CanvasGrowth.grown(PageSize(width: 19_500, height: 2_000), toFit: bounds)
        #expect(size.width == DocumentLimits.maxCanvasSide)
        #expect(size.height == 2_000)
    }

    // MARK: Revision and undo

    @Test func undoAndRedoSpanStrokesAndObjectMovesAndAdvanceRevision() async throws {
        let created = try await store.create(type: .canvas)
        let session = try await open(created.id)
        addStroke(session, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 100))
        try await nextEvent()
        let id = try #require(session.addTextObject(at: CGPoint(x: 500, y: 500)))
        try await nextEvent()
        let before = session.snapshot
        let moved = session.moved(before, strokes: [0], objectIds: [id], delta: CGPoint(x: 40, y: 30))
        session.commit(moved, named: "Move")
        try await nextEvent()
        #expect(session.revision == 3)

        session.manager.undo()
        try await nextEvent()
        #expect(session.snapshot == before)
        #expect(session.revision == 4)
        session.manager.undo()
        try await nextEvent()
        #expect(session.objects.isEmpty)
        #expect(session.drawing.strokes.count == 1)
        session.manager.undo()
        try await nextEvent()
        #expect(session.drawing.strokes.isEmpty)
        #expect(session.revision == 6)
        for _ in 0..<3 {
            session.manager.redo()
            try await nextEvent()
        }
        #expect(session.snapshot.objects == moved.objects)
        #expect(session.drawing.strokes.first?.transform == moved.drawing.strokes.first?.transform)
        #expect(session.revision == 9)
    }

    @Test func previewsAndNoOpCommitsDoNotChangeRevisionOrHistory() async throws {
        let created = try await store.create(type: .canvas)
        let session = try await open(created.id)
        let id = try #require(session.addTextObject(at: CGPoint(x: 300, y: 300)))
        let committed = session.snapshot
        session.preview(session.moved(committed, strokes: [], objectIds: [id], delta: CGPoint(x: 10, y: 0)))
        session.preview(committed)
        session.commit(committed, named: "Nothing")
        #expect(session.revision == 1)
        session.manager.undo()
        #expect(!session.manager.canUndo)
    }

    @Test func movesAreClampedSoObjectsStayOnTheirPage() async throws {
        let created = try await store.create(type: .notebook)
        let session = try await open(created.id)
        let id = try #require(session.addTextObject(at: CGPoint(x: 100, y: 100)))
        let delta = session.clampedDelta(CGPoint(x: -1_000, y: 5_000), strokes: [], objectIds: [id], in: session.snapshot)
        let frame = try #require(session.moved(session.snapshot, strokes: [], objectIds: [id], delta: delta).objects.first?.frame)
        #expect(frame.x == 0)
        #expect(frame.y + frame.height == DocumentSchema.a4.height)
    }

    @Test func resizeKeepsMinimumSideAndPageBounds() async throws {
        let created = try await store.create(type: .notebook)
        let session = try await open(created.id)
        let id = try #require(session.addTextObject(at: CGPoint(x: 300, y: 300)))
        let tiny = try #require(session.resized(session.snapshot, objectId: id, to: CGSize(width: 1, height: 1)).objects.first?.frame)
        #expect(tiny.width == DocumentLimits.minObjectSide && tiny.height == DocumentLimits.minObjectSide)
        let huge = try #require(session.resized(session.snapshot, objectId: id, to: CGSize(width: 9_999, height: 9_999)).objects.first?.frame)
        #expect(huge.x + huge.width == DocumentSchema.a4.width)
        #expect(huge.y + huge.height == DocumentSchema.a4.height)
    }

    // MARK: Pages

    @Test func deletingAPageRemovesItsContentShiftsLaterInkAndUndoes() async throws {
        let created = try await store.create(type: .notebook)
        let session = try await open(created.id)
        session.addPage(after: 0)
        session.addPage(after: 1)
        let layout = session.layout
        let middle = layout.pageRect(1), last = layout.pageRect(2)
        addStroke(session, from: CGPoint(x: middle.minX + 50, y: middle.minY + 50), to: CGPoint(x: middle.minX + 150, y: middle.minY + 50))
        addStroke(session, from: CGPoint(x: last.minX + 50, y: last.minY + 60), to: CGPoint(x: last.minX + 150, y: last.minY + 60))
        session.addTextObject(at: CGPoint(x: middle.midX, y: middle.midY))
        try await nextEvent()
        let before = session.snapshot

        session.deletePage(at: 1)
        try await nextEvent()
        #expect(session.pages.count == 2)
        #expect(session.objects.isEmpty)
        #expect(session.drawing.strokes.count == 1)
        // The last page's stroke moved up into the second slot.
        let shifted = session.drawing.bounds.minY - session.layout.pageRect(1).minY
        #expect(abs(shifted - (before.drawing.strokes[1].renderBounds.minY - last.minY)) < 0.5)

        session.manager.undo()
        #expect(session.snapshot == before)
    }

    @Test func lastNotebookPageCannotBeDeleted() async throws {
        let created = try await store.create(type: .notebook)
        let session = try await open(created.id)
        session.deletePage(at: 0)
        #expect(session.pages.count == 1)
        #expect(session.revision == 0)
    }

    @Test func layoutComposeAndDecomposeRoundTrip() {
        let pages = (0..<3).map { _ in Page(id: UUID(), size: DocumentSchema.a4, background: .blank) }
        let layout = EditorLayout(type: .notebook, pages: pages)
        let local = PKDrawing(strokes: [Self.stroke(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 90, y: 40))])
        let composed = layout.compose([pages[2].id: local])
        #expect(composed.bounds.minY > layout.pageRect(2).minY)
        let split = layout.decompose(composed)
        #expect(Set(split.keys) == [pages[2].id])
        let back = try! #require(split[pages[2].id])
        #expect(abs(back.bounds.minX - local.bounds.minX) < 0.5 && abs(back.bounds.minY - local.bounds.minY) < 0.5)
    }

    // MARK: Autosave and conflicts

    @Test func autosaveWritesAfterTheDebounce() async throws {
        let created = try await store.create(type: .canvas)
        let session = try await open(created.id)
        session.autosaveDelay = .milliseconds(50)
        session.addTextObject(at: CGPoint(x: 200, y: 200))
        #expect(session.saveState == .pending)
        for _ in 0..<40 where session.hasUnsavedChanges { try await Task.sleep(for: .milliseconds(25)) }
        #expect(!session.hasUnsavedChanges)
        #expect(try await store.load(id: created.id).document.manifest.revision == 1)
    }

    @Test func saveWithoutChangesWritesNothing() async throws {
        let created = try await store.create(type: .canvas)
        let session = try await open(created.id)
        let url = await store.packageURL(for: created.id)
        let before = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent("manifest.json").path)[.modificationDate] as? Date
        #expect(await session.saveNow())
        let after = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent("manifest.json").path)[.modificationDate] as? Date
        #expect(before == after)
    }

    @Test func secondWriterConflictStopsSavingWithoutOverwriting() async throws {
        let created = try await store.create(type: .canvas)
        let first = try await open(created.id)
        let second = try await open(created.id)
        first.addTextObject(at: CGPoint(x: 100, y: 100), source: "first")
        #expect(await first.saveNow())
        second.addTextObject(at: CGPoint(x: 100, y: 100), source: "second")
        #expect(!(await second.saveNow()))
        if case .failed = second.saveState {} else { Issue.record("expected a failed save state") }
        #expect(try await store.load(id: created.id).document.objects.map(\.source) == ["first"])
    }

    @Test func readOnlySessionsRefuseEditsAndNeverSave() async throws {
        let created = try await store.create(type: .notebook)
        let session = EditorSession(loaded: try await store.load(id: created.id), store: store, readOnlyReason: "open elsewhere")
        #expect(session.addTextObject(at: CGPoint(x: 100, y: 100)) == nil)
        session.setBackground(.grid, page: 0)
        #expect(session.pages[0].background == .blank)
        #expect(session.revision == 0)
        #expect(session.saveState == .readOnly("open elsewhere"))
    }

    @Test func openDocumentsAllowsOneEditorPerDocument() {
        let id = UUID()
        let registry = OpenDocuments()
        #expect(registry.claim(id))
        #expect(!registry.claim(id))
        registry.release(id)
        #expect(registry.claim(id))
    }
}

extension EditorSessionTests {
    @Test func editorRenameGridAndAppearanceRoundTrip() async throws {
        let created = try await store.create(type: .canvas)
        let session = try await open(created.id)
        #expect(session.manifest.gridVisible == nil)
        #expect(!session.rename(to: "  "))
        #expect(!session.rename(to: String(repeating: "x", count: 201)))
        #expect(session.rename(to: "  Editor title  "))
        session.setGridVisible(false)
        let id = try #require(session.addTextObject(at: CGPoint(x: 100, y: 100)))
        var next = session.snapshot
        next.objects[0].aiAppearance = AIAnswerAppearance(ink: .purple, font: .rounded)
        session.commit(next, named: "Style")
        #expect(await session.saveNow())
        let reopened = try await open(created.id)
        #expect(reopened.manifest.title == "Editor title")
        #expect(reopened.manifest.gridVisible == false)
        #expect(reopened.objects.first { $0.id == id }?.aiAppearance == AIAnswerAppearance(ink: .purple, font: .rounded))
        #expect(reopened.saveState == .saved)
    }

    @Test func handModeKeepsNavigationAndDisablesDrawing() async throws {
        let created = try await store.create(type: .canvas)
        let session = try await open(created.id)
        let editor = DocumentEditorController(session: session, assetsURL: nil)
        editor.loadViewIfNeeded()
        editor.setHandMode(true)
        #expect(!editor.canvas.isDrawingEnabled)
        #expect(editor.canvas.isScrollEnabled)
        #expect(editor.canvas.maximumZoomScale == 4)
        editor.setHandMode(false)
        #expect(editor.canvas.isDrawingEnabled)
    }
}

extension EditorSessionTests {
    @Test func metadataPreferencesDoNotAdvanceAIRevision() async throws {
        let created = try await store.create(type: .canvas)
        let session = try await open(created.id), revision = session.revision
        #expect(session.rename(to: "Metadata title"))
        session.setGridVisible(false)
        session.setChatPanelOpen(true)
        #expect(session.revision == revision && session.hasUnsavedChanges)
        #expect(await session.saveNow())
        #expect(!session.hasUnsavedChanges)
    }
}
