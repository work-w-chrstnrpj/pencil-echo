import Foundation
import Testing
@testable import PencilEcho

// Cases from the "Test cases" table in docs/api/canvas-commands-v1.md (ticket 006).
struct CommandValidatorTests {
    let objectInScope = UUID()
    let context: CommandRequestContext
    let state: DocumentValidationState

    init() {
        context = CommandRequestContext(
            requestId: UUID(), documentId: UUID(), pageId: UUID(), capturedRevision: 7,
            scopeFrame: CommandFrame(x: 50, y: 50, width: 300, height: 200),
            scopeObjectIds: [objectInScope],
            pageBounds: CommandFrame(x: 0, y: 0, width: 595, height: 842),
            allowReplace: false)
        state = DocumentValidationState(currentRevision: 7, scopeChanged: false,
                                        existingObjectIds: [objectInScope], appliedRequestIds: [])
    }

    // MARK: Helpers

    static func add(type: String = "markdown", source: String = "$x = 4$",
                    placement: String = "right_of_scope", frame: String = "null") -> String {
        #"{"op":"add_object","type":"\#(type)","source":"\#(source)","placement":"\#(placement)","frame":\#(frame)}"#
    }

    static func answer(_ operations: [String], version: String = "1", message: String = "null") -> Data {
        Data(#"{"version":\#(version),"operations":[\#(operations.joined(separator: ","))],"message":\#(message)}"#.utf8)
    }

    func validate(_ raw: Data, context: CommandRequestContext? = nil,
                  state: DocumentValidationState? = nil) -> ValidationResult {
        CommandValidator.validate(raw, context: context ?? self.context, state: state ?? self.state)
    }

    // MARK: Valid

    @Test func validAdd() {
        #expect(validate(Self.answer([Self.add()], message: #""Solved for x.""#)) ==
            .valid([.addObject(type: .markdown, source: "$x = 4$", placement: .rightOfScope, frame: nil)]))
    }

    @Test func validAtFrame() {
        let raw = Self.answer([Self.add(type: "latex", source: "5", placement: "at_frame",
                                        frame: #"{"x":200,"y":100,"width":40,"height":32}"#)])
        #expect(validate(raw) == .valid([.addObject(type: .latex, source: "5", placement: .atFrame,
                                                    frame: CommandFrame(x: 200, y: 100, width: 40, height: 32))]))
    }

    @Test func changedOutsideScopeIsValid() {
        var changed = state
        changed.currentRevision = 9
        guard case .valid = validate(Self.answer([Self.add()]), state: changed) else {
            Issue.record("expected valid"); return
        }
    }

    // MARK: Limits

    @Test func oversizeSource() {
        let raw = Self.answer([Self.add(source: String(repeating: "a", count: CommandLimits.maxSourceBytes + 1))])
        #expect(validate(raw) == .invalid(.limit("/operations/0/source")))
    }

    @Test func sourceAtLimitIsValid() {
        let raw = Self.answer([Self.add(source: String(repeating: "a", count: CommandLimits.maxSourceBytes))])
        guard case .valid = validate(raw) else { Issue.record("expected valid"); return }
    }

    @Test func whitespaceSource() {
        #expect(validate(Self.answer([Self.add(source: "  \\n ")])) == .invalid(.limit("/operations/0/source")))
    }

    @Test func tooManyOperations() {
        let raw = Self.answer(Array(repeating: Self.add(), count: CommandLimits.maxOperations + 1))
        #expect(validate(raw) == .invalid(.limit("/operations")))
    }

    @Test func zeroOperations() {
        #expect(validate(Self.answer([])) == .invalid(.limit("/operations")))
    }

    @Test func oversizeMessage() {
        let message = "\"" + String(repeating: "m", count: CommandLimits.maxMessageBytes + 1) + "\""
        #expect(validate(Self.answer([Self.add()], message: message)) == .invalid(.limit("/message")))
    }

    @Test func responseTooLarge() {
        var raw = Self.answer([Self.add()])
        raw.append(Data(repeating: 0x20, count: CommandLimits.maxResponseBytes))
        #expect(validate(raw) == .invalid(.responseTooLarge))
    }

    // MARK: Schema

    @Test func unknownType() {
        #expect(validate(Self.answer([Self.add(type: "image")])) == .invalid(.schema("/operations/0/type")))
    }

    @Test func unknownOperation() {
        #expect(validate(Self.answer([#"{"op":"move_object","objectId":"x"}"#])) ==
            .invalid(.schema("/operations/0/op")))
    }

    @Test func unknownField() {
        let operation = #"{"op":"add_object","type":"text","source":"hi","placement":"below_scope","frame":null,"color":"red"}"#
        #expect(validate(Self.answer([operation])) == .invalid(.schema("/operations/0/color")))
    }

    @Test func unknownEnvelopeField() {
        let raw = Data(#"{"version":1,"operations":[\#(Self.add())],"message":null,"requestId":"abc"}"#.utf8)
        #expect(validate(raw) == .invalid(.schema("/requestId")))
    }

    @Test func missingField() {
        let operation = #"{"op":"add_object","type":"text","source":"hi","placement":"below_scope"}"#
        #expect(validate(Self.answer([operation])) == .invalid(.schema("/operations/0/frame")))
    }

    @Test func wrongVersion() {
        #expect(validate(Self.answer([Self.add()], version: "4")) == .invalid(.schema("/version")))
        #expect(validate(Self.answer([Self.add()], version: "3")) != .invalid(.schema("/version")))
        #expect(validate(Self.answer([Self.add()], version: "2")) != .invalid(.schema("/version")))
        #expect(validate(Self.answer([Self.add()], version: "true")) == .invalid(.schema("/version")))
    }

    // MARK: Geometry

    @Test func frameOutsidePage() {
        let raw = Self.answer([Self.add(placement: "at_frame", frame: #"{"x":560,"y":10,"width":40,"height":40}"#)])
        #expect(validate(raw) == .invalid(.geometry("/operations/0/frame")))
    }

    @Test func frameTooSmall() {
        let raw = Self.answer([Self.add(placement: "at_frame", frame: #"{"x":10,"y":10,"width":4,"height":40}"#)])
        #expect(validate(raw) == .invalid(.geometry("/operations/0/frame/width")))
    }

    @Test func nonFiniteFrame() {
        let raw = Self.answer([Self.add(placement: "at_frame", frame: #"{"x":10,"y":10,"width":1e400,"height":40}"#)])
        let result = validate(raw)
        #expect(result == .invalid(.malformedJSON) || result == .invalid(.geometry("/operations/0/frame/width")))
    }

    @Test func placementFrameMismatch() {
        let withFrame = Self.answer([Self.add(placement: "below_scope", frame: #"{"x":10,"y":10,"width":40,"height":40}"#)])
        #expect(validate(withFrame) == .invalid(.geometry("/operations/0/frame")))
        #expect(validate(Self.answer([Self.add(placement: "at_frame")])) == .invalid(.geometry("/operations/0/frame")))
    }

    // MARK: Authorization

    func edit(_ id: UUID) -> String {
        #"{"op":"edit_object","objectId":"\#(id.uuidString)","source":"new"}"#
    }

    @Test func editWithoutAuthorization() {
        #expect(validate(Self.answer([edit(objectInScope)])) == .invalid(.notAuthorized("/operations/0")))
    }

    @Test func editOutOfScope() {
        var allowed = context
        allowed.allowReplace = true
        #expect(validate(Self.answer([edit(UUID())]), context: allowed) ==
            .invalid(.outOfScope("/operations/0/objectId")))
    }

    @Test func editTargetGone() {
        var allowed = context
        allowed.allowReplace = true
        var gone = state
        gone.existingObjectIds = []
        #expect(validate(Self.answer([edit(objectInScope)]), context: allowed, state: gone) ==
            .needsReview([.editObject(objectId: objectInScope, source: "new")], .targetMissing))
    }

    @Test func authorizedEditAndConflict() {
        var allowed = context
        allowed.allowReplace = true
        #expect(validate(Self.answer([edit(objectInScope)]), context: allowed) ==
            .valid([.editObject(objectId: objectInScope, source: "new")]))
        let delete = #"{"op":"delete_object","objectId":"\#(objectInScope.uuidString)"}"#
        #expect(validate(Self.answer([edit(objectInScope), delete]), context: allowed) ==
            .invalid(.conflictingOperations("/operations/1/objectId")))
    }

    // MARK: Staleness, duplicates, parsing

    @Test func staleInScope() {
        var changed = state
        changed.currentRevision = 8
        changed.scopeChanged = true
        #expect(validate(Self.answer([Self.add()]), state: changed) ==
            .needsReview([.addObject(type: .markdown, source: "$x = 4$", placement: .rightOfScope, frame: nil)],
                         .scopeChanged))
    }

    @Test func duplicateRequest() {
        var applied = state
        applied.appliedRequestIds = [context.requestId]
        #expect(validate(Self.answer([Self.add()]), state: applied) == .duplicate)
    }

    @Test func malformedJSON() {
        let full = String(decoding: Self.answer([Self.add()]), as: UTF8.self)
        #expect(validate(Data(full.dropLast(5).utf8)) == .invalid(.malformedJSON))
        #expect(validate(Data(("Here you go: " + full).utf8)) == .invalid(.malformedJSON))
        #expect(validate(Data("[1,2]".utf8)) == .invalid(.malformedJSON))
    }

    @Test func deterministicWithoutSideEffects() {
        let raw = Self.answer([Self.add()])
        let (contextBefore, stateBefore) = (context, state)
        #expect(validate(raw) == validate(raw))
        #expect(context == contextBefore && state == stateBefore)
    }

    // MARK: Provider schema agreement

    @Test func providerSchemaMatchesSwiftEnums() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("shared/schemas/canvas-commands-v1.json")
        let text = try String(contentsOf: url, encoding: .utf8)
        let names = CanvasOperation.opNames + CanvasObjectType.allCases.map(\.rawValue) +
            PlacementHint.allCases.map(\.rawValue) + InkStrokeSpec.Kind.allCases.map(\.rawValue) +
            InkStrokeSpec.Arrow.allCases.map(\.rawValue) + InkCoordinates.allCases.map(\.rawValue) +
            InkLabel.Kind.allCases.map(\.rawValue)
        for name in names {
            #expect(text.contains("\"\(name)\""), "schema is missing \(name)")
        }
        let schema = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let operations = try #require((schema["properties"] as? [String: Any])?["operations"] as? [String: Any])
        let draw = try #require((operations["items"] as? [String: Any])?["anyOf"] as? [[String: Any]])
            .first { ($0["properties"] as? [String: Any])?["op"] != nil && text.contains("draw_ink") &&
                (($0["properties"] as? [String: Any])?["strokes"] != nil) }
        #expect(draw?["additionalProperties"] as? Bool == false)
        let stroke = try #require((((draw?["properties"] as? [String: Any])?["strokes"] as? [String: Any])?["items"] as? [String: Any]))
        #expect(stroke["additionalProperties"] as? Bool == false)
        let fields = try #require(stroke["properties"] as? [String: Any])
        #expect(fields["arrow"] != nil && fields["fill"] != nil && fields["wavelength"] != nil && fields["sweep"] != nil)
        #expect(fields["mystery"] == nil)
    }
}

// Ticket 018 and 019: diagram strokes, labels, and page-coordinate ink.
struct DiagramCommandTests {
    let base = CommandValidatorTests()

    func validate(_ operations: [String], version: String = "3") -> ValidationResult {
        base.validate(CommandValidatorTests.answer(operations, version: version))
    }

    func stroke(_ body: String) -> String {
        VisualCommandTests.ink(strokes: "[\(body)]")
    }

    @Test func version2DrawingStillValidates() {
        guard case .valid(let operations) = validate([VisualCommandTests.ink()], version: "2") else {
            Issue.record("expected valid"); return
        }
        guard case .drawInk(let drawing, _, _) = operations[0] else { Issue.record("expected ink"); return }
        #expect(drawing.coordinates == .local && drawing.labels.isEmpty && drawing.strokes[0].arrow == .none)
    }

    @Test func newKindsAndFieldsNeedVersion3() {
        let arc = #"{"kind":"arc","points":[],"closed":false,"color":"black","size":3,"center":[40,40],"radiusX":20,"radiusY":10,"startAngle":0,"sweep":90}"#
        #expect(validate([stroke(arc)], version: "2") == .invalid(.schema("/operations/0/strokes/0/kind")))
        let arrow = #"{"kind":"line","points":[[0,0],[40,0]],"closed":false,"color":"black","size":3,"arrow":"end"}"#
        #expect(validate([stroke(arrow)], version: "2") == .invalid(.schema("/operations/0/strokes/0/arrow")))
        let labeled = VisualCommandTests.ink().dropLast() + #","labels":[]}"#
        #expect(validate([String(labeled)], version: "2") == .invalid(.schema("/operations/0/labels")))
    }

    @Test func rejectsMalformedDiagramValues() {
        let badSweep = #"{"kind":"arc","points":[],"closed":false,"color":"black","size":3,"center":[40,40],"radiusX":20,"radiusY":10,"startAngle":0,"sweep":0}"#
        #expect(validate([stroke(badSweep)]) == .invalid(.limit("/operations/0/strokes/0/sweep")))
        // 1e400 overflows JSON number parsing, so the whole answer is malformed.
        // A finite angle outside -1080...1080 is a limit error on the sweep.
        let overflow = #"{"kind":"arc","points":[],"closed":false,"color":"black","size":3,"center":[40,40],"radiusX":20,"radiusY":10,"startAngle":0,"sweep":1e400}"#
        let overflowResult = validate([stroke(overflow)])
        #expect(overflowResult == .invalid(.malformedJSON) || overflowResult == .invalid(.limit("/operations/0/strokes/0/sweep")))
        let huge = #"{"kind":"arc","points":[],"closed":false,"color":"black","size":3,"center":[40,40],"radiusX":20,"radiusY":10,"startAngle":0,"sweep":5000}"#
        #expect(validate([stroke(huge)]) == .invalid(.limit("/operations/0/strokes/0/sweep")))
        let negative = #"{"kind":"wave","points":[[0,20],[80,20]],"closed":false,"color":"black","size":3,"amplitude":-2,"wavelength":20}"#
        #expect(validate([stroke(negative)]) == .invalid(.limit("/operations/0/strokes/0/amplitude")))
        let unknown = #"{"kind":"line","points":[[0,0],[10,0]],"closed":false,"color":"black","size":3,"arrow":"sideways"}"#
        #expect(validate([stroke(unknown)]) == .invalid(.schema("/operations/0/strokes/0/arrow")))
        let filled = #"{"kind":"line","points":[[0,0],[10,0]],"closed":false,"color":"black","size":3,"fill":"yes"}"#
        #expect(validate([stroke(filled)]) == .invalid(.schema("/operations/0/strokes/0/fill")))
        let extra = #"{"kind":"line","points":[[0,0],[10,0]],"closed":false,"color":"black","size":3,"dash":true}"#
        #expect(validate([stroke(extra)]) == .invalid(.schema("/operations/0/strokes/0/dash")))
        let long = String(repeating: "a", count: CommandLimits.maxInkLabelBytes + 1)
        let label = VisualCommandTests.ink().dropLast() + #","labels":[{"kind":"text","text":"\#(long)","x":10,"y":10}]}"#
        #expect(validate([String(label)]) == .invalid(.limit("/operations/0/labels/0/text")))
        let many = (0..<17).map { #"{"kind":"text","text":"n","x":\#($0),"y":1}"# }.joined(separator: ",")
        let tooMany = VisualCommandTests.ink().dropLast() + #","labels":[\#(many)]}"#
        #expect(validate([String(tooMany)]) == .invalid(.limit("/operations/0/labels")))
        let outside = #"{"kind":"wave","points":[[0,10],[90,10]],"closed":false,"color":"black","size":3,"amplitude":40,"wavelength":20}"#
        #expect(validate([stroke(outside)]) == .invalid(.geometry("/operations/0/strokes/0/points/0"))
                || validate([stroke(outside)]) == .invalid(.geometry("/operations/0/strokes/0/points/1"))
                || { if case .invalid(.geometry) = validate([stroke(outside)]) { return true }; return false }())
        let spine = #"{"kind":"wave","points":[[0,50],[2000,50]],"closed":false,"color":"black","size":3,"amplitude":10,"wavelength":4}"#
        #expect(validate([VisualCommandTests.ink(strokes: "[\(spine)]", width: 2000, height: 200)]) == .invalid(.limit("/operations/0/strokes/0/points"))
                || validate([VisualCommandTests.ink(strokes: "[\(spine)]", width: 2000, height: 200)]) == .invalid(.limit("/operations/0/strokes")))
    }

    @Test func pageInkMustStayOnThePageAndNearTheCapture() {
        let near = #"{"op":"draw_ink","coordinates":"page","width":null,"height":null,"strokes":[{"kind":"line","points":[[80,80],[200,120]],"closed":false,"color":"red","size":3}],"labels":[],"placement":"at_frame","frame":null}"#
        guard case .valid(let operations) = validate([near]) else { Issue.record("expected valid"); return }
        guard case .drawInk(let drawing, .atFrame, nil) = operations[0] else { Issue.record("expected page ink"); return }
        #expect(drawing.coordinates == .page && drawing.strokes[0].points[1].x == 200)
        let far = #"{"op":"draw_ink","coordinates":"page","width":null,"height":null,"strokes":[{"kind":"line","points":[[80,80],[520,400]],"closed":false,"color":"red","size":3}],"labels":[],"placement":"at_frame","frame":null}"#
        #expect(validate([far]) == .invalid(.geometry("/operations/0/strokes/0/points/1"))
                || { if case .invalid(.geometry) = validate([far]) { return true }; return false }())
        let off = #"{"op":"draw_ink","coordinates":"page","width":null,"height":null,"strokes":[{"kind":"line","points":[[80,80],[-20,80]],"closed":false,"color":"red","size":3}],"labels":[],"placement":"at_frame","frame":null}"#
        guard case .invalid(.geometry) = validate([off]) else { Issue.record("expected geometry"); return }
        let boxed = #"{"op":"draw_ink","coordinates":"page","width":100,"height":100,"strokes":[{"kind":"line","points":[[80,80],[120,80]],"closed":false,"color":"red","size":3}],"labels":[],"placement":"at_frame","frame":null}"#
        #expect(validate([boxed]) == .invalid(.schema("/operations/0/width")))
    }
}

// Ticket 016: version 2 plot objects and draw_ink, and the bounded plot grammar.
struct VisualCommandTests {
    let base = CommandValidatorTests()

    static func ink(strokes: String = #"[{"kind":"smooth","points":[[10,10],[50,40],[90,10]],"closed":false,"color":"black","size":3}]"#,
                    width: Double = 100, height: Double = 60, placement: String = "right_of_scope", frame: String = "null") -> String {
        #"{"op":"draw_ink","width":\#(width),"height":\#(height),"strokes":\#(strokes),"placement":"\#(placement)","frame":\#(frame)}"#
    }

    func validate(_ operations: [String], version: String = "2") -> ValidationResult {
        base.validate(CommandValidatorTests.answer(operations, version: version))
    }

    @Test func validInkAndPlot() {
        let plot = CommandValidatorTests.add(type: "plot", source: #"y = x^2\nx: -3 .. 3"#)
        guard case .valid(let operations) = validate([Self.ink(), plot]) else { Issue.record("expected valid"); return }
        guard case .drawInk(let drawing, .rightOfScope, nil) = operations[0] else { Issue.record("expected ink"); return }
        #expect(drawing.width == 100 && drawing.strokes.first?.points.count == 3 && drawing.strokes.first?.kind == .smooth)
        #expect(operations[1] == .addObject(type: .plot, source: "y = x^2\nx: -3 .. 3", placement: .rightOfScope, frame: nil))
    }

    @Test func newTypesNeedVersion2() {
        #expect(validate([Self.ink()], version: "1") == .invalid(.schema("/operations/0/op")))
        #expect(validate([CommandValidatorTests.add(type: "plot", source: "y = x")], version: "1") == .invalid(.schema("/operations/0/type")))
    }

    @Test func badPlotSourceIsRejected() {
        #expect(validate([CommandValidatorTests.add(type: "plot", source: "y = import(x)")]) == .invalid(.schema("/operations/0/source")))
        #expect(validate([CommandValidatorTests.add(type: "plot", source: "x: 5 .. 1")]) == .invalid(.schema("/operations/0/source")))
    }

    @Test func inkLimitsAndShape() {
        let outside = #"[{"kind":"line","points":[[0,0],[500,10]],"closed":false,"color":"black","size":3}]"#
        #expect(validate([Self.ink(strokes: outside)]) == .invalid(.geometry("/operations/0/strokes/0/points/1")))
        let ellipse3 = #"[{"kind":"ellipse","points":[[0,0],[10,10],[20,20]],"closed":true,"color":"red","size":3}]"#
        #expect(validate([Self.ink(strokes: ellipse3)]) == .invalid(.limit("/operations/0/strokes/0/points")))
        let fat = #"[{"kind":"line","points":[[0,0],[10,10]],"closed":false,"color":"red","size":40}]"#
        #expect(validate([Self.ink(strokes: fat)]) == .invalid(.limit("/operations/0/strokes/0/size")))
        let color = #"[{"kind":"line","points":[[0,0],[10,10]],"closed":false,"color":"teal","size":3}]"#
        #expect(validate([Self.ink(strokes: color)]) == .invalid(.schema("/operations/0/strokes/0/color")))
        let closedString = #"[{"kind":"line","points":[[0,0],[10,10]],"closed":"no","color":"red","size":3}]"#
        #expect(validate([Self.ink(strokes: closedString)]) == .invalid(.schema("/operations/0/strokes/0/closed")))
        #expect(validate([Self.ink(strokes: "[]")]) == .invalid(.limit("/operations/0/strokes")))
        #expect(validate([Self.ink(width: 4)]) == .invalid(.limit("/operations/0/width")))
        let many = "[" + Array(repeating: #"{"kind":"line","points":[[0,0],[10,10]],"closed":false,"color":"red","size":3}"#, count: 65).joined(separator: ",") + "]"
        #expect(validate([Self.ink(strokes: many)]) == .invalid(.limit("/operations/0/strokes")))
        #expect(validate([Self.ink(placement: "at_frame")]) == .invalid(.geometry("/operations/0/frame")))
        #expect(validate([Self.ink(placement: "at_frame", frame: #"{"x":500,"y":10,"width":200,"height":100}"#)]) ==
                .invalid(.geometry("/operations/0/frame")))
    }

    @Test func mathExpressions() throws {
        func value(_ text: String, _ x: Double) throws -> Double { try MathExpression(text).evaluate(x: x) }
        #expect(try value("x^2", 3) == 9)
        #expect(try value("2x + 1", 2) == 5)
        #expect(try value("-x^2", 3) == -9)
        #expect(try value("2^-1", 0) == 0.5)
        #expect(abs(try value("3sin(x)", .pi / 2) - 3) < 1e-12)
        #expect(abs(try value("sin x", .pi / 2) - 1) < 1e-12)
        #expect(try value("(x+1)(x-1)", 3) == 8)
        #expect(abs(try value("2pi", 0) - 2 * .pi) < 1e-12)
        #expect(try value("sqrt(abs(x))", -16) == 4)
        #expect(try value("x**3 − 1", 2) == 7)
        #expect(try value("ln(e)", 0) == 1 && value("log(100)", 0) == 2)
        #expect(throws: MathExpression.ParseError.self) { try MathExpression("system(x)") }
        #expect(throws: MathExpression.ParseError.self) { try MathExpression("x +") }
        #expect(throws: MathExpression.ParseError.self) { try MathExpression("(x") }
        #expect(throws: MathExpression.ParseError.self) { try MathExpression(String(repeating: "(", count: 40) + "x" + String(repeating: ")", count: 40)) }
        #expect(throws: MathExpression.ParseError.self) { try MathExpression(String(repeating: "x+", count: 200) + "x") }
    }

    @Test func plotSpecFormat() throws {
        let spec = try PlotSpec.parse("title: Waves\ny = sin(x)\nf(x) = cos(x)\nx: -pi .. pi\ny: -1.5 to 1.5")
        #expect(spec.title == "Waves" && spec.functions == ["sin(x)", "cos(x)"])
        #expect(abs(spec.xRange.lowerBound + .pi) < 1e-12 && spec.yRange == -1.5...1.5)
        let bare = try PlotSpec.parse("x^2 - 4")
        #expect(bare.functions == ["x^2 - 4"] && bare.xRange == PlotSpec.defaultX && bare.yRange == nil)
        #expect(throws: PlotSpec.ParseError.empty) { try PlotSpec.parse("title: nothing") }
        #expect(throws: PlotSpec.ParseError.tooManyFunctions) { try PlotSpec.parse("x\nx\nx\nx\nx") }
        #expect(throws: PlotSpec.ParseError.self) { try PlotSpec.parse("y = x\nx: 1 .. 1") }
    }
}
