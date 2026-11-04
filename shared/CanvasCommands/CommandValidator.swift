import Foundation

/// Decides whether an AI answer may be applied. Pure: it reads values and never
/// touches a document, store or undo manager. Check order follows
/// docs/api/canvas-commands-v1.md "Order of checks"; the first failure wins.
enum CommandValidator {
    static func validate(_ raw: Data, context: CommandRequestContext,
                         state: DocumentValidationState) -> ValidationResult {
        guard raw.count <= CommandLimits.maxResponseBytes else { return .invalid(.responseTooLarge) }
        guard let root = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
            return .invalid(.malformedJSON)
        }
        if state.appliedRequestIds.contains(context.requestId) { return .duplicate }

        let parsed: Parsed
        do {
            parsed = try parse(root)
            try checkLimits(parsed)
            try checkGeometry(parsed.operations, pageBounds: context.pageBounds, scope: context.scopeFrame)
        } catch let error as CommandError {
            return .invalid(error)
        } catch {
            return .invalid(.malformedJSON)
        }

        let operations = parsed.operations.map(\.operation)
        var targetMissing = false
        var targets = Set<UUID>()
        for (index, operation) in operations.enumerated() {
            let id: UUID
            switch operation {
            case .addObject, .drawInk: continue
            case .editObject(let objectId, _), .deleteObject(let objectId): id = objectId
            }
            let path = "/operations/\(index)"
            guard context.allowReplace else { return .invalid(.notAuthorized(path)) }
            guard context.scopeObjectIds.contains(id) else { return .invalid(.outOfScope(path + "/objectId")) }
            guard targets.insert(id).inserted else { return .invalid(.conflictingOperations(path + "/objectId")) }
            if !state.existingObjectIds.contains(id) { targetMissing = true }
        }
        if targetMissing { return .needsReview(operations, .targetMissing) }

        if state.currentRevision != context.capturedRevision && state.scopeChanged {
            return .needsReview(operations, .scopeChanged)
        }
        return .valid(operations)
    }

    // MARK: - Shape

    private struct Parsed {
        var operations: [(operation: CanvasOperation, path: String)]
        var message: String?
    }

    private static let envelopeKeys: Set<String> = ["version", "operations", "message"]
    private static let operationKeys: [String: Set<String>] = [
        "add_object": ["op", "type", "source", "placement", "frame"],
        "edit_object": ["op", "objectId", "source"],
        "delete_object": ["op", "objectId"],
        "draw_ink": ["op", "width", "height", "strokes", "placement", "frame"],
    ]
    /// Present only on version 3 answers. Version 1 and 2 keep the exact key sets above.
    private static let drawInkOptional: Set<String> = ["labels", "coordinates"]
    private static let frameKeys: Set<String> = ["x", "y", "width", "height"]
    private static let strokeRequired: Set<String> = ["kind", "points", "closed", "color", "size"]
    private static let strokeOptional: Set<String> = [
        "arrow", "fill", "amplitude", "wavelength", "center", "radiusX", "radiusY", "startAngle", "sweep",
    ]

    private static func parse(_ root: [String: Any]) throws -> Parsed {
        try requireExactKeys(root, envelopeKeys, path: "")
        // Version 2 adds plots and draw_ink. Version 3 adds diagram strokes (ticket 018)
        // and page-coordinate ink (ticket 019). Version 1 answers stay valid.
        guard let version = number(root["version"]), version == 1 || version == 2 || version == 3 else {
            throw CommandError.schema("/version")
        }
        guard let rawOperations = root["operations"] as? [Any] else { throw CommandError.schema("/operations") }
        let message = try nullableString(root["message"], path: "/message")

        let operations = try rawOperations.enumerated().map { index, value -> (operation: CanvasOperation, path: String) in
            let path = "/operations/\(index)"
            let operation = try parseOperation(value, path: path, version: Int(version))
            if version == 1 {
                if case .drawInk = operation { throw CommandError.schema(path + "/op") }
                if case .addObject(.plot, _, _, _) = operation { throw CommandError.schema(path + "/type") }
            }
            return (operation: operation, path: path)
        }
        return Parsed(operations: operations, message: message)
    }

    private static func parseOperation(_ value: Any, path: String, version: Int) throws -> CanvasOperation {
        guard let object = value as? [String: Any] else { throw CommandError.schema(path) }
        guard let op = object["op"] as? String, let keys = operationKeys[op] else {
            throw CommandError.schema(path + "/op")
        }
        if op != "draw_ink" { try requireExactKeys(object, keys, path: path) }

        switch op {
        case "add_object":
            guard let type = (object["type"] as? String).flatMap(CanvasObjectType.init(rawValue:)) else {
                throw CommandError.schema(path + "/type")
            }
            guard let placement = (object["placement"] as? String).flatMap(PlacementHint.init(rawValue:)) else {
                throw CommandError.schema(path + "/placement")
            }
            return .addObject(type: type, source: try string(object["source"], path: path + "/source"),
                              placement: placement, frame: try parseFrame(object["frame"], path: path + "/frame"))
        case "draw_ink":
            guard let placement = (object["placement"] as? String).flatMap(PlacementHint.init(rawValue:)) else {
                throw CommandError.schema(path + "/placement")
            }
            try requireKeys(object, required: operationKeys["draw_ink"]!, optional: drawInkOptional, path: path)
            let coordinates = try parseCoordinates(object["coordinates"], path: path + "/coordinates", version: version)
            let width: Double
            let height: Double
            if coordinates == .page {
                guard object["width"] is NSNull, object["height"] is NSNull else { throw CommandError.schema(path + "/width") }
                width = 0
                height = 0
            } else {
                guard let parsedWidth = number(object["width"]) else { throw CommandError.schema(path + "/width") }
                guard let parsedHeight = number(object["height"]) else { throw CommandError.schema(path + "/height") }
                width = parsedWidth
                height = parsedHeight
            }
            guard let strokes = object["strokes"] as? [Any] else { throw CommandError.schema(path + "/strokes") }
            let drawing = InkDrawing(
                width: width, height: height,
                strokes: try strokes.enumerated().map { index, value in
                    try parseStroke(value, path: path + "/strokes/\(index)", version: version)
                },
                labels: try parseLabels(object["labels"], path: path + "/labels", version: version),
                coordinates: coordinates)
            return .drawInk(drawing, placement: placement, frame: try parseFrame(object["frame"], path: path + "/frame"))
        case "edit_object":
            return .editObject(objectId: try uuid(object["objectId"], path: path + "/objectId"),
                               source: try string(object["source"], path: path + "/source"))
        default:
            return .deleteObject(objectId: try uuid(object["objectId"], path: path + "/objectId"))
        }
    }

    private static func parseCoordinates(_ value: Any?, path: String, version: Int) throws -> InkCoordinates {
        guard let value else { return .local }
        if version < 3 { throw CommandError.schema(path) }
        guard let name = value as? String, let coordinates = InkCoordinates(rawValue: name) else {
            throw CommandError.schema(path)
        }
        return coordinates
    }

    private static func parseLabels(_ value: Any?, path: String, version: Int) throws -> [InkLabel] {
        guard let value else { return [] }
        if version < 3 { throw CommandError.schema(path) }
        guard let items = value as? [Any] else { throw CommandError.schema(path) }
        return try items.enumerated().map { index, item in
            let itemPath = path + "/\(index)"
            guard let object = item as? [String: Any] else { throw CommandError.schema(itemPath) }
            try requireExactKeys(object, ["kind", "text", "x", "y"], path: itemPath)
            guard let kind = (object["kind"] as? String).flatMap(InkLabel.Kind.init(rawValue:)) else {
                throw CommandError.schema(itemPath + "/kind")
            }
            guard let x = number(object["x"]), let y = number(object["y"]) else {
                throw CommandError.schema(itemPath + "/x")
            }
            return InkLabel(kind: kind, text: try string(object["text"], path: itemPath + "/text"), at: CommandPoint(x: x, y: y))
        }
    }

    private static func parseStroke(_ value: Any, path: String, version: Int) throws -> InkStrokeSpec {
        guard let object = value as? [String: Any] else { throw CommandError.schema(path) }
        try requireKeys(object, required: strokeRequired, optional: strokeOptional, path: path)
        guard let kind = (object["kind"] as? String).flatMap(InkStrokeSpec.Kind.init(rawValue:)) else {
            throw CommandError.schema(path + "/kind")
        }
        // A new kind is the schema error even when the stroke also carries version 3 fields.
        if version < 3, kind != .line, kind != .polyline, kind != .smooth, kind != .ellipse {
            throw CommandError.schema(path + "/kind")
        }
        if version < 3, let extra = strokeOptional.sorted().first(where: { object[$0] != nil }) {
            throw CommandError.schema(path + "/" + extra)
        }
        guard let color = (object["color"] as? String).flatMap(InkStrokeSpec.Color.init(rawValue:)) else {
            throw CommandError.schema(path + "/color")
        }
        guard let closed = boolean(object["closed"]) else { throw CommandError.schema(path + "/closed") }
        guard let size = number(object["size"]) else { throw CommandError.schema(path + "/size") }
        guard let rawPoints = object["points"] as? [Any] else { throw CommandError.schema(path + "/points") }
        let points = try rawPoints.enumerated().map { index, value -> CommandPoint in
            guard let pair = value as? [Any], pair.count == 2, let x = number(pair[0]), let y = number(pair[1]) else {
                throw CommandError.schema(path + "/points/\(index)")
            }
            return CommandPoint(x: x, y: y)
        }
        var stroke = InkStrokeSpec(kind: kind, points: points, closed: closed, color: color, size: size)
        if let arrow = object["arrow"] {
            guard let name = arrow as? String, let parsed = InkStrokeSpec.Arrow(rawValue: name) else {
                throw CommandError.schema(path + "/arrow")
            }
            stroke.arrow = parsed
        }
        if let fill = object["fill"] {
            guard let parsed = boolean(fill) else { throw CommandError.schema(path + "/fill") }
            stroke.fill = parsed
        }
        stroke.amplitude = try optionalNumber(object["amplitude"], path: path + "/amplitude")
        stroke.wavelength = try optionalNumber(object["wavelength"], path: path + "/wavelength")
        stroke.radiusX = try optionalNumber(object["radiusX"], path: path + "/radiusX")
        stroke.radiusY = try optionalNumber(object["radiusY"], path: path + "/radiusY")
        stroke.startAngle = try optionalNumber(object["startAngle"], path: path + "/startAngle")
        stroke.sweep = try optionalNumber(object["sweep"], path: path + "/sweep")
        if let center = object["center"], !(center is NSNull) {
            guard let pair = center as? [Any], pair.count == 2, let x = number(pair[0]), let y = number(pair[1]) else {
                throw CommandError.schema(path + "/center")
            }
            stroke.center = CommandPoint(x: x, y: y)
        }
        try rejectUnusedGeometry(stroke, path: path)
        return stroke
    }

    /// Arc, wave and zigzag may carry only the fields they use. A line with an amplitude is rejected.
    private static func rejectUnusedGeometry(_ stroke: InkStrokeSpec, path: String) throws {
        let hasWave = stroke.amplitude != nil || stroke.wavelength != nil
        let hasArc = stroke.center != nil || stroke.radiusX != nil || stroke.radiusY != nil
            || stroke.startAngle != nil || stroke.sweep != nil
        switch stroke.kind {
        case .wave, .zigzag:
            if hasArc { throw CommandError.schema(path + "/center") }
        case .arc:
            if hasWave { throw CommandError.schema(path + "/amplitude") }
        default:
            if hasWave { throw CommandError.schema(path + "/amplitude") }
            if hasArc { throw CommandError.schema(path + "/center") }
        }
    }

    private static func parseFrame(_ value: Any?, path: String) throws -> CommandFrame? {
        if value is NSNull { return nil }
        guard let object = value as? [String: Any] else { throw CommandError.schema(path) }
        try requireExactKeys(object, frameKeys, path: path)
        func side(_ key: String) throws -> Double {
            guard let value = number(object[key]) else { throw CommandError.schema(path + "/" + key) }
            return value
        }
        return CommandFrame(x: try side("x"), y: try side("y"), width: try side("width"), height: try side("height"))
    }

    /// Codable would silently drop unknown keys; the contract rejects them.
    private static func requireExactKeys(_ object: [String: Any], _ allowed: Set<String>, path: String) throws {
        try requireKeys(object, required: allowed, optional: [], path: path)
    }

    private static func requireKeys(_ object: [String: Any], required: Set<String>, optional: Set<String>, path: String) throws {
        let allowed = required.union(optional)
        if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw CommandError.schema(path + "/" + unknown)
        }
        if let missing = required.sorted().first(where: { object[$0] == nil }) {
            throw CommandError.schema(path + "/" + missing)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        // JSONSerialization represents booleans as NSNumber too.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A missing key or JSON null stays nil. Any other value must be a number.
    private static func optionalNumber(_ value: Any?, path: String) throws -> Double? {
        if value == nil || value is NSNull { return nil }
        guard let number = number(value) else { throw CommandError.schema(path) }
        return number
    }

    private static func string(_ value: Any?, path: String) throws -> String {
        guard let string = value as? String else { throw CommandError.schema(path) }
        return string
    }

    private static func nullableString(_ value: Any?, path: String) throws -> String? {
        if value is NSNull { return nil }
        return try string(value, path: path)
    }

    private static func uuid(_ value: Any?, path: String) throws -> UUID {
        guard let id = (value as? String).flatMap(UUID.init(uuidString:)) else { throw CommandError.schema(path) }
        return id
    }

    // MARK: - Limits and geometry

    private static func checkLimits(_ parsed: Parsed) throws {
        guard (1...CommandLimits.maxOperations).contains(parsed.operations.count) else {
            throw CommandError.limit("/operations")
        }
        if let message = parsed.message, message.utf8.count > CommandLimits.maxMessageBytes {
            throw CommandError.limit("/message")
        }
        for (operation, path) in parsed.operations {
            switch operation {
            case .addObject(_, let source, _, _), .editObject(_, let source):
                if source.utf8.count > CommandLimits.maxSourceBytes ||
                    source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw CommandError.limit(path + "/source")
                }
                // A plot must parse with the renderer's own bounded grammar (ticket 016).
                if case .addObject(.plot, _, _, _) = operation, (try? PlotSpec.parse(source)) == nil {
                    throw CommandError.schema(path + "/source")
                }
            case .drawInk(let drawing, _, _):
                try checkInk(drawing, path: path)
            case .deleteObject:
                break
            }
        }
    }

    private static func checkInk(_ drawing: InkDrawing, path: String) throws {
        if drawing.coordinates == .local {
            guard drawing.width.isFinite, CommandLimits.inkBoxSides.contains(drawing.width) else { throw CommandError.limit(path + "/width") }
            guard drawing.height.isFinite, CommandLimits.inkBoxSides.contains(drawing.height) else { throw CommandError.limit(path + "/height") }
        }
        guard (1...CommandLimits.maxInkStrokes).contains(drawing.strokes.count) else { throw CommandError.limit(path + "/strokes") }
        guard drawing.labels.count <= CommandLimits.maxInkLabels else { throw CommandError.limit(path + "/labels") }
        for (index, label) in drawing.labels.enumerated() {
            let labelPath = path + "/labels/\(index)"
            let trimmed = label.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, label.text.utf8.count <= CommandLimits.maxInkLabelBytes else {
                throw CommandError.limit(labelPath + "/text")
            }
        }
        var budget = 0
        // Points may sit up to 1% outside a local box: models round coordinates.
        let slackX = drawing.width * 0.01, slackY = drawing.height * 0.01
        for (index, stroke) in drawing.strokes.enumerated() {
            let strokePath = path + "/strokes/\(index)"
            try checkStrokeShape(stroke, path: strokePath)
            guard let count = InkGeometry.budgetCount(stroke) else { throw CommandError.limit(strokePath + "/points") }
            budget += count
            guard budget <= CommandLimits.maxInkPoints else { throw CommandError.limit(path + "/strokes") }
            if drawing.coordinates == .local {
                try checkLocalStroke(stroke, path: strokePath, width: drawing.width, height: drawing.height, slackX: slackX, slackY: slackY)
            }
        }
        if drawing.coordinates == .local {
            for (index, label) in drawing.labels.enumerated() {
                guard label.at.x.isFinite, label.at.y.isFinite, label.at.x >= -slackX, label.at.y >= -slackY,
                      label.at.x <= drawing.width + slackX, label.at.y <= drawing.height + slackY else {
                    throw CommandError.geometry(path + "/labels/\(index)/x")
                }
            }
        }
    }

    private static func checkStrokeShape(_ stroke: InkStrokeSpec, path: String) throws {
        let count = stroke.points.count
        let validCount = switch stroke.kind {
        case .line, .ellipse, .rect: count == 2
        case .polyline, .smooth, .wave, .zigzag: (2...CommandLimits.maxInkStrokePoints).contains(count)
        case .arc: count == 0
        }
        guard validCount else { throw CommandError.limit(path + "/points") }
        guard stroke.size.isFinite, CommandLimits.inkStrokeSizes.contains(stroke.size) else {
            throw CommandError.limit(path + "/size")
        }
        if stroke.kind == .arc {
            guard let center = stroke.center, center.x.isFinite, center.y.isFinite else { throw CommandError.schema(path + "/center") }
            guard let radiusX = stroke.radiusX, radiusX.isFinite, CommandLimits.inkRadii.contains(radiusX) else {
                throw CommandError.limit(path + "/radiusX")
            }
            guard let radiusY = stroke.radiusY, radiusY.isFinite, CommandLimits.inkRadii.contains(radiusY) else {
                throw CommandError.limit(path + "/radiusY")
            }
            guard let start = stroke.startAngle, start.isFinite, CommandLimits.inkAngles.contains(start) else {
                throw CommandError.limit(path + "/startAngle")
            }
            guard let sweep = stroke.sweep, sweep.isFinite, abs(sweep) >= 1, CommandLimits.inkAngles.contains(sweep) else {
                throw CommandError.limit(path + "/sweep")
            }
        }
        if stroke.kind == .wave || stroke.kind == .zigzag {
            guard let amplitude = stroke.amplitude, amplitude.isFinite, CommandLimits.inkAmplitude.contains(amplitude) else {
                throw CommandError.limit(path + "/amplitude")
            }
            guard let wavelength = stroke.wavelength, wavelength.isFinite, CommandLimits.inkWavelength.contains(wavelength) else {
                throw CommandError.limit(path + "/wavelength")
            }
        }
    }

    private static func checkLocalStroke(_ stroke: InkStrokeSpec, path: String, width: Double, height: Double,
                                        slackX: Double, slackY: Double) throws {
        func inside(_ point: CommandPoint, _ pointPath: String) throws {
            guard point.x.isFinite, point.y.isFinite, point.x >= -slackX, point.y >= -slackY,
                  point.x <= width + slackX, point.y <= height + slackY else {
                throw CommandError.geometry(pointPath)
            }
        }
        for (pointIndex, point) in stroke.points.enumerated() {
            try inside(point, path + "/points/\(pointIndex)")
        }
        if let center = stroke.center { try inside(center, path + "/center") }
        // Expanded waves, zigzags and arcs can leave the box even when the spine is inside.
        guard let samples = InkGeometry.constrainedPoints(stroke) else { throw CommandError.limit(path + "/points") }
        if stroke.kind == .arc || stroke.kind == .wave || stroke.kind == .zigzag || stroke.fill || stroke.arrow != .none {
            for (index, point) in samples.enumerated() where !point.x.isFinite || !point.y.isFinite
                || point.x < -slackX || point.y < -slackY || point.x > width + slackX || point.y > height + slackY {
                throw CommandError.geometry(path + "/points/\(index)")
            }
        }
    }

    private static func checkGeometry(_ operations: [(operation: CanvasOperation, path: String)],
                                      pageBounds: CommandFrame, scope: CommandFrame) throws {
        for (operation, path) in operations {
            if case .drawInk(let drawing, let placement, let frame) = operation, drawing.coordinates == .page {
                guard placement == .atFrame, frame == nil else { throw CommandError.geometry(path + "/frame") }
                try checkPageInk(drawing, path: path, pageBounds: pageBounds, scope: scope)
                continue
            }
            let placement: PlacementHint, frame: CommandFrame?
            switch operation {
            case .addObject(_, _, let objectPlacement, let objectFrame): (placement, frame) = (objectPlacement, objectFrame)
            case .drawInk(_, let inkPlacement, let inkFrame): (placement, frame) = (inkPlacement, inkFrame)
            default: continue
            }
            guard let frame else {
                if placement == .atFrame { throw CommandError.geometry(path + "/frame") }
                continue
            }
            guard placement == .atFrame else { throw CommandError.geometry(path + "/frame") }
            for (key, value) in [("x", frame.x), ("y", frame.y), ("width", frame.width), ("height", frame.height)]
            where !value.isFinite {
                throw CommandError.geometry(path + "/frame/" + key)
            }
            guard frame.width >= CommandLimits.minFrameSide, frame.width <= pageBounds.width else {
                throw CommandError.geometry(path + "/frame/width")
            }
            guard frame.height >= CommandLimits.minFrameSide, frame.height <= pageBounds.height else {
                throw CommandError.geometry(path + "/frame/height")
            }
            guard pageBounds.contains(frame) else { throw CommandError.geometry(path + "/frame") }
        }
    }

    /// Page-coordinate ink is absolute. Every drawn point must be on the page and near the capture.
    private static func checkPageInk(_ drawing: InkDrawing, path: String, pageBounds: CommandFrame, scope: CommandFrame) throws {
        let near = scope.outset(by: CommandLimits.pageInkReach)
        func inside(_ point: CommandPoint, _ pointPath: String) throws {
            guard point.x.isFinite, point.y.isFinite, pageBounds.contains(x: point.x, y: point.y),
                  near.contains(x: point.x, y: point.y) else {
                throw CommandError.geometry(pointPath)
            }
        }
        for (index, stroke) in drawing.strokes.enumerated() {
            guard let samples = InkGeometry.constrainedPoints(stroke) else {
                throw CommandError.limit(path + "/strokes/\(index)/points")
            }
            for (pointIndex, point) in samples.enumerated() {
                try inside(point, path + "/strokes/\(index)/points/\(pointIndex)")
            }
        }
        for (index, label) in drawing.labels.enumerated() {
            try inside(label.at, path + "/labels/\(index)/x")
        }
    }
}
