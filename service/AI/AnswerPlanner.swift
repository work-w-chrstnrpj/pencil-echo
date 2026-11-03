import Foundation
import PencilKit

// Placement, stale detection and conversation recording for Ask AI (ticket 010).
// All coordinates here are page points, origin top-left, unless named `document`.

enum AnswerPlacement {
    static let gap = 16.0
    static let minWidth = 240.0
    static let maxWidth = 480.0
    /// Scan step when looking for free space.
    static let step = 16.0

    /// A starting size; the object view may auto-size its height (ticket 011).
    static func size(type: CanvasObjectType, source: String, scope: CGRect, pageWidth: Double) -> CGSize {
        let width = min(max(scope.width, minWidth), maxWidth, max(minWidth, pageWidth - gap * 2))
        let charsPerLine = max(1, Int((width - 16) / 9.5))
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, ($1.count + charsPerLine - 1) / charsPerLine) }
        switch type {
        case .plot:
            // A readable chart; its height follows the width (ticket 016).
            let plotWidth = min(360, max(minWidth, pageWidth - gap * 2))
            return CGSize(width: plotWidth, height: plotWidth * 0.68 + 16)
        case .latex:
            return CGSize(width: width, height: max(56, Double(lines) * 40 + 16))
        case .text, .markdown:
            return CGSize(width: width, height: max(44, Double(lines) * 26 + 20))
        }
    }

    /// Finds a free rect of `size` next to `scope`: right of it, then below it.
    /// Returns nil when neither fits inside `page`, so the caller can grow the
    /// canvas or move to another notebook page. `occupied` is ink and object bounds.
    static func freeRect(size: CGSize, scope: CGRect, page: CGRect, occupied: [CGRect],
                         preferBelow: Bool = false) -> CGRect? {
        let right = { scan(origin: CGPoint(x: scope.maxX + gap, y: max(page.minY, scope.minY)), size: size,
                           page: page, occupied: occupied) }
        let below = { scan(origin: CGPoint(x: min(max(page.minX, scope.minX), page.maxX - size.width),
                                           y: scope.maxY + gap), size: size, page: page, occupied: occupied) }
        return preferBelow ? (below() ?? right()) : (right() ?? below())
    }

    /// Walks down from `origin` until the rect clears everything or leaves the page.
    private static func scan(origin: CGPoint, size: CGSize, page: CGRect, occupied: [CGRect]) -> CGRect? {
        var rect = CGRect(origin: origin, size: size)
        guard rect.minX >= page.minX, rect.maxX <= page.maxX else { return nil }
        while rect.maxY <= page.maxY {
            let blockers = occupied.filter { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(rect) }
            guard let lowest = blockers.map(\.maxY).max() else { return rect }
            rect.origin.y = max(rect.minY + step, lowest + gap / 2)
        }
        return nil
    }

    /// Stacks `sizes` top to bottom inside `block`, which must be tall enough.
    static func stack(_ sizes: [CGSize], in block: CGRect) -> [CGRect] {
        var y = block.minY
        return sizes.map { size in
            defer { y += size.height + gap }
            return CGRect(x: block.minX, y: y, width: size.width, height: size.height)
        }
    }

    static func blockSize(_ sizes: [CGSize]) -> CGSize {
        CGSize(width: sizes.map(\.width).max() ?? 0,
               height: sizes.map(\.height).reduce(0, +) + gap * Double(max(0, sizes.count - 1)))
    }
}

/// A fingerprint of the ink and objects inside the captured region. A change in
/// it means the user's problem changed while the request was pending (ticket 010
/// "Stale"). Ink is compared by each stroke's bounds, point count, transform and
/// ink, so edits elsewhere on the page do not count. Valid within one app run only.
enum ScopeFingerprint {
    static func make(strokes: [PKStroke], objects: [DocumentObject], pageId: UUID,
                     scope: CGRect, pageOrigin: CGPoint) -> Int {
        let documentScope = scope.offsetBy(dx: pageOrigin.x, dy: pageOrigin.y)
        var hasher = Hasher()
        for stroke in strokes where stroke.renderBounds.intersects(documentScope) {
            let bounds = stroke.renderBounds, t = stroke.transform
            for value in [bounds.minX, bounds.minY, bounds.width, bounds.height, t.a, t.b, t.c, t.d, t.tx, t.ty] {
                hasher.combine(value)
            }
            hasher.combine(stroke.path.count)
            hasher.combine(stroke.ink.inkType.rawValue)
            hasher.combine(stroke.mask?.bounds.width ?? -1)
        }
        for object in objects where object.pageId == pageId &&
            CGRect(x: object.frame.x, y: object.frame.y, width: object.frame.width, height: object.frame.height)
                .intersects(scope) {
            hasher.combine(object.id)
            hasher.combine(object.type.rawValue)
            hasher.combine(object.source)
            for value in [object.frame.x, object.frame.y, object.frame.width, object.frame.height] { hasher.combine(value) }
        }
        return hasher.finalize()
    }
}

extension Conversation {
    /// Records an applied answer: the instruction, the model's message and the
    /// request ID used for duplicate checks. The ID is kept even if the answer is
    /// later undone (docs/database/document-schema-v1.md, conversation.json).
    func recordingAnswer(requestId: UUID, instruction: String, message: String?, at date: Date) -> Conversation {
        var next = self
        if !next.appliedRequests.contains(where: { $0.requestId == requestId }) {
            next.appliedRequests.append(AppliedRequest(requestId: requestId, appliedAt: date))
        }
        func clipped(_ text: String) -> String {
            var text = text
            while text.utf8.count > DocumentLimits.maxMessageBytes { text.removeLast() }
            return text
        }
        next.messages.append(ConversationMessage(id: UUID(), role: .user, requestId: requestId,
                                                 text: clipped(instruction), createdAt: date))
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.messages.append(ConversationMessage(id: UUID(), role: .assistant, requestId: requestId,
                                                     text: clipped(message), createdAt: date))
        }
        if next.messages.count > DocumentLimits.maxMessages {
            next.messages.removeFirst(next.messages.count - DocumentLimits.maxMessages)
        }
        return next
    }
}
