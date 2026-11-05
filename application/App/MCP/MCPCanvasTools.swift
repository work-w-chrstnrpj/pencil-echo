import Foundation
import PencilKit
import UIKit

/// A document Claude Code may work on (ticket 023). `EditorSession` conforms.
@MainActor
protocol MCPDraftDocument: AskAIDocument {
    var title: String { get }
    /// One undo step. Records `requestId` so the same capture can't be placed twice.
    func applyExternalDrafts(_ next: EditorSnapshot, requestId: UUID)
}

/// The open editor while "Share with Claude Code" is on.
@MainActor
protocol MCPShareTarget: AnyObject {
    var shareDocument: any MCPDraftDocument { get }
    func visibleRegion() -> CGRect
    func selectionRegion() -> CGRect?
}

/// Marks everything an answer added as a draft (ticket 021): new objects get
/// `isDraft`, new ink gets one creation date of its own recorded in `draftInk`.
enum DraftMarker {
    /// AI ink is dated in the first day of 1970: answers at 0, draft batches from 60 s.
    /// PencilKit's canvas doesn't draw strokes dated before 1970, so dates stay positive.
    static let syntheticLimit = Date(timeIntervalSince1970: 86_400)

    /// AI or draft ink, never the user's own writing.
    static func isSynthetic(_ date: Date) -> Bool { date < syntheticLimit }

    static func mark(_ next: inout EditorSnapshot, comparedTo original: EditorSnapshot, requestId: UUID) {
        let originalIds = Set(original.objects.map(\.id))
        for index in next.objects.indices where !originalIds.contains(next.objects[index].id) {
            next.objects[index].isDraft = true
        }
        guard next.drawing.strokes.count > original.drawing.strokes.count else { return }
        let used = next.drawing.strokes.map { $0.path.creationDate.timeIntervalSince1970 }.filter { $0 >= 60 && $0 < 86_000 }
        let marker = Date(timeIntervalSince1970: (used.max() ?? 59) + 1)
        for index in original.drawing.strokes.count..<next.drawing.strokes.count {
            let stroke = next.drawing.strokes[index]
            next.drawing.strokes[index] = PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: Array(stroke.path), creationDate: marker),
                                                   transform: stroke.transform, mask: stroke.mask)
        }
        next.draftInk.append(DraftInkBatch(requestId: requestId, strokeDate: marker))
    }
}

/// JSON-RPC methods for the MCP server. Tool work is delegated to `MCPCanvasTools`.
@MainActor
final class MCPDispatcher {
    static let maxCallsPerMinute = 30
    let tools: MCPCanvasTools
    private let now: () -> Date
    private var recentCalls: [Date] = []

    init(tools: MCPCanvasTools, now: @escaping () -> Date = Date.init) {
        self.tools = tools
        self.now = now
    }

    func handle(line: Data) async -> Data? {
        guard let message = MCPWire.decode(line) else {
            return MCPWire.encode(MCPWire.error(id: nil, code: -32700, message: "Parse error"))
        }
        return await handle(message).flatMap(MCPWire.encode)
    }

    func handle(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        let isRequest = id != nil && !(id is NSNull)
        guard message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
            // Responses from the client and malformed notifications need no reply.
            return isRequest && message["result"] == nil && message["error"] == nil
                ? MCPWire.error(id: id, code: -32600, message: "Invalid request") : nil
        }
        guard isRequest else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return MCPWire.result(id: id, MCPCatalog.initializeResult(version: params["protocolVersion"] as? String ?? ""))
        case "ping":
            return MCPWire.result(id: id, [:])
        case "tools/list":
            return MCPWire.result(id: id, ["tools": MCPCatalog.tools(answerSchema: tools.answerSchema)])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return MCPWire.error(id: id, code: -32602, message: "Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let date = now()
            recentCalls.removeAll { date.timeIntervalSince($0) >= 60 }
            guard recentCalls.count < Self.maxCallsPerMinute else {
                return MCPWire.result(id: id, MCPWire.toolError("Too many Pencil Echo requests. Wait a minute and try again."))
            }
            recentCalls.append(date)
            return MCPWire.result(id: id, await tools.call(name, arguments: arguments))
        default:
            return MCPWire.error(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }
}

/// The four tools (ticket 023). Captures and placement use the same code as Ask AI
/// (017/019) and the same validator; answers become drafts (021).
@MainActor
final class MCPCanvasTools {
    static let maxImageBytes = 3 * 1024 * 1024
    static let keptCaptures = 8

    weak var target: MCPShareTarget? {
        didSet { if target !== oldValue { resetForTarget() } }
    }
    /// A short line for the iPad banner, such as "Captured newest ink".
    var onActivity: (String) -> Void = { _ in }

    private var controller: AskAIController?
    private var captures: [(id: String, capture: AskAICapture)] = []
    /// Strokes after this date are "newest". It starts when sharing starts.
    private var watermark = Date.distantPast
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    lazy var answerSchema: [String: Any]? = AskAIController.bundledSchema
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

    private func resetForTarget() {
        captures = []
        controller = target.map { target in
            AskAIController(document: target.shareDocument, region: { [weak target] in target?.visibleRegion() ?? .zero },
                            selection: { [weak target] in target?.selectionRegion() })
        }
        watermark = target.flatMap { AskAIController.latestStrokeDate(in: $0.shareDocument.snapshot.drawing) } ?? .distantPast
    }

    func call(_ name: String, arguments: [String: Any]) async -> [String: Any] {
        switch name {
        case MCPCatalog.status: return status()
        case MCPCatalog.instructions: return instructions()
        case MCPCatalog.capture: return capture(arguments)
        case MCPCatalog.place: return place(arguments)
        default: return MCPWire.toolError("Unknown tool \(name).")
        }
    }

    // MARK: - Tools

    private static let notShared = "No Pencil Echo document is shared. Ask the user to open a document on the iPad and turn on Share with Claude Code."

    func status() -> [String: Any] {
        guard let document = target?.shareDocument else { return MCPWire.toolError(Self.notShared) }
        let info: [String: Any] = [
            "title": document.title,
            "type": document.layout.type == .canvas ? "canvas" : "notebook",
            "pages": document.snapshot.pages.count,
            "revision": document.revision,
            "readOnly": document.isReadOnly,
            "hasNewInk": newestRegion(in: document) != nil,
        ]
        return Self.text(Self.json(info))
    }

    func instructions() -> [String: Any] {
        let schema = AskAIController.bundledSchema.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let text = CanvasCommandPrompt.system + """


        Notes for Claude Code (MCP):
        - The capture JSON gives captureFrame, focusFrame, imageScale and pageBounds; use them exactly as \
        the Request fields described above. pencil_echo_place takes the answer object itself, not a string.
        - Answers are added as drafts. The user accepts or discards them on the iPad.
        - Each capture can be placed once. If placing fails, fix the answer and place again with the same \
        captureId; if the page changed, capture again.
        - You can think as long as needed before placing; the iPad waits.

        Answer JSON Schema:
        \(schema)
        """
        return Self.text(text)
    }

    func capture(_ arguments: [String: Any]) -> [String: Any] {
        guard let target, let controller else { return MCPWire.toolError(Self.notShared) }
        let document = target.shareDocument
        let requested = arguments["target"] as? String ?? "newest"
        var used = requested
        var made: AskAICapture?
        switch requested {
        case "newest":
            if let region = newestRegion(in: document) {
                made = controller.makeCapture(documentRegion: region, withContext: true)
                if made != nil { watermark = AskAIController.latestStrokeDate(in: document.snapshot.drawing) ?? watermark }
            } else {
                used = "visible"
                made = controller.makeCapture(documentRegion: target.visibleRegion())
            }
        case "visible":
            made = controller.makeCapture(documentRegion: target.visibleRegion())
        case "selection":
            guard let selection = target.selectionRegion() else {
                return MCPWire.toolError("Nothing is selected on the iPad. Use target visible, or ask the user to lasso the part to capture.")
            }
            made = controller.makeCapture(documentRegion: selection)
        case "page":
            let layout = document.layout
            let index: Int
            if let page = arguments["page"] as? Int {
                guard document.snapshot.pages.indices.contains(page) else {
                    return MCPWire.toolError("Page \(page) doesn't exist. The document has \(document.snapshot.pages.count) pages.")
                }
                index = page
            } else {
                index = layout.pageIndex(nearestY: target.visibleRegion().midY)
            }
            made = controller.makeCapture(documentRegion: layout.pageRect(index))
        default:
            return MCPWire.toolError("Unknown target \(requested). Use newest, visible, selection or page.")
        }
        guard let capture = made else { return MCPWire.toolError("That part of the page is empty or off the page. Try target visible.") }
        guard capture.png.count <= Self.maxImageBytes, (capture.focusPNG?.count ?? 0) <= Self.maxImageBytes else {
            return MCPWire.toolError("The capture is too large to send. Ask the user to lasso a smaller part and use target selection.")
        }
        let id = capture.context.requestId.uuidString
        captures.append((id, capture))
        if captures.count > Self.keptCaptures { captures.removeFirst(captures.count - Self.keptCaptures) }
        let pageIndex = document.layout.pageIndex(of: capture.context.pageId) ?? 0
        var info: [String: Any] = [
            "captureId": id, "target": used, "pageIndex": pageIndex, "revision": capture.context.capturedRevision,
            "captureFrame": Self.frame(capture.context.scopeFrame), "focusFrame": Self.frame(capture.focusFrame),
            "imageScale": capture.imageScale, "pageBounds": Self.frame(capture.context.pageBounds),
            "documentType": document.layout.type == .canvas ? "canvas" : "notebook",
        ]
        if let scale = capture.focusImageScale, capture.focusPNG != nil {
            info["focusImageScale"] = scale
            info["images"] = "The first image is captureFrame. The second is a magnified copy of focusFrame: pageX = focusFrame.x + imageX / focusImageScale."
        }
        var content: [[String: Any]] = [["type": "image", "data": capture.png.base64EncodedString(), "mimeType": "image/png"]]
        if let focus = capture.focusPNG, capture.focusImageScale != nil {
            content.append(["type": "image", "data": focus.base64EncodedString(), "mimeType": "image/png"])
        }
        content.append(["type": "text", "text": Self.json(info)])
        onActivity(used == "newest" ? "Captured the newest ink" : "Captured the \(used == "page" ? "page" : used == "selection" ? "selection" : "visible area")")
        return ["content": content]
    }

    func place(_ arguments: [String: Any]) -> [String: Any] {
        guard let target, let controller else { return MCPWire.toolError(Self.notShared) }
        let document = target.shareDocument
        guard let id = arguments["captureId"] as? String, let capture = captures.last(where: { $0.id == id })?.capture else {
            return MCPWire.toolError("Unknown captureId. Call pencil_echo_capture and use its captureId.")
        }
        guard !document.isReadOnly else { return MCPWire.toolError("This document is read-only on the iPad, so nothing was placed.") }
        let raw: Data
        if let text = arguments["answer"] as? String {
            raw = Data(CanvasCommandPrompt.stripCodeFence(text).utf8)
        } else if let object = arguments["answer"] as? [String: Any], JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object) {
            raw = data
        } else {
            return MCPWire.toolError("answer must be one JSON object in the Pencil Echo answer format.")
        }
        switch CommandValidator.validate(raw, context: capture.context, state: controller.validationState(for: capture)) {
        case .valid(let operations):
            let original = document.snapshot
            guard var next = AnswerApplier.apply(operations, to: original, layout: document.layout, capture: capture, date: now()) else {
                return MCPWire.toolError("There's no free space for that answer on the page. Use a smaller answer or at_frame in a blank area.")
            }
            DraftMarker.mark(&next, comparedTo: original, requestId: capture.context.requestId)
            document.applyExternalDrafts(next, requestId: capture.context.requestId)
            let objects = next.objects.count - original.objects.count
            let strokes = next.drawing.strokes.count - original.drawing.strokes.count
            onActivity("Placed drafts")
            return Self.text("Placed \(objects) object(s) and \(strokes) ink stroke(s) as drafts on \"\(document.title)\". The user accepts them on the iPad with Drafts → Accept all.")
        case .needsReview:
            return MCPWire.toolError("The user changed this part of the page after the capture. Capture again and place a new answer.")
        case .duplicate:
            return MCPWire.toolError("This capture was already placed. Capture again to add another answer.")
        case .invalid(let error):
            return MCPWire.toolError("The answer was rejected: \(Self.describe(error)). Fix it and place again with the same captureId.")
        }
    }

    // MARK: - Helpers

    /// Strokes newer than the watermark, with the capture margin. AI and draft ink never count.
    private func newestRegion(in document: any MCPDraftDocument) -> CGRect? {
        let strokes = document.snapshot.drawing.strokes.filter { $0.path.creationDate > watermark && !DraftMarker.isSynthetic($0.path.creationDate) }
        guard let first = strokes.first else { return nil }
        let bounds = strokes.dropFirst().reduce(first.renderBounds) { $0.union($1.renderBounds) }
        return bounds.insetBy(dx: -AskAIController.captureMargin, dy: -AskAIController.captureMargin)
    }

    static func describe(_ error: CommandError) -> String {
        switch error {
        case .responseTooLarge: "the answer is too large"
        case .malformedJSON: "it isn't valid JSON"
        case .schema(let path): "it doesn't match the schema at \(path)"
        case .limit(let path): "a value is over its limit at \(path)"
        case .geometry(let path): "a frame or point is outside the allowed area at \(path)"
        case .notAuthorized(let path): "that operation isn't allowed (\(path)); only add answers"
        case .outOfScope(let path): "it refers to something outside the capture at \(path)"
        case .conflictingOperations(let path): "two operations conflict at \(path)"
        }
    }

    private static func frame(_ frame: CommandFrame) -> [String: Double] {
        ["x": frame.x, "y": frame.y, "width": frame.width, "height": frame.height]
    }

    private static func json(_ object: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    private static func text(_ text: String) -> [String: Any] { ["content": [["type": "text", "text": text]]] }
}
