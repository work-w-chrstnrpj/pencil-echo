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
    /// Ticket 018. Degrees, y down: 0 points right and positive sweep goes clockwise.
    static let inkAngles = -1_080.0...1_080.0
    static let inkRadii = 1.0...2_000.0
    static let inkAmplitude = 0.5...400.0
    static let inkWavelength = 4.0...2_000.0
    static let maxInkLabels = 16
    static let maxInkLabelBytes = 40
    /// Ticket 019: page-coordinate ink must stay this close to the captured context.
    static let pageInkReach = 64.0
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

    func contains(x pointX: Double, y pointY: Double) -> Bool {
        pointX >= x && pointY >= y && pointX <= maxX && pointY <= maxY
    }

    func outset(by margin: Double) -> CommandFrame {
        CommandFrame(x: x - margin, y: y - margin, width: width + margin * 2, height: height + margin * 2)
    }
}

struct CommandPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// One native ink stroke of a `draw_ink` answer.
/// Local drawings use the drawing's box. Page drawings use page points (ticket 019).
struct InkStrokeSpec: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        /// `line`: 2 points. `polyline`/`smooth`: 2 or more points, `smooth` curves through them.
        /// `ellipse` and `rect`: 2 points, the opposite corners of the bounding box.
        /// `arc`: empty `points`; geometry is `center`, radii and angles.
        /// `wave` and `zigzag`: the spine in `points`, expanded on device.
        case line, polyline, smooth, ellipse, arc, rect, wave, zigzag
    }
    enum Color: String, CaseIterable, Sendable {
        case black, gray, blue, red, green, orange, purple, brown, yellow, pink
    }
    /// Where to draw the arrowhead. `mid` sits halfway along the stroke.
    enum Arrow: String, CaseIterable, Sendable {
        case none, end, start, both, mid
    }
    var kind: Kind
    var points: [CommandPoint]
    var closed: Bool
    var color: Color
    /// Pen width in page points.
    var size: Double
    var arrow: Arrow = .none
    var fill: Bool = false
    /// `wave` and `zigzag` only.
    var amplitude: Double?
    var wavelength: Double?
    /// `arc` only. Angles are degrees.
    var center: CommandPoint?
    var radiusX: Double?
    var radiusY: Double?
    var startAngle: Double?
    var sweep: Double?
}

/// A short label placed with a drawing, in the same coordinates as its strokes.
struct InkLabel: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable { case text, latex }
    var kind: Kind
    var text: String
    var at: CommandPoint
}

enum InkCoordinates: String, CaseIterable, Sendable {
    /// Points live in the local `width` × `height` box and are scaled into place.
    case local
    /// Points are page points. There is no local box and no scaling (ticket 019).
    case page
}

/// Native ink. Local drawings are scaled into place; page drawings are already in page points.
struct InkDrawing: Equatable, Sendable {
    var width: Double
    var height: Double
    var strokes: [InkStrokeSpec]
    var labels: [InkLabel] = []
    var coordinates: InkCoordinates = .local
}

/// Expands diagram primitives into polylines the validator can bound and the
/// ink converter can draw. Pure: no PencilKit and no document access.
enum InkGeometry {
    /// The stroke's rendered centerline. Nil when a wave or zigzag would exceed the point budget.
    static func outline(_ stroke: InkStrokeSpec) -> [CommandPoint]? {
        switch stroke.kind {
        case .line, .polyline:
            var points = stroke.points
            if stroke.closed, let first = points.first { points.append(first) }
            return densify(points)
        case .smooth:
            return catmullRom(stroke.points, closed: stroke.closed)
        case .ellipse:
            guard stroke.points.count == 2 else { return [] }
            let box = box(stroke.points[0], stroke.points[1])
            return (0...64).map { index in
                let angle = Double(index) / 64 * 2 * .pi
                return CommandPoint(x: box.midX + box.width / 2 * cos(angle), y: box.midY + box.height / 2 * sin(angle))
            }
        case .rect:
            guard stroke.points.count == 2 else { return [] }
            let box = box(stroke.points[0], stroke.points[1])
            return densify([
                CommandPoint(x: box.minX, y: box.minY), CommandPoint(x: box.maxX, y: box.minY),
                CommandPoint(x: box.maxX, y: box.maxY), CommandPoint(x: box.minX, y: box.maxY),
                CommandPoint(x: box.minX, y: box.minY),
            ])
        case .arc:
            guard let center = stroke.center, let radiusX = stroke.radiusX, let radiusY = stroke.radiusY,
                  let start = stroke.startAngle, let sweep = stroke.sweep, sweep != 0 else { return [] }
            let steps = max(2, Int((abs(sweep) / 6).rounded(.up)))
            return (0...steps).map { index in
                let radians = (start + sweep * Double(index) / Double(steps)) * .pi / 180
                return CommandPoint(x: center.x + radiusX * cos(radians), y: center.y + radiusY * sin(radians))
            }
        case .wave, .zigzag:
            guard let amplitude = stroke.amplitude, let wavelength = stroke.wavelength, wavelength > 0 else { return [] }
            return oscillate(stroke.points, amplitude: amplitude, wavelength: wavelength, wavy: stroke.kind == .wave,
                             closed: stroke.closed)
        }
    }

    /// Points that count toward the 2,048 limit. Classic strokes count their model
    /// points, so version 2 answers keep the same budget; waves, zigzags, arcs,
    /// arrowheads and fills count the points the device actually draws.
    static func budgetCount(_ stroke: InkStrokeSpec) -> Int? {
        let base: Int
        switch stroke.kind {
        case .line, .polyline, .smooth, .ellipse:
            base = stroke.points.count
        case .rect:
            base = 5
        case .arc, .wave, .zigzag:
            guard let outline = outline(stroke) else { return nil }
            base = outline.count
        }
        let marks = decorations(stroke)
        return base + marks.arrows.reduce(0) { $0 + $1.count } + marks.fill.reduce(0) { $0 + $1.count }
    }

    /// Arrowheads (two short strokes each) and fill chords, in the stroke's own coordinates.
    static func decorations(_ stroke: InkStrokeSpec) -> (arrows: [[CommandPoint]], fill: [[CommandPoint]]) {
        let arrows = arrowheads(stroke)
        let fill = stroke.fill ? fillChords(stroke) : []
        return (arrows, fill)
    }

    static func arrowheads(_ stroke: InkStrokeSpec) -> [[CommandPoint]] {
        guard stroke.arrow != .none, let path = outline(stroke), path.count >= 2 else { return [] }
        let length = max(8, stroke.size * 4)
        var heads: [[CommandPoint]] = []
        func add(_ fraction: Double, forward: Bool) {
            guard let mark = sample(path, at: fraction) else { return }
            let direction = forward ? mark.direction : CommandPoint(x: -mark.direction.x, y: -mark.direction.y)
            heads += arrowhead(tip: mark.point, direction: direction, length: length)
        }
        switch stroke.arrow {
        case .none: break
        case .end: add(1, forward: true)
        case .start: add(0, forward: false)
        case .both: add(0, forward: false); add(1, forward: true)
        case .mid: add(0.5, forward: true)
        }
        return heads
    }

    /// Horizontal chords covering a closed shape. Spacing stays under the pen width.
    static func fillChords(_ stroke: InkStrokeSpec) -> [[CommandPoint]] {
        let spacing = max(stroke.size * 0.55, 1.25)
        switch stroke.kind {
        case .ellipse:
            guard stroke.points.count == 2 else { return [] }
            return ellipseChords(box(stroke.points[0], stroke.points[1]), spacing: spacing)
        case .rect:
            guard stroke.points.count == 2 else { return [] }
            let rect = box(stroke.points[0], stroke.points[1])
            return scan([
                CommandPoint(x: rect.minX, y: rect.minY), CommandPoint(x: rect.maxX, y: rect.minY),
                CommandPoint(x: rect.maxX, y: rect.maxY), CommandPoint(x: rect.minX, y: rect.maxY),
                CommandPoint(x: rect.minX, y: rect.minY),
            ], spacing: spacing)
        case .arc, .line, .polyline, .smooth, .wave, .zigzag:
            guard stroke.closed, let outline = outline(stroke), outline.count >= 4 else { return [] }
            var polygon = outline
            if polygon.first != polygon.last, let first = polygon.first { polygon.append(first) }
            return scan(polygon, spacing: spacing)
        }
    }

    /// Every point that must lie inside the box or the page: centerline, arrowheads and fill.
    static func constrainedPoints(_ stroke: InkStrokeSpec) -> [CommandPoint]? {
        guard let centerline = outline(stroke) else { return nil }
        let marks = decorations(stroke)
        return centerline + marks.arrows.flatMap { $0 } + marks.fill.flatMap { $0 }
    }

    // MARK: - Sampling

    private static func densify(_ points: [CommandPoint]) -> [CommandPoint] {
        guard let first = points.first else { return [] }
        var result = [first]
        for (start, end) in zip(points, points.dropFirst()) {
            let steps = max(1, Int((hypot(end.x - start.x, end.y - start.y) / 6).rounded(.up)))
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                result.append(CommandPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            }
        }
        return result
    }

    private static func catmullRom(_ points: [CommandPoint], closed: Bool) -> [CommandPoint] {
        var points = points
        if closed, points.count > 2 { points.append(points[0]) }
        guard points.count > 2 else { return points }
        func at(_ index: Int) -> CommandPoint {
            if closed, points.count > 3 {
                let count = points.count - 1
                return points[((index % count) + count) % count]
            }
            return points[min(max(index, 0), points.count - 1)]
        }
        var result: [CommandPoint] = []
        for index in 0..<(points.count - 1) {
            let p0 = at(index - 1), p1 = at(index), p2 = at(index + 1), p3 = at(index + 2)
            for step in 0..<8 {
                let t = Double(step) / 8, t2 = t * t, t3 = t2 * t
                func blend(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                result.append(CommandPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    private static func oscillate(_ spine: [CommandPoint], amplitude: Double, wavelength: Double,
                                  wavy: Bool, closed: Bool) -> [CommandPoint]? {
        var spine = spine
        if closed, spine.count > 2, let first = spine.first { spine.append(first) }
        guard spine.count >= 2 else { return [] }
        var estimate = 0
        for (start, end) in zip(spine, spine.dropFirst()) {
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0 else { continue }
            estimate += max(4, Int((length / wavelength * 8).rounded(.up)))
            if estimate > CommandLimits.maxInkPoints { return nil }
        }
        var result: [CommandPoint] = []
        var traveled = 0.0
        for (start, end) in zip(spine, spine.dropFirst()) {
            let dx = end.x - start.x, dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 0 else { continue }
            let samples = max(4, Int((length / wavelength * 8).rounded(.up)))
            let normal = CommandPoint(x: -dy / length, y: dx / length)
            let firstStep = result.isEmpty ? 0 : 1
            for step in firstStep...samples {
                let t = Double(step) / Double(samples)
                let distance = traveled + length * t
                let offset = amplitude * (wavy ? sin(distance / wavelength * 2 * .pi) : triangle(distance / wavelength))
                result.append(CommandPoint(x: start.x + dx * t + normal.x * offset,
                                           y: start.y + dy * t + normal.y * offset))
            }
            traveled += length
        }
        return result
    }

    /// Triangle wave from -1 to 1 and back, one wavelength long.
    private static func triangle(_ cycles: Double) -> Double {
        let phase = cycles - cycles.rounded(.down)
        return phase < 0.5 ? (4 * phase - 1) : (3 - 4 * phase)
    }

    private struct Box {
        var minX: Double, minY: Double, maxX: Double, maxY: Double
        var midX: Double { (minX + maxX) / 2 }
        var midY: Double { (minY + maxY) / 2 }
        var width: Double { maxX - minX }
        var height: Double { maxY - minY }
    }

    private static func box(_ a: CommandPoint, _ b: CommandPoint) -> Box {
        Box(minX: min(a.x, b.x), minY: min(a.y, b.y), maxX: max(a.x, b.x), maxY: max(a.y, b.y))
    }

    private static func ellipseChords(_ box: Box, spacing: Double) -> [[CommandPoint]] {
        guard box.width > 0, box.height > 0 else { return [] }
        var chords: [[CommandPoint]] = []
        var y = box.minY + spacing / 2
        while y < box.maxY {
            let ny = (y - box.midY) / (box.height / 2)
            let half = box.width / 2 * (1 - ny * ny).squareRoot()
            if half > 0 {
                chords.append([CommandPoint(x: box.midX - half, y: y), CommandPoint(x: box.midX + half, y: y)])
            }
            y += spacing
            if chords.count > CommandLimits.maxInkPoints { break }
        }
        return chords
    }

    private static func scan(_ polygon: [CommandPoint], spacing: Double) -> [[CommandPoint]] {
        guard polygon.count >= 2 else { return [] }
        let minY = polygon.map(\.y).min() ?? 0, maxY = polygon.map(\.y).max() ?? 0
        var chords: [[CommandPoint]] = []
        var y = minY + spacing / 2
        while y < maxY && chords.count <= CommandLimits.maxInkPoints {
            var xs: [Double] = []
            for (a, b) in zip(polygon, polygon.dropFirst()) where a.y != b.y {
                if (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                    let t = (y - a.y) / (b.y - a.y)
                    xs.append(a.x + (b.x - a.x) * t)
                }
            }
            xs.sort()
            var index = 0
            while index + 1 < xs.count {
                chords.append([CommandPoint(x: xs[index], y: y), CommandPoint(x: xs[index + 1], y: y)])
                index += 2
            }
            y += spacing
        }
        return chords
    }

    private struct Sample {
        var point: CommandPoint
        var direction: CommandPoint
    }

    /// `fraction` 0 is the start and 1 is the end, measured along the polyline.
    private static func sample(_ path: [CommandPoint], at fraction: Double) -> Sample? {
        let lengths = zip(path, path.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return nil }
        var remaining = min(max(fraction, 0), 1) * total
        for (index, length) in lengths.enumerated() where length > 0 {
            if remaining <= length || index == lengths.count - 1 {
                let t = min(max(remaining / length, 0), 1)
                let start = path[index], end = path[index + 1]
                return Sample(point: CommandPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                              direction: CommandPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length))
            }
            remaining -= length
        }
        return nil
    }

    private static func arrowhead(tip: CommandPoint, direction: CommandPoint, length: Double) -> [[CommandPoint]] {
        let wing = 0.5
        func rotate(_ vector: CommandPoint, _ angle: Double) -> CommandPoint {
            CommandPoint(x: vector.x * cos(angle) - vector.y * sin(angle),
                         y: vector.x * sin(angle) + vector.y * cos(angle))
        }
        let back = CommandPoint(x: -direction.x, y: -direction.y)
        return [wing, -wing].map { angle in
            let barb = rotate(back, angle)
            return [tip, CommandPoint(x: tip.x + barb.x * length, y: tip.y + barb.y * length)]
        }
    }
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
