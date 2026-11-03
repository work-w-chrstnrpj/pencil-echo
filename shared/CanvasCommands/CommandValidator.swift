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
            try checkGeometry(parsed.operations, pageBounds: context.pageBounds)
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
    private static let frameKeys: Set<String> = ["x", "y", "width", "height"]
    private static let strokeKeys: Set<String> = ["kind", "points", "closed", "color", "size"]

    private static func parse(_ root: [String: Any]) throws -> Parsed {
        try requireExactKeys(root, envelopeKeys, path: "")
        // Version 2 (ticket 016) adds `plot` objects and `draw_ink`; version 1 answers stay valid.
        guard let version = number(root["version"]), version == 1 || version == 2 else { throw CommandError.schema("/version") }
        guard let rawOperations = root["operations"] as? [Any] else { throw CommandError.schema("/operations") }
        let message = try nullableString(root["message"], path: "/message")

        let operations = try rawOperations.enumerated().map { index, value -> (operation: CanvasOperation, path: String) in
            let path = "/operations/\(index)"
            let operation = try parseOperation(value, path: path)
            if version == 1 {
                if case .drawInk = operation { throw CommandError.schema(path + "/op") }
                if case .addObject(.plot, _, _, _) = operation { throw CommandError.schema(path + "/type") }
            }
            return (operation: operation, path: path)
        }
        return Parsed(operations: operations, message: message)
    }

    private static func parseOperation(_ value: Any, path: String) throws -> CanvasOperation {
        guard let object = value as? [String: Any] else { throw CommandError.schema(path) }
        guard let op = object["op"] as? String, let keys = operationKeys[op] else {
            throw CommandError.schema(path + "/op")
        }
        try requireExactKeys(object, keys, path: path)

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
            guard let width = number(object["width"]) else { throw CommandError.schema(path + "/width") }
            guard let height = number(object["height"]) else { throw CommandError.schema(path + "/height") }
            guard let strokes = object["strokes"] as? [Any] else { throw CommandError.schema(path + "/strokes") }
            let drawing = InkDrawing(width: width, height: height, strokes: try strokes.enumerated().map { index, value in
                try parseStroke(value, path: path + "/strokes/\(index)")
            })
            return .drawInk(drawing, placement: placement, frame: try parseFrame(object["frame"], path: path + "/frame"))
        case "edit_object":
            return .editObject(objectId: try uuid(object["objectId"], path: path + "/objectId"),
                               source: try string(object["source"], path: path + "/source"))
        default:
            return .deleteObject(objectId: try uuid(object["objectId"], path: path + "/objectId"))
        }
    }

    private static func parseStroke(_ value: Any, path: String) throws -> InkStrokeSpec {
        guard let object = value as? [String: Any] else { throw CommandError.schema(path) }
        try requireExactKeys(object, strokeKeys, path: path)
        guard let kind = (object["kind"] as? String).flatMap(InkStrokeSpec.Kind.init(rawValue:)) else {
            throw CommandError.schema(path + "/kind")
        }
        guard let color = (object["color"] as? String).flatMap(InkStrokeSpec.Color.init(rawValue:)) else {
            throw CommandError.schema(path + "/color")
        }
        guard let closedValue = object["closed"] as? NSNumber, CFGetTypeID(closedValue) == CFBooleanGetTypeID() else {
            throw CommandError.schema(path + "/closed")
        }
        let closed = closedValue.boolValue
        guard let size = number(object["size"]) else { throw CommandError.schema(path + "/size") }
        guard let rawPoints = object["points"] as? [Any] else { throw CommandError.schema(path + "/points") }
        let points = try rawPoints.enumerated().map { index, value -> CommandPoint in
            guard let pair = value as? [Any], pair.count == 2, let x = number(pair[0]), let y = number(pair[1]) else {
                throw CommandError.schema(path + "/points/\(index)")
            }
            return CommandPoint(x: x, y: y)
        }
        return InkStrokeSpec(kind: kind, points: points, closed: closed, color: color, size: size)
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
        if let unknown = object.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw CommandError.schema(path + "/" + unknown)
        }
        if let missing = allowed.sorted().first(where: { object[$0] == nil }) {
            throw CommandError.schema(path + "/" + missing)
        }
    }

    private static func number(_ value: Any?) -> Double? {
        // JSONSerialization represents booleans as NSNumber too.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
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
        guard drawing.width.isFinite, CommandLimits.inkBoxSides.contains(drawing.width) else { throw CommandError.limit(path + "/width") }
        guard drawing.height.isFinite, CommandLimits.inkBoxSides.contains(drawing.height) else { throw CommandError.limit(path + "/height") }
        guard (1...CommandLimits.maxInkStrokes).contains(drawing.strokes.count) else { throw CommandError.limit(path + "/strokes") }
        guard drawing.strokes.map(\.points.count).reduce(0, +) <= CommandLimits.maxInkPoints else {
            throw CommandError.limit(path + "/strokes")
        }
        // Points may sit up to 1% outside the box: models round coordinates.
        let slackX = drawing.width * 0.01, slackY = drawing.height * 0.01
        for (index, stroke) in drawing.strokes.enumerated() {
            let strokePath = path + "/strokes/\(index)"
            let count = stroke.points.count
            let validCount = switch stroke.kind {
            case .line, .ellipse: count == 2
            case .polyline, .smooth: (2...CommandLimits.maxInkStrokePoints).contains(count)
            }
            guard validCount else { throw CommandError.limit(strokePath + "/points") }
            guard stroke.size.isFinite, CommandLimits.inkStrokeSizes.contains(stroke.size) else {
                throw CommandError.limit(strokePath + "/size")
            }
            for (pointIndex, point) in stroke.points.enumerated() {
                guard point.x.isFinite, point.y.isFinite, point.x >= -slackX, point.y >= -slackY,
                      point.x <= drawing.width + slackX, point.y <= drawing.height + slackY else {
                    throw CommandError.geometry(strokePath + "/points/\(pointIndex)")
                }
            }
        }
    }

    private static func checkGeometry(_ operations: [(operation: CanvasOperation, path: String)],
                                      pageBounds: CommandFrame) throws {
        for (operation, path) in operations {
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
}
