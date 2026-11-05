import PencilKit
import Observation

/// Everything an undo step restores. Ink is the composed document-space drawing.
struct EditorSnapshot: Equatable {
    var pages: [Page]
    var drawing: PKDrawing
    var objects: [DocumentObject]
    var draftInk: [DraftInkBatch] = []
}

/// One open document: content, unified undo, revision and autosave (ticket 008).
///
/// Undo: PencilKit registers each native stroke and erase on `manager` (the canvas
/// returns it as its undo manager). Every other edit is `commit`, which registers
/// an inverse snapshot. Grouping is by event, so each user action is one undo step.
/// Revision follows docs/database/document-schema-v1.md: +1 per committed content
/// change, undo and redo included, never for previews, selection or view changes.
@MainActor
@Observable
final class EditorSession {
    enum SaveState: Equatable {
        case saved
        case pending
        case saving
        /// Reason text names no content.
        case failed(String)
        case readOnly(String)
    }

    static let defaultTextSize = CGSize(width: 240, height: 80)

    let manager = UndoManager()
    let store: DocumentStore
    let isReadOnly: Bool
    private(set) var manifest: DocumentManifest
    private(set) var pages: [Page]
    private(set) var objects: [DocumentObject]
    private(set) var drawing: PKDrawing
    private(set) var draftInk: [DraftInkBatch]
    private(set) var savedRevision: Int
    private(set) var saveState: SaveState {
        didSet { if saveState != oldValue { onSaveStateChange?(saveState) } }
    }
    /// Debounce after the last change; the most a force-quit can lose.
    var autosaveDelay: Duration = .seconds(2)
    /// Called after content changes (commit, undo, redo, preview), so views re-render.
    var onApply: (() -> Void)?
    var onSaveStateChange: ((SaveState) -> Void)?

    private var metadataGeneration = 0
    private var savedMetadataGeneration = 0
    private var base: Document
    private var autosaveTask: Task<Void, Never>?
    private var saveChain: Task<Void, Never>?
    private var stopped = false

    /// `readOnlyReason` is set when the document is open in another window. Unreadable
    /// ink also opens read-only, so its original bytes are never overwritten.
    init(loaded: LoadedDocument, store: DocumentStore, readOnlyReason: String? = nil) {
        let document = loaded.document
        base = document
        self.store = store
        manifest = document.manifest
        pages = document.pages
        objects = document.objects
        draftInk = document.chat?.draftInk ?? []
        savedRevision = document.manifest.revision
        let layout = EditorLayout(type: document.manifest.type, pages: document.pages)
        drawing = layout.compose(document.ink.compactMapValues { try? PKDrawing(data: $0) })
        let unreadableInk = loaded.issues.contains { if case .inkUnreadable = $0 { true } else { false } }
        let reason = readOnlyReason ?? (unreadableInk ? "Some ink can't be read, so this document opened read-only." : nil)
        isReadOnly = reason != nil
        saveState = reason.map(SaveState.readOnly) ?? .saved
        manager.levelsOfUndo = 100
    }

    var type: DocumentType { manifest.type }
    var revision: Int { manifest.revision }
    var layout: EditorLayout { EditorLayout(type: manifest.type, pages: pages) }
    var snapshot: EditorSnapshot { EditorSnapshot(pages: pages, drawing: drawing, objects: objects, draftInk: draftInk) }
    var hasUnsavedChanges: Bool { manifest.revision != savedRevision || metadataGeneration != savedMetadataGeneration }

    // MARK: - Applying changes

    /// Native PencilKit edits (stroke, erase, native lasso, native undo/redo of those).
    /// PencilKit already registered the undo; this records content and revision.
    func inkDidChange(_ next: PKDrawing) {
        guard !isReadOnly, next != drawing else { return }
        drawing = next
        if type == .canvas { growCanvas() }
        contentChanged()
        onApply?()
    }

    /// A gesture preview: shown, but not in history and not a content change.
    func preview(_ state: EditorSnapshot) {
        apply(state)
    }

    /// One undoable content change.
    func commit(_ next: EditorSnapshot, named name: String) {
        guard !isReadOnly else { return }
        var next = next
        for index in next.objects.indices {
            let object = next.objects[index]
            let previous = objects.first { $0.id == object.id }
            if object.type == .markdown || object.type == .latex || object.type == .plot,
               previous == nil || previous?.source != object.source || previous?.frame.width != object.frame.width {
                fitRichObject(&next.objects[index], pages: next.pages)
            }
        }
        guard next != snapshot else { return }
        let old = snapshot
        // The manager groups by event (what PencilKit expects), so a user action is one
        // undo step; this group keeps the restore and its registration together.
        manager.beginUndoGrouping()
        registerRestore(old, named: name)
        apply(next)
        manager.endUndoGrouping()
        contentChanged()
    }

    private func registerRestore(_ state: EditorSnapshot, named name: String) {
        manager.registerUndo(withTarget: self) { target in
            target.registerRestore(target.snapshot, named: name)
            target.apply(state)
            target.contentChanged()
        }
        manager.setActionName(name)
    }

    private func apply(_ state: EditorSnapshot) {
        var state = state
        // A canvas never shrinks back under ink drawn after the snapshot was taken.
        if type == .canvas, let current = pages.first, !state.pages.isEmpty {
            state.pages[0].size = PageSize(width: max(current.size.width, state.pages[0].size.width),
                                           height: max(current.size.height, state.pages[0].size.height))
        }
        pages = state.pages
        drawing = state.drawing
        objects = state.objects
        draftInk = state.draftInk
        // Programmatic drawing assignment must not register a second PencilKit undo.
        manager.disableUndoRegistration()
        onApply?()
        manager.enableUndoRegistration()
    }

    private func growCanvas() {
        var bounds = drawing.bounds
        for object in objects { bounds = bounds.union(layout.documentFrame(of: object)) }
        let grown = CanvasGrowth.grown(pages[0].size, toFit: bounds)
        if grown != pages[0].size { pages[0].size = grown }
    }

    private func contentChanged() {
        manifest.revision += 1
        scheduleAutosave()
    }

    private func metadataChanged() { metadataGeneration += 1; scheduleAutosave() }

    func rename(to title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isReadOnly, !title.isEmpty, title.count <= DocumentLimits.maxTitleLength else { return false }
        guard title != manifest.title else { return true }
        manifest.title = title
        metadataChanged()
        return true
    }

    func setGridVisible(_ visible: Bool) {
        guard !isReadOnly else { return }
        manifest.gridVisible = visible
        metadataChanged()
        onApply?()
    }

    // MARK: - Edits

    /// Adds a text object centred on `point` (document space), clamped into its page.
    @discardableResult
    func addTextObject(at point: CGPoint, source: String = "Text", type: ObjectType = .text) -> UUID? {
        guard !isReadOnly, type != .image, source.utf8.count <= DocumentLimits.maxSourceBytes, objects.count < DocumentLimits.maxObjects else { return nil }
        let layout = layout
        let index = layout.pageIndex(nearestY: point.y)
        let page = layout.pageRect(index)
        let size = CGSize(width: min(Self.defaultTextSize.width, page.width), height: min(Self.defaultTextSize.height, page.height))
        let x = min(max(0, point.x - page.minX - size.width / 2), page.width - size.width)
        let y = min(max(0, point.y - page.minY - size.height / 2), page.height - size.height)
        let now = Date()
        let object = DocumentObject(id: UUID(), pageId: pages[index].id, type: type,
                                    frame: PageRect(x: x, y: y, width: size.width, height: size.height),
                                    zIndex: (objects.map(\.zIndex).max() ?? -1) + 1, source: source,
                                    assetRefs: [], createdBy: .user, createdAt: now, updatedAt: now)
        var next = snapshot
        next.objects.append(object)
        commit(next, named: "Add Text")
        return object.id
    }

    func updateSource(of id: UUID, to source: String) {
        guard let index = objects.firstIndex(where: { $0.id == id }), objects[index].source != source,
              source.utf8.count <= DocumentLimits.maxSourceBytes else { return }
        var next = snapshot
        next.objects[index].source = source
        next.objects[index].updatedAt = Date()
        commit(next, named: "Edit Text")
    }

    /// Translation clamped as one group: every selected object stays inside its page,
    /// and ink-only selections stay inside the document.
    func clampedDelta(_ delta: CGPoint, strokes: Set<Int>, objectIds: Set<UUID>, in state: EditorSnapshot) -> CGPoint {
        var minX = -CGFloat.infinity, maxX = CGFloat.infinity, minY = -CGFloat.infinity, maxY = CGFloat.infinity
        let layout = EditorLayout(type: type, pages: state.pages)
        for object in state.objects where objectIds.contains(object.id) {
            guard let index = layout.pageIndex(of: object.pageId) else { continue }
            let page = state.pages[index].size, frame = object.frame
            minX = max(minX, -frame.x); maxX = min(maxX, page.width - frame.x - frame.width)
            minY = max(minY, -frame.y); maxY = min(maxY, page.height - frame.y - frame.height)
        }
        var inkBounds = CGRect.null
        for index in strokes where state.drawing.strokes.indices.contains(index) {
            inkBounds = inkBounds.union(state.drawing.strokes[index].renderBounds)
        }
        if !inkBounds.isNull {
            let content = layout.contentSize
            minX = max(minX, -inkBounds.minX); maxX = min(maxX, content.width - inkBounds.maxX)
            minY = max(minY, -inkBounds.minY); maxY = min(maxY, content.height - inkBounds.maxY)
        }
        guard minX <= maxX, minY <= maxY else { return .zero }
        return CGPoint(x: min(max(delta.x, minX), maxX), y: min(max(delta.y, minY), maxY))
    }

    /// `state` with the selection translated. Stroke transforms keep masks and metadata.
    func moved(_ state: EditorSnapshot, strokes: Set<Int>, objectIds: Set<UUID>, delta: CGPoint) -> EditorSnapshot {
        var next = state
        var moved = state.drawing.strokes
        for index in strokes where moved.indices.contains(index) {
            moved[index].transform = moved[index].transform.concatenating(CGAffineTransform(translationX: delta.x, y: delta.y))
        }
        next.drawing = PKDrawing(strokes: moved)
        let now = Date()
        for index in next.objects.indices where objectIds.contains(next.objects[index].id) {
            next.objects[index].frame.x += delta.x
            next.objects[index].frame.y += delta.y
            next.objects[index].updatedAt = now
        }
        return next
    }

    /// `state` with one object resized to `size`, kept inside its page and above the minimum side.
    func resized(_ state: EditorSnapshot, objectId: UUID, to size: CGSize) -> EditorSnapshot {
        var next = state
        guard let index = next.objects.firstIndex(where: { $0.id == objectId }),
              let pageIndex = EditorLayout(type: type, pages: state.pages).pageIndex(of: next.objects[index].pageId) else { return state }
        let page = state.pages[pageIndex].size, frame = next.objects[index].frame
        next.objects[index].frame.width = min(max(DocumentLimits.minObjectSide, size.width), page.width - frame.x)
        next.objects[index].frame.height = min(max(DocumentLimits.minObjectSide, size.height), page.height - frame.y)
        fitRichObject(&next.objects[index], pages: next.pages)
        next.objects[index].updatedAt = Date()
        return next
    }

    private func fitRichObject(_ object: inout DocumentObject, pages: [Page]) {
        guard object.type == .markdown || object.type == .latex || object.type == .plot,
              let page = pages.first(where: { $0.id == object.pageId }) else { return }
        object.frame.height = min(max(DocumentLimits.minObjectSide, page.size.height - object.frame.y),
                                  RichTextRenderer.height(source: object.source, type: object.type, width: object.frame.width,
                                                          handwritten: object.rendersHandwritten))
    }

    func deleteSelection(strokes: Set<Int>, objectIds: Set<UUID>) {
        guard !strokes.isEmpty || !objectIds.isEmpty else { return }
        var next = snapshot
        next.drawing = PKDrawing(strokes: drawing.strokes.enumerated().filter { !strokes.contains($0.offset) }.map(\.element))
        next.objects.removeAll { objectIds.contains($0.id) }
        commit(next, named: "Delete Selection")
    }

    func setBackground(_ style: BackgroundStyle, page index: Int) {
        guard pages.indices.contains(index) else { return }
        var next = snapshot
        next.pages[index].background = style == .blank ? .blank : PageBackground(style: style, spacing: nil)
        commit(next, named: "Change Background")
    }

    /// Inserts a page after `index` with that page's background. Notebook only.
    @discardableResult
    func addPage(after index: Int) -> Int? {
        guard type == .notebook, pages.count < DocumentLimits.maxNotebookPages, pages.indices.contains(index) else { return nil }
        let ink = layout.decompose(drawing)
        var next = snapshot
        next.pages.insert(Page(id: UUID(), size: DocumentSchema.a4, background: pages[index].background), at: index + 1)
        next.drawing = EditorLayout(type: type, pages: next.pages).compose(ink)
        commit(next, named: "Add Page")
        return index + 1
    }

    /// Removes a page with its ink and objects. Notebook only; the last page stays.
    func deletePage(at index: Int) {
        guard type == .notebook, pages.count > 1, pages.indices.contains(index) else { return }
        let removed = pages[index].id
        var ink = layout.decompose(drawing)
        ink[removed] = nil
        var next = snapshot
        next.pages.remove(at: index)
        next.objects.removeAll { $0.pageId == removed }
        next.drawing = EditorLayout(type: type, pages: next.pages).compose(ink)
        commit(next, named: "Delete Page")
    }

    // MARK: - Ask AI (ticket 010)

    var conversation: Conversation { base.conversation ?? Conversation() }

    /// One undo step for an AI answer. The conversation is set first and is not
    /// undoable: `appliedRequests` backs duplicate detection even after undo
    /// (docs/database/document-schema-v1.md, conversation.json).
    func applyAIAnswer(_ next: EditorSnapshot, conversation: Conversation, named name: String) {
        guard !isReadOnly else { return }
        base.conversation = conversation
        commit(next, named: name)
    }

    // MARK: - Agent chat (021)

    var chatHistory: AgentChatHistory { base.chat ?? AgentChatHistory() }
    var hasDrafts: Bool { objects.contains { $0.isDraft == true } || !draftInk.isEmpty }

    func setChatPanelOpen(_ open: Bool) {
        guard !isReadOnly else { return }
        manifest.chatPanelOpen = open
        metadataChanged()
    }

    func clearChat() {
        guard !isReadOnly else { return }
        var history = chatHistory
        history.messages = []
        base.chat = history
        metadataChanged()
    }

    func applyChatAnswer(_ next: EditorSnapshot, history: AgentChatHistory, requestId: UUID) {
        guard !isReadOnly else { return }
        base.chat = history
        // Duplicate suppression survives undo and New chat.
        var conversation = conversation
        conversation.appliedRequests.append(AppliedRequest(requestId: requestId, appliedAt: Date()))
        base.conversation = conversation
        metadataChanged()
        commit(next, named: "Chat drafts")
    }

    /// Drafts from Claude Code over MCP (ticket 023). One undo step; the request ID
    /// is recorded so the same capture can't be placed twice, even after undo.
    func applyExternalDrafts(_ next: EditorSnapshot, requestId: UUID) {
        guard !isReadOnly else { return }
        var conversation = conversation
        conversation.appliedRequests.append(AppliedRequest(requestId: requestId, appliedAt: Date()))
        base.conversation = conversation
        metadataChanged()
        commit(next, named: "Claude Code drafts")
    }

    func acceptAllDrafts() {
        var next = snapshot
        for i in next.objects.indices where next.objects[i].isDraft == true { next.objects[i].isDraft = nil }
        next.draftInk = []
        commit(next, named: "Accept drafts")
    }

    func discardAllDrafts() {
        var next = snapshot
        next.objects.removeAll { $0.isDraft == true }
        let dates = Set(next.draftInk.map(\.strokeDate))
        next.drawing = PKDrawing(strokes: next.drawing.strokes.filter { !dates.contains($0.path.creationDate) })
        next.draftInk = []
        commit(next, named: "Discard drafts")
    }

    // MARK: - Saving

    func makeDocument() -> Document {
        var document = base
        document.manifest = manifest
        document.pages = pages
        document.objects = objects
        if document.chat != nil || !draftInk.isEmpty {
            var history = chatHistory
            history.draftInk = draftInk
            document.chat = history
        }
        document.ink = layout.decompose(drawing).compactMapValues { $0.strokes.isEmpty ? nil : $0.dataRepresentation() }
        document.thumbnail = ThumbnailRenderer.render(document, assetsURL: store.rootURL
            .appendingPathComponent(document.id.uuidString + "." + DocumentSchema.packageExtension)
            .appendingPathComponent(DocumentStore.FileName.assets, isDirectory: true))
        return document
    }

    private func scheduleAutosave() {
        guard !isReadOnly, !stopped else { return }
        if saveState != .saving { saveState = .pending }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self, autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    /// Saves now if there are unsaved changes. Saves run one at a time, in order.
    /// Returns false when changes remain unsaved.
    @discardableResult
    func saveNow() async -> Bool {
        autosaveTask?.cancel()
        autosaveTask = nil
        let previous = saveChain
        let task = Task { [weak self] in
            await previous?.value
            await self?.performSave()
        }
        saveChain = task
        await task.value
        return !hasUnsavedChanges || isReadOnly
    }

    private func performSave() async {
        guard !isReadOnly, !stopped, hasUnsavedChanges else { return }
        let document = makeDocument()
        let metadata = metadataGeneration
        saveState = .saving
        do {
            let receipt = try await store.save(document, expectedRevision: savedRevision)
            savedRevision = receipt.revision
            savedMetadataGeneration = metadata
            manifest.updatedAt = receipt.updatedAt
            base.migratedFrom = nil
            saveState = hasUnsavedChanges ? .pending : .saved
            if hasUnsavedChanges { scheduleAutosave() }
        } catch DocumentStoreError.conflict {
            // Another writer changed the package. Stop writing so neither copy is lost.
            stopped = true
            saveState = .failed("This document changed elsewhere. Close it and reopen to continue.")
        } catch {
            saveState = .failed("Couldn't save. Changes are kept while the document is open.")
        }
    }
}

/// Documents open in any window of this process. v1 allows one editing window per
/// document; a second window opens it read-only (ticket 008).
@MainActor
final class OpenDocuments {
    static let shared = OpenDocuments()
    private var ids: Set<UUID> = []

    /// True when the caller now owns editing for `id`.
    func claim(_ id: UUID) -> Bool { ids.insert(id).inserted }

    func release(_ id: UUID) { ids.remove(id) }
}
