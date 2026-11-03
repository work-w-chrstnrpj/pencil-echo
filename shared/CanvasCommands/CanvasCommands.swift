import Foundation

// Canvas commands v1 types. Contract: docs/api/canvas-commands-v1.md.
// The provider schema is shared/schemas/canvas-commands-v1.json; these types
// and CommandValidator are authoritative when the two disagree.

enum CommandLimits {
    static let maxResponseBytes = 256 * 1024
    static let maxOperations = 20
    static let maxSourceBytes = 20 * 1024
    static let maxMessageBytes = 4 * 1024
    static let minFrameSide = 8.0
    // draw_ink (ticket 016), bounds taken from upstream finish-drawing.js.
    static let maxInkStrokes = 64
    static let maxInkStrokePoints = 128
    static let maxInkPoints = 2_048
    static let inkBoxSides = 16.0...2_000.0
    static let inkStrokeSizes = 1.0...24.0
}

enum CanvasObjectType: String, CaseIterable, Sendable {
    /// `plot` sources use the `PlotSpec` line format (ticket 016).
    case text, markdown, latex, plot
}

enum PlacementHint: String, CaseIterable, Sendable {
    case rightOfScope = "right_of_scope"
    case belowScope = "below_scope"
    case atFrame = "at_frame"
}

/// A rectangle in page points, origin top-left, y down.
struct CommandFrame: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var maxX: Double { x + width }
    var maxY: Double { y + height }

    func contains(_ other: CommandFrame) -> Bool {
        other.x >= x && other.y >= y && other.maxX <= maxX && other.maxY <= maxY
    }
}

struct CommandPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// One native ink stroke of a `draw_ink` answer, in the drawing's local box.
struct InkStrokeSpec: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        /// `line`: 2 points. `polyline`/`smooth`: 2 or more points, `smooth` curves through them.
        /// `ellipse`: 2 points, the opposite corners of its bounding box.
        case line, polyline, smooth, ellipse
    }
    enum Color: String, CaseIterable, Sendable {
        case black, gray, blue, red, green, orange, purple, brown, yellow, pink
    }
    var kind: Kind
    var points: [CommandPoint]
    var closed: Bool
    var color: Color
    /// Pen width in page points.
    var size: Double
}

/// Native ink drawn in a local `width` × `height` box, y down; the app scales it into place.
struct InkDrawing: Equatable, Sendable {
    var width: Double
    var height: Double
    var strokes: [InkStrokeSpec]
}

enum CanvasOperation: Equatable, Sendable {
    case addObject(type: CanvasObjectType, source: String, placement: PlacementHint, frame: CommandFrame?)
    case editObject(objectId: UUID, source: String)
    case deleteObject(objectId: UUID)
    /// Ticket 016: a sketch, diagram or annotation as editable PencilKit strokes.
    case drawInk(InkDrawing, placement: PlacementHint, frame: CommandFrame?)

    /// Wire names of `op`, in schema order.
    static let opNames = ["add_object", "edit_object", "delete_object", "draw_ink"]
}

/// Recorded by the app at capture time; immutable until the answer is applied or discarded.
struct CommandRequestContext: Equatable, Sendable {
    var requestId: UUID
    var documentId: UUID
    var pageId: UUID
    var capturedRevision: Int
    var scopeFrame: CommandFrame
    var scopeObjectIds: Set<UUID>
    var pageBounds: CommandFrame
    /// Set only by an explicit user control, never inferred from text or model output.
    var allowReplace: Bool
}

/// Read-only snapshot of the document when the answer arrives.
struct DocumentValidationState: Equatable, Sendable {
    var currentRevision: Int
    /// Whether ink or objects intersecting the captured scope changed since capture.
    var scopeChanged: Bool
    var existingObjectIds: Set<UUID>
    /// From conversation.json `appliedRequests`.
    var appliedRequestIds: Set<UUID>
}

enum ReviewReason: Equatable, Sendable {
    case scopeChanged
    case targetMissing
}

/// `path` is a JSON pointer into the response, e.g. `/operations/3/frame/width`.
/// Never put response content in an error.
enum CommandError: Error, Equatable, Sendable {
    case responseTooLarge
    case malformedJSON
    case schema(String)
    case limit(String)
    case geometry(String)
    case notAuthorized(String)
    case outOfScope(String)
    case conflictingOperations(String)
}

enum ValidationResult: Equatable, Sendable {
    case valid([CanvasOperation])
    case needsReview([CanvasOperation], ReviewReason)
    /// Already applied: a silent no-op, not an error for the user.
    case duplicate
    case invalid(CommandError)
}
