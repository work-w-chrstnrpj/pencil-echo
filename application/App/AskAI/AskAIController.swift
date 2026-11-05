import Foundation
import Observation
import PencilKit
import UIKit

/// What Ask AI needs from an open document. `EditorSession` conforms (ticket 008);
/// tests use a fake. Ink is the composed document-space drawing; object frames are page points.
@MainActor
protocol AskAIDocument: AnyObject {
    var documentId: UUID { get }
    var isReadOnly: Bool { get }
    var revision: Int { get }
    var layout: EditorLayout { get }
    var snapshot: EditorSnapshot { get }
    var conversation: Conversation { get }
    var captureAssetsURL: URL? { get }
    /// One undo step for the answer. The conversation change is not undoable.
    func applyAIAnswer(_ next: EditorSnapshot, conversation: Conversation, named name: String)
}

extension AskAIDocument { var captureAssetsURL: URL? { nil } }

/// A provider that refuses every request: used when the settings have no usable
/// endpoint, so Ask AI never falls back to a different provider.
struct UnconfiguredProvider: AIProvider {
    func capabilities(model: String) -> ModelCapabilities? { nil }
    func send(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: AIError.invalidRequest) }
    }
}

/// An immutable capture of one request (ticket 010 "Capture").
/// `context.scopeFrame` is the whole captured image; `focusFrame` is the newest
/// input inside it (ticket 017). Staleness and flowing placement use the focus.
struct AskAICapture: Equatable, Sendable {
    var context: CommandRequestContext
    /// Page points, inside `context.scopeFrame`.
    var focusFrame: CommandFrame
    var instruction: String
    var png: Data
    var imageScale: Double
    /// A magnified copy of `focusFrame`, sent only when that region is small beside the capture.
    var focusPNG: Data?
    var focusImageScale: Double?
    var fingerprint: Int
}

/// Ask AI lifecycle for one open document: capture → request → validate → place → apply.
/// Never retries automatically and never switches providers.
@MainActor
@Observable
final class AskAIController {
    enum Phase: Equatable {
        case idle
        case pending(AskAICapture)
        /// The problem changed while pending; the user decides.
        case review(AskAICapture, [CanvasOperation])
        /// Kept so Retry can resend the same capture and instruction.
        case failed(AskAICapture, String)
    }

    private(set) var phase = Phase.idle
    private(set) var autoAskSuspended = false
    func suspendAutoAsk(_ suspended: Bool) { autoAskSuspended = suspended; if suspended { toolBegan() } }
    var instruction = CanvasCommandPrompt.defaultInstruction
    private(set) var hasPlacedAnswer = false
    var status: String {
        switch phase {
        case .idle: hasPlacedAnswer ? "Placed" : "Ready"
        case .pending: "Asking…"
        case .review: "Review answer"
        case .failed(_, let message): message
        }
    }

    private let document: AskAIDocument
    private let region: () -> CGRect
    private let selection: () -> CGRect?
    private let autoAsk: () -> AutoAskSettings
    private let provider: () -> (any AIProvider, String)
    private let blocked: () -> String?
    private let schema: Data?
    private let now: () -> Date
    private var task: Task<Void, Never>?
    private var generation = 0
    private var autoTask: Task<Void, Never>?
    /// Strokes created after this date are the newest ink (ticket 014). Creation dates
    /// survive moves and erasing, so lasso and eraser edits don't count as new ink.
    private var inkWatermark: Date
    /// The region of the last newest-ink capture, reused when Ask has no new ink.
    private var lastInkRegion: CGRect?

    nonisolated static let captureMargin = 24.0
    nonisolated static let maxImageSide = 2048.0
    /// How far around the newest ink to look for earlier work it may refer to (ticket 017).
    nonisolated static let contextReach = 200.0
    /// Longest side of the context region, so one large drawing can't shrink the image too much.
    nonisolated static let maxContextSide = 1_600.0

    init(document: AskAIDocument, region: @escaping () -> CGRect,
         selection: @escaping () -> CGRect? = { nil },
         autoAsk: @escaping () -> AutoAskSettings = { AutoAskSettings.load() },
         provider: @escaping () -> (any AIProvider, String) = AskAIController.configuredProvider,
         blocked: @escaping () -> String? = AskAIController.configuredBlockedReason,
         schema: Data? = AskAIController.bundledSchema, now: @escaping () -> Date = Date.init) {
        self.document = document
        self.region = region
        self.selection = selection
        self.autoAsk = autoAsk
        inkWatermark = Self.latestStrokeDate(in: document.snapshot.drawing) ?? .distantPast
        self.provider = provider
        self.blocked = blocked
        self.schema = schema
        self.now = now
    }

    /// The provider and model selected in AI Settings (ticket 012).
    nonisolated static func configuredProvider() -> (any AIProvider, String) {
#if DEBUG
        if AgentChatFixtureProvider.isEnabled { return (AgentChatFixtureProvider(), "fixture-vision") }
#endif
        let settings = AISettings.load()
        let model = settings.settings(for: settings.selectedPresetID).model
        guard let preset = try? settings.resolvedPreset(for: settings.selectedPresetID) else {
            return (UnconfiguredProvider(), model)
        }
        return (ProviderFactory.make(preset), model)
    }

    nonisolated static func configuredBlockedReason() -> String? {
#if DEBUG
        if AgentChatFixtureProvider.isEnabled { return nil }
#endif
        return AISettings.load().askAIBlockedReason
    }

    nonisolated static var bundledSchema: Data? {
        Bundle.main.url(forResource: "canvas-commands-v1", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }

    var isPending: Bool { if case .pending = phase { true } else { false } }
    /// Why Ask AI is unavailable with the current settings, such as a model without vision.
    var blockedReason: String? { blocked() }
    var canAsk: Bool { !document.isReadOnly && !isPending && blockedReason == nil }

    // MARK: - Actions

    func ask() {
        guard canAsk else { return }
        autoTask?.cancel()
        autoTask = nil
        let newest = newestInkRegion
        // A lasso selection is the exclusive context. Newest ink gets the earlier work
        // around it as context (ticket 017); the viewport fallback is already wide.
        let focus: CGRect, withContext: Bool
        if let selected = selection() {
            (focus, withContext) = (selected, false)
        } else if let ink = newest ?? lastInkRegion.flatMap({ hasInk(in: $0) ? $0 : nil }) {
            (focus, withContext) = (ink, true)
        } else {
            (focus, withContext) = (region(), false)
        }
        guard let capture = makeCapture(documentRegion: focus, withContext: withContext) else {
            phase = .idle
            return
        }
        if let newest {
            lastInkRegion = newest
            inkWatermark = Self.latestStrokeDate(in: document.snapshot.drawing) ?? inkWatermark
        }
        send(capture)
    }

    // MARK: - Auto Ask (ticket 014)

    /// Any tool started: the user is still working, so wait for the next pause.
    func toolBegan() {
        autoTask?.cancel()
        autoTask = nil
    }

    /// A tool gesture ended. Only ink starts the pause timer; each new stroke restarts it.
    func toolEnded(inked: Bool) {
        autoTask?.cancel()
        autoTask = nil
        let settings = autoAsk()
        guard inked, settings.enabled, !autoAskSuspended else { return }
        autoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(settings.delaySeconds))
            guard !Task.isCancelled, let self else { return }
            autoTask = nil
            autoAskNow()
        }
    }

    /// The pause timer fired. Asks only about new ink, never over a selection or a
    /// held answer; a pending request re-arms the timer so the new ink is asked next.
    func autoAskNow() {
        guard !autoAskSuspended, autoAsk().enabled, !document.isReadOnly, blockedReason == nil,
              selection() == nil, newestInkRegion != nil else { return }
        switch phase {
        case .review: return
        case .pending: toolEnded(inked: true)
        case .idle, .failed: ask()
        }
    }

    var isAutoAskScheduled: Bool { autoTask != nil }

    /// Bounds of the strokes created since the last newest-ink capture, plus the margin.
    var newestInkRegion: CGRect? {
        // AI and draft ink is dated in the first day of 1970, so it is never the newest ink.
        let strokes = document.snapshot.drawing.strokes.filter { $0.path.creationDate > inkWatermark && !DraftMarker.isSynthetic($0.path.creationDate) }
        guard let first = strokes.first else { return nil }
        let bounds = strokes.dropFirst().reduce(first.renderBounds) { $0.union($1.renderBounds) }
        return bounds.insetBy(dx: -Self.captureMargin, dy: -Self.captureMargin)
    }

    private func hasInk(in documentRegion: CGRect) -> Bool {
        document.snapshot.drawing.strokes.contains { $0.renderBounds.intersects(documentRegion) }
    }

    nonisolated static func latestStrokeDate(in drawing: PKDrawing) -> Date? {
        drawing.strokes.map(\.path.creationDate).max()
    }

    /// Manual retry of the last failed request: same capture, same request ID.
    func retry() {
        guard case .failed(let capture, _) = phase, !document.isReadOnly else { return }
        send(capture)
    }

    /// Discards any late response.
    func cancel() {
        autoTask?.cancel()
        autoTask = nil
        generation += 1
        task?.cancel()
        task = nil
        phase = .idle
    }

    func dismiss() {
        if case .pending = phase { return }
        phase = .idle
    }

    /// Review card "Place": re-check geometry and scope against the current page, then apply.
    func placeAnyway() {
        guard case .review(let capture, let operations) = phase else { return }
        let raw = Self.encode(operations)
        let state = validationState(for: capture, ignoringScopeChange: true)
        switch CommandValidator.validate(raw, context: capture.context, state: state) {
        case .valid(let checked): apply(checked, capture: capture, message: nil)
        case .duplicate: phase = .idle
        case .needsReview: phase = .failed(capture, "The answer no longer fits this page. Retry to ask again.")
        case .invalid: phase = .failed(capture, "The answer no longer fits this page. Retry to ask again.")
        }
    }

    // MARK: - Capture

    /// Clips the region to the page under its center and renders it. With `withContext`,
    /// the region is the focus and the image also shows the earlier work around it.
    func makeCapture(documentRegion: CGRect, withContext: Bool = false) -> AskAICapture? {
        let layout = document.layout, snapshot = document.snapshot
        guard !snapshot.pages.isEmpty, documentRegion.width > 0, documentRegion.height > 0 else { return nil }
        let index = layout.pageIndex(nearestY: documentRegion.midY)
        let pageDocument = layout.pageRect(index)
        let focus = documentRegion.intersection(pageDocument)
        guard !focus.isNull, focus.width >= 8, focus.height >= 8 else { return nil }
        let page = snapshot.pages[index]
        var clipped = focus
        if withContext {
            let content = snapshot.drawing.strokes.map(\.renderBounds).filter { $0.intersects(pageDocument) }
                + snapshot.objects.filter { $0.pageId == page.id }.map(layout.documentFrame(of:))
            clipped = Self.contextRegion(around: focus, within: pageDocument, content: content)
        }
        let scope = clipped.offsetBy(dx: -pageDocument.minX, dy: -pageDocument.minY)
        let focusScope = focus.offsetBy(dx: -pageDocument.minX, dy: -pageDocument.minY)
        let scale = min(2, Self.maxImageSide / max(scope.width, scope.height))
        let scopeObjects = snapshot.objects.filter { $0.pageId == page.id && Self.rect($0.frame).intersects(scope) }
        let context = CommandRequestContext(
            requestId: UUID(), documentId: document.documentId, pageId: page.id,
            capturedRevision: document.revision, scopeFrame: Self.frame(scope),
            scopeObjectIds: Set(scopeObjects.map(\.id)),
            pageBounds: CommandFrame(x: 0, y: 0, width: page.size.width, height: page.size.height),
            allowReplace: false)
        let png = RegionCapture.render(drawing: snapshot.drawing, documentRect: clipped,
                                       objects: scopeObjects, pageOrigin: pageDocument.origin, scale: scale, assetsURL: document.captureAssetsURL)
        let magnification = withContext ? Self.focusImageScale(focus: focus, context: clipped, contextScale: scale) : nil
        var focusPNG: Data?
        if let magnification {
            let rendered = RegionCapture.render(drawing: snapshot.drawing, documentRect: focus,
                                                objects: scopeObjects, pageOrigin: pageDocument.origin, scale: magnification, assetsURL: document.captureAssetsURL)
            if rendered.count <= 5_000_000 { focusPNG = rendered }
        }
        let fingerprint = ScopeFingerprint.make(strokes: snapshot.drawing.strokes, objects: snapshot.objects,
                                                pageId: page.id, scope: focusScope, pageOrigin: pageDocument.origin)
        return AskAICapture(context: context, focusFrame: Self.frame(focusScope), instruction: instruction, png: png,
                            imageScale: scale, focusPNG: focusPNG, focusImageScale: focusPNG == nil ? nil : magnification,
                            fingerprint: fingerprint)
    }

    /// A second image, up to 3×, when the newest input is less than half the capture's longest side.
    nonisolated static func focusImageScale(focus: CGRect, context: CGRect, contextScale: Double) -> Double? {
        let focusLong = max(focus.width, focus.height)
        let contextLong = max(context.width, context.height)
        guard focusLong >= 8, contextLong > focusLong * 2 else { return nil }
        let magnified = min(3, maxImageSide / focusLong)
        guard magnified > contextScale + 0.05 else { return nil }
        return magnified
    }

    /// The focus plus every stroke or object frame that comes within `contextReach`
    /// (or half the focus size) of it, with the capture margin, at most
    /// `maxContextSide` per side around the focus, inside `page`. Document space.
    nonisolated static func contextRegion(around focus: CGRect, within page: CGRect, content: [CGRect]) -> CGRect {
        let reach = max(contextReach, max(focus.width, focus.height) / 2)
        let near = focus.insetBy(dx: -reach, dy: -reach)
        let grown = content.filter { $0.intersects(near) }.reduce(focus) { $0.union($1) }
            .insetBy(dx: -captureMargin, dy: -captureMargin)
        func span(_ low: CGFloat, _ high: CGFloat, keeping focusLow: CGFloat, _ focusHigh: CGFloat) -> (CGFloat, CGFloat) {
            guard high - low > maxContextSide else { return (low, high) }
            guard focusHigh - focusLow < maxContextSide else { return (focusLow, focusHigh) }
            let start = min(max((focusLow + focusHigh) / 2 - maxContextSide / 2, low), high - maxContextSide)
            return (start, start + maxContextSide)
        }
        let x = span(grown.minX, grown.maxX, keeping: focus.minX, focus.maxX)
        let y = span(grown.minY, grown.maxY, keeping: focus.minY, focus.maxY)
        return CGRect(x: x.0, y: y.0, width: x.1 - x.0, height: y.1 - y.0).intersection(page).union(focus)
    }

    // MARK: - Request

    private func send(_ capture: AskAICapture) {
        generation += 1
        let current = generation
        task?.cancel()
        phase = .pending(capture)
        let (provider, model) = provider()
        guard provider.capabilities(model: model)?.vision == true else {
            phase = .failed(capture, AIError.modelLacksVision.localizedDescription)
            return
        }
        let request = AIRequest(requestId: capture.context.requestId, model: model,
                                systemPrompt: CanvasCommandPrompt.system,
                                instruction: CanvasCommandPrompt.instruction(capture.instruction, context: capture.context,
                                                                             imageScale: capture.imageScale,
                                                                             focusFrame: capture.focusFrame,
                                                                             focusImageScale: capture.focusPNG == nil ? nil : capture.focusImageScale),
                                pngImages: capture.focusPNG.map { [capture.png, $0] } ?? [capture.png], jsonSchema: schema,
                                reasoning: AISettings.load().settings(for: AISettings.load().selectedPresetID).reasoning)
        task = Task { [weak self] in
            var text: String?
            var failure: AIError?
            do {
                for try await event in provider.send(request) {
                    if case .completed(let final) = event { text = final }
                }
                if text == nil { failure = .invalidOutput }
            } catch {
                failure = AIError.normalized(error)
            }
            guard let self, current == generation, !Task.isCancelled else { return }
            task = nil
            if let failure {
                phase = failure == .cancelled ? .idle : .failed(capture, failure.localizedDescription)
            } else if let text {
                receive(text, capture: capture)
            }
        }
    }

    /// Validates a completed response and applies it, holds it for review, or reports failure.
    func receive(_ text: String, capture: AskAICapture) {
        let raw = Data(CanvasCommandPrompt.stripCodeFence(text).utf8)
        switch CommandValidator.validate(raw, context: capture.context, state: validationState(for: capture)) {
        case .valid(let operations):
            apply(operations, capture: capture, message: Self.message(in: raw))
        case .needsReview(let operations, _):
            phase = .review(capture, operations)
        case .duplicate:
            phase = .idle
        case .invalid:
            phase = .failed(capture, "The answer couldn't be used. Nothing was changed. Retry to ask again.")
        }
    }

    func validationState(for capture: AskAICapture, ignoringScopeChange: Bool = false) -> DocumentValidationState {
        let snapshot = document.snapshot, layout = document.layout
        let pageIndex = layout.pageIndex(of: capture.context.pageId)
        let changed: Bool
        if ignoringScopeChange { changed = false }
        else if let pageIndex {
            changed = ScopeFingerprint.make(strokes: snapshot.drawing.strokes, objects: snapshot.objects,
                                            pageId: capture.context.pageId, scope: Self.rect(capture.focusFrame),
                                            pageOrigin: layout.pageRect(pageIndex).origin) != capture.fingerprint
        } else { changed = true }
        // Staleness needs a changed revision *and* a changed scope, so `placeAnyway`
        // overrides it by reporting the scope as unchanged.
        return DocumentValidationState(
            currentRevision: document.revision, scopeChanged: changed,
            existingObjectIds: Set(snapshot.objects.filter { $0.pageId == capture.context.pageId }.map(\.id)),
            appliedRequestIds: Set(document.conversation.appliedRequests.map(\.requestId)))
    }

    // MARK: - Apply

    private func apply(_ operations: [CanvasOperation], capture: AskAICapture, message: String?) {
        guard !document.isReadOnly else {
            phase = .failed(capture, "This document is read-only, so the answer wasn't placed.")
            return
        }
        guard let next = AnswerApplier.apply(operations, to: document.snapshot, layout: document.layout,
                                             capture: capture, date: now()) else {
            phase = .failed(capture, "There's no room for the answer on this page. Make space and retry.")
            return
        }
        let conversation = document.conversation.recordingAnswer(
            requestId: capture.context.requestId, instruction: capture.instruction, message: message, at: now())
        document.applyAIAnswer(next, conversation: conversation, named: "AI Answer")
        hasPlacedAnswer = true
        phase = .idle
    }

    // MARK: - Helpers

    nonisolated static func rect(_ frame: PageRect) -> CGRect { CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height) }
    nonisolated static func rect(_ frame: CommandFrame) -> CGRect { CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height) }
    nonisolated static func frame(_ rect: CGRect) -> CommandFrame {
        CommandFrame(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    nonisolated private static func message(in raw: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: raw)) as? [String: Any])?["message"] as? String
    }

    /// Re-encodes validated operations so `placeAnyway` can re-run the validator.
    nonisolated static func encode(_ operations: [CanvasOperation]) -> Data {
        let items: [[String: Any]] = operations.map { operation in
            switch operation {
            case .addObject(let type, let source, let placement, let frame):
                let frameValue: Any = frame.map { ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height] } ?? NSNull()
                return ["op": "add_object", "type": type.rawValue, "source": source,
                        "placement": placement.rawValue, "frame": frameValue]
            case .editObject(let id, let source):
                return ["op": "edit_object", "objectId": id.uuidString, "source": source]
            case .deleteObject(let id):
                return ["op": "delete_object", "objectId": id.uuidString]
            case .drawInk(let drawing, let placement, let frame):
                let frameValue: Any = frame.map { ["x": $0.x, "y": $0.y, "width": $0.width, "height": $0.height] } ?? NSNull()
                let strokes: [[String: Any]] = drawing.strokes.map { stroke in
                    var object: [String: Any] = [
                        "kind": stroke.kind.rawValue, "points": stroke.points.map { [$0.x, $0.y] },
                        "closed": stroke.closed, "color": stroke.color.rawValue, "size": stroke.size,
                    ]
                    if stroke.arrow != .none { object["arrow"] = stroke.arrow.rawValue }
                    if stroke.fill { object["fill"] = true }
                    if let amplitude = stroke.amplitude { object["amplitude"] = amplitude }
                    if let wavelength = stroke.wavelength { object["wavelength"] = wavelength }
                    if let center = stroke.center { object["center"] = [center.x, center.y] }
                    if let radiusX = stroke.radiusX { object["radiusX"] = radiusX }
                    if let radiusY = stroke.radiusY { object["radiusY"] = radiusY }
                    if let start = stroke.startAngle { object["startAngle"] = start }
                    if let sweep = stroke.sweep { object["sweep"] = sweep }
                    return object
                }
                var operation: [String: Any] = [
                    "op": "draw_ink",
                    "width": drawing.coordinates == .page ? NSNull() : drawing.width,
                    "height": drawing.coordinates == .page ? NSNull() : drawing.height,
                    "strokes": strokes, "placement": placement.rawValue, "frame": frameValue,
                ]
                if drawing.coordinates == .page { operation["coordinates"] = "page" }
                if !drawing.labels.isEmpty {
                    operation["labels"] = drawing.labels.map {
                        ["kind": $0.kind.rawValue, "text": $0.text, "x": $0.at.x, "y": $0.at.y]
                    }
                }
                return operation
            }
        }
        let diagram = operations.contains { operation in
            guard case .drawInk(let drawing, _, _) = operation else { return false }
            if drawing.coordinates != .local || !drawing.labels.isEmpty { return true }
            return drawing.strokes.contains { stroke in
                switch stroke.kind {
                case .line, .polyline, .smooth, .ellipse: stroke.arrow != .none || stroke.fill
                default: true
                }
            }
        }
        let version = diagram ? 3 : 2
        return (try? JSONSerialization.data(withJSONObject: ["version": version, "operations": items, "message": NSNull()])) ?? Data()
    }
}

/// Turns validated operations into the next editor snapshot (ticket 010 "Place" and "Apply").
@MainActor
enum AnswerApplier {
    static let newPageMargin = 40.0

    /// Nil when the answer can't be placed without overlapping the user's work.
    static func apply(_ operations: [CanvasOperation], to snapshot: EditorSnapshot, layout: EditorLayout,
                      capture: AskAICapture, date: Date) -> EditorSnapshot? {
        guard var pageIndex = layout.pageIndex(of: capture.context.pageId) else { return nil }
        var next = snapshot
        // Flowing answers go beside the newest input, not beside the whole context image.
        let scope = AskAIController.rect(capture.focusFrame)
        var zIndex = (snapshot.objects.map(\.zIndex).max() ?? -1) + 1
        func makeObject(_ type: CanvasObjectType, _ source: String, _ frame: CGRect, page: Int) -> DocumentObject {
            defer { zIndex += 1 }
            return DocumentObject(id: UUID(), pageId: next.pages[page].id, type: ObjectType(rawValue: type.rawValue)!,
                                  frame: PageRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
                                  zIndex: zIndex, source: source, assetRefs: [],
                                  createdBy: .ai(requestId: capture.context.requestId), createdAt: date, updatedAt: date,
                                  aiAppearance: CanvasAISettings.load().appearance)
        }

        enum Flowing { case object(CanvasObjectType, String), ink(InkDrawing) }
        var flowing: [Flowing] = []
        var preferBelow = false
        func addInk(_ drawing: InkDrawing, in frame: CGRect, page: Int) {
            let pageOrigin = EditorLayout(type: layout.type, pages: next.pages).pageRect(page).origin
            var drawing = drawing
            let color = CanvasAISettings.load().appearance.ink.rawValue
            for index in drawing.strokes.indices {
                drawing.strokes[index].color = InkStrokeSpec.Color(rawValue: color) ?? .blue
            }
            if drawing.coordinates == .page {
                next.drawing.strokes.append(contentsOf: InkAnswer.pageStrokes(drawing, pageOrigin: pageOrigin))
                for label in drawing.labels {
                    let placed = labelFrame(label, at: CGPoint(x: label.at.x, y: label.at.y), page: page)
                    next.objects.append(makeObject(label.kind == .latex ? .latex : .text, label.text, placed, page: page))
                }
            } else {
                let documentFrame = frame.offsetBy(dx: pageOrigin.x, dy: pageOrigin.y)
                next.drawing.strokes.append(contentsOf: InkAnswer.strokes(drawing, in: documentFrame))
                let fitted = InkAnswer.fit(drawing, in: documentFrame)
                for label in drawing.labels {
                    let point = CGPoint(x: fitted.origin.x + label.at.x * fitted.scale - pageOrigin.x,
                                        y: fitted.origin.y + label.at.y * fitted.scale - pageOrigin.y)
                    next.objects.append(makeObject(label.kind == .latex ? .latex : .text, label.text,
                                                   labelFrame(label, at: point, page: page), page: page))
                }
            }
        }
        func labelFrame(_ label: InkLabel, at point: CGPoint, page: Int) -> CGRect {
            let type = label.kind == .latex ? ObjectType.latex : ObjectType.text
            let pageSize = next.pages[page].size
            var width = RichTextRenderer.fittingWidth(source: label.text, type: type, maxWidth: 160, handwritten: label.kind == .text)
            width = min(max(width, 16), pageSize.width)
            var height = RichTextRenderer.height(source: label.text, type: type, width: width, handwritten: label.kind == .text)
            if height < 8 { height = 8 }
            let x = min(max(0, point.x), max(0, pageSize.width - width))
            let y = min(max(0, point.y - height / 2), max(0, pageSize.height - height))
            return CGRect(x: x, y: y, width: width, height: height)
        }
        for operation in operations {
            switch operation {
            case .addObject(let type, let source, let placement, let frame):
                let occupied = occupiedRects(next, layout: EditorLayout(type: layout.type, pages: next.pages), page: pageIndex)
                var measured = frame.map(AskAIController.rect)
                if let requested = measured {
                    measured = measuredFrame(type, source, requested)
                }
                let pageBounds = CGRect(origin: .zero, size: CGSize(width: next.pages[pageIndex].size.width, height: next.pages[pageIndex].size.height))
                if placement == .atFrame, let measured, pageBounds.contains(measured), !occupied.contains(where: { $0.intersects(measured) }) {
                    next.objects.append(makeObject(type, source, measured, page: pageIndex))
                } else {
                    if flowing.isEmpty { preferBelow = placement == .belowScope }
                    flowing.append(.object(type, source))
                }
            case .drawInk(let drawing, let placement, let frame):
                // Page points are already where they belong. An exact frame may overlap
                // existing ink, for annotations such as a circle around a term.
                if drawing.coordinates == .page {
                    addInk(drawing, in: .zero, page: pageIndex)
                } else if placement == .atFrame, let frame {
                    addInk(drawing, in: AskAIController.rect(frame), page: pageIndex)
                } else {
                    if flowing.isEmpty { preferBelow = placement == .belowScope }
                    flowing.append(.ink(drawing))
                }
            case .editObject(let id, let source):
                if let index = next.objects.firstIndex(where: { $0.id == id }) {
                    next.objects[index].source = source
                    next.objects[index].updatedAt = date
                }
            case .deleteObject(let id):
                next.objects.removeAll { $0.id == id }
            }
        }
        guard !flowing.isEmpty else { return next }

        // Place the remaining objects as one column: next to the scope, then
        // (canvas) grow the page or (notebook) use the following page.
        var page = CGRect(origin: .zero, size: CGSize(width: next.pages[pageIndex].size.width,
                                                      height: next.pages[pageIndex].size.height))
        let sizes = flowing.map { item -> CGSize in
            guard case .object(let type, let source) = item else {
                if case .ink(let drawing) = item { return InkAnswer.naturalSize(drawing, pageWidth: page.width) }
                return .zero
            }
            var size = AnswerPlacement.size(type: type, source: source, scope: scope, pageWidth: page.width)
            let objectType = ObjectType(rawValue: type.rawValue)!
            if type == .text {
                size.width = RichTextRenderer.fittingWidth(source: source, type: objectType, maxWidth: size.width, handwritten: true)
            }
            size.height = RichTextRenderer.height(source: source, type: objectType, width: size.width, handwritten: true)
            return size
        }
        let block = AnswerPlacement.blockSize(sizes)
        var occupied = occupiedRects(next, layout: EditorLayout(type: layout.type, pages: next.pages), page: pageIndex)
        var origin: CGPoint?
        if let rect = AnswerPlacement.freeRect(size: block, scope: scope, page: page, occupied: occupied, preferBelow: preferBelow) {
            origin = rect.origin
        } else if layout.type == .canvas {
            let bottom = max(scope.maxY, occupied.map(\.maxY).max() ?? 0) + AnswerPlacement.gap
            let x = min(max(0, scope.minX), max(0, page.width - block.width))
            let needed = PageSize(width: max(page.width, x + block.width), height: bottom + block.height + AnswerPlacement.gap)
            guard needed.width <= DocumentLimits.maxCanvasSide, needed.height <= DocumentLimits.maxCanvasSide else { return nil }
            next.pages[pageIndex].size = needed
            origin = CGPoint(x: x, y: bottom)
        } else {
            // Notebook: the top of the next page, adding a page when this is the last one.
            pageIndex += 1
            if pageIndex == next.pages.count {
                guard next.pages.count < DocumentLimits.maxNotebookPages else { return nil }
                next.pages.append(Page(id: UUID(), size: DocumentSchema.a4, background: next.pages[pageIndex - 1].background))
            }
            page = CGRect(origin: .zero, size: CGSize(width: next.pages[pageIndex].size.width,
                                                      height: next.pages[pageIndex].size.height))
            occupied = occupiedRects(next, layout: EditorLayout(type: layout.type, pages: next.pages), page: pageIndex)
            let top = CGRect(x: newPageMargin, y: newPageMargin, width: 0, height: 0)
            origin = AnswerPlacement.freeRect(size: block, scope: top.offsetBy(dx: 0, dy: -AnswerPlacement.gap),
                                              page: page, occupied: occupied, preferBelow: true)?.origin
        }
        guard let origin else { return nil }
        for (frame, item) in zip(AnswerPlacement.stack(sizes, in: CGRect(origin: origin, size: block)), flowing) {
            switch item {
            case .object(let type, let source): next.objects.append(makeObject(type, source, frame, page: pageIndex))
            case .ink(let drawing): addInk(drawing, in: frame, page: pageIndex)
            }
        }
        return next
    }

    /// The handwritten size of an `at_frame` answer: at least the requested width (text
    /// grows to fit), the measured height, and the same vertical center as requested,
    /// so an answer after "=" stays on that line.
    static func measuredFrame(_ type: CanvasObjectType, _ source: String, _ requested: CGRect) -> CGRect {
        let objectType = ObjectType(rawValue: type.rawValue)!
        var width = requested.width
        if type == .text {
            width = max(width, RichTextRenderer.fittingWidth(source: source, type: objectType,
                                                             maxWidth: AnswerPlacement.maxWidth, handwritten: true))
        }
        let height = RichTextRenderer.height(source: source, type: objectType, width: width, handwritten: true)
        let y = type == .text ? requested.midY - height / 2 : requested.minY
        return CGRect(x: requested.minX, y: y, width: width, height: height)
    }

    /// Ink and object bounds on one page, in page points.
    static func occupiedRects(_ snapshot: EditorSnapshot, layout: EditorLayout, page index: Int) -> [CGRect] {
        let pageRect = layout.pageRect(index), pageId = snapshot.pages[index].id
        let ink = snapshot.drawing.strokes.map(\.renderBounds).filter { $0.intersects(pageRect) }
            .map { $0.offsetBy(dx: -pageRect.minX, dy: -pageRect.minY) }
        let objects = snapshot.objects.filter { $0.pageId == pageId }.map { AskAIController.rect($0.frame) }
        return ink + objects
    }
}

/// Turns a validated `draw_ink` answer into PencilKit strokes (ticket 016), so the
/// drawing can be erased, moved and recolored like the user's own ink.
@MainActor
enum InkAnswer {
    static let minSide = 160.0
    static let maxSide = 360.0
    /// AI ink is never the user's newest ink, so Auto Ask doesn't ask about its own answer.
    static let creationDate = Date(timeIntervalSince1970: 0)

    static func color(_ color: InkStrokeSpec.Color) -> UIColor {
        switch color {
        case .black: UIColor(white: 0.1, alpha: 1)
        case .gray: UIColor(white: 0.5, alpha: 1)
        case .blue: RichTextRenderer.handwrittenInk
        case .red: UIColor(red: 0.82, green: 0.16, blue: 0.14, alpha: 1)
        case .green: UIColor(red: 0.12, green: 0.55, blue: 0.24, alpha: 1)
        case .orange: UIColor(red: 0.95, green: 0.52, blue: 0.10, alpha: 1)
        case .purple: UIColor(red: 0.48, green: 0.24, blue: 0.70, alpha: 1)
        case .brown: UIColor(red: 0.52, green: 0.33, blue: 0.18, alpha: 1)
        case .yellow: UIColor(red: 0.95, green: 0.78, blue: 0.10, alpha: 1)
        case .pink: UIColor(red: 0.93, green: 0.45, blue: 0.62, alpha: 1)
        }
    }

    /// The drawing's size on the page: its longest side between 160 and 360 points.
    static func naturalSize(_ drawing: InkDrawing, pageWidth: Double) -> CGSize {
        let longest = max(drawing.width, drawing.height)
        let target = min(max(longest, minSide), maxSide, max(minSide, pageWidth - AnswerPlacement.gap * 2))
        let scale = target / longest
        return CGSize(width: drawing.width * scale, height: drawing.height * scale)
    }

    /// How a local drawing sits inside `rect`: uniform scale, aspect kept, centered.
    static func fit(_ drawing: InkDrawing, in rect: CGRect) -> (scale: CGFloat, origin: CGPoint) {
        let scale = min(rect.width / drawing.width, rect.height / drawing.height)
        let origin = CGPoint(x: rect.midX - drawing.width * scale / 2, y: rect.midY - drawing.height * scale / 2)
        return (scale, origin)
    }

    /// Strokes in document space, fitted into `rect` with the drawing's aspect ratio kept.
    static func strokes(_ drawing: InkDrawing, in rect: CGRect) -> [PKStroke] {
        let fitted = fit(drawing, in: rect)
        return render(drawing, scale: fitted.scale, origin: fitted.origin)
    }

    /// Page-coordinate ink is already in page points. `pageOrigin` moves it into document space.
    static func pageStrokes(_ drawing: InkDrawing, pageOrigin: CGPoint) -> [PKStroke] {
        render(drawing, scale: 1, origin: pageOrigin)
    }

    /// Sample points of the centerline. Straight segments are densified so PencilKit's
    /// spline stays close to the corners; `smooth` is a Catmull-Rom curve through the points.
    static func path(_ spec: InkStrokeSpec) -> [CGPoint] {
        (InkGeometry.outline(spec) ?? []).map { CGPoint(x: $0.x, y: $0.y) }
    }

    private static func render(_ drawing: InkDrawing, scale: CGFloat, origin: CGPoint) -> [PKStroke] {
        drawing.strokes.flatMap { spec in
            polylines(spec).map { points in
                let controls = points.enumerated().map { index, point in
                    PKStrokePoint(location: CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale),
                                  timeOffset: Double(index) / 120, size: CGSize(width: spec.size, height: spec.size),
                                  opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                return PKStroke(ink: PKInk(.pen, color: color(spec.color)),
                                path: PKStrokePath(controlPoints: controls, creationDate: creationDate))
            }
        }
    }

    /// Centerline, then arrowheads, then fill chords. Each entry is one PencilKit stroke.
    static func polylines(_ spec: InkStrokeSpec) -> [[CGPoint]] {
        var lines: [[CGPoint]] = []
        let centerline = path(spec)
        if centerline.count >= 2 { lines.append(centerline) }
        let marks = InkGeometry.decorations(spec)
        for stroke in marks.arrows + marks.fill {
            let points = stroke.map { CGPoint(x: $0.x, y: $0.y) }
            guard points.count >= 2 else { continue }
            lines.append(points)
        }
        return lines
    }
}

/// Renders the captured region to PNG: white background, objects, then ink above them.
@MainActor
enum RegionCapture {
    static func render(drawing: PKDrawing, documentRect: CGRect, objects: [DocumentObject],
                       pageOrigin: CGPoint, scale: Double, assetsURL: URL? = nil) -> Data {
        let size = CGSize(width: (documentRect.width * scale).rounded(.up), height: (documentRect.height * scale).rounded(.up))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: -documentRect.minX, y: -documentRect.minY)
            for object in objects.sorted(by: { $0.zIndex < $1.zIndex }) {
                let rect = AskAIController.rect(object.frame).offsetBy(dx: pageOrigin.x, dy: pageOrigin.y)
                if object.type == .image {
                    if let name = object.assetRefs.first, AssetName.isValid(name), let assetsURL {
                        UIImage(contentsOfFile: assetsURL.appendingPathComponent(name).path)?.draw(in: rect)
                    }
                } else {
                    RichTextRenderer.draw(source: object.source, type: object.type, in: rect, density: scale,
                                          handwritten: object.rendersHandwritten, appearance: object.aiAppearance)
                }
            }
            // Dark ink regardless of appearance, so dark-mode white ink stays visible on white.
            var image = UIImage()
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = drawing.image(from: documentRect, scale: scale)
            }
            image.draw(in: documentRect)
        }
    }
}
