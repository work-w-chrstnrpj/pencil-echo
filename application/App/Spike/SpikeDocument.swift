#if DEBUG
import PencilKit

struct SpikeObject: Identifiable {
    enum Kind { case text, image, box }
    let id: UUID
    var kind: Kind
    var frame: CGRect
    var text: String

    init(kind: Kind, frame: CGRect, text: String = "") {
        id = UUID()
        self.kind = kind
        self.frame = frame
        self.text = text
    }
}

struct SpikeSnapshot {
    var drawing: PKDrawing
    var objects: [SpikeObject]
}

/// Synthetic content only. No document storage, upstream assets or provider calls.
enum SpikeFixtures {
    static func stroke(_ points: [CGPoint], color: UIColor = .black, width: CGFloat = 4) -> PKStroke {
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) / 60,
                          size: CGSize(width: width, height: width), opacity: 1,
                          force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: color),
                        path: PKStrokePath(controlPoints: controls, creationDate: Date(timeIntervalSince1970: 0)))
    }

    static func baseline() -> SpikeSnapshot {
        SpikeSnapshot(drawing: PKDrawing(strokes: [
            stroke([CGPoint(x: 140, y: 270), CGPoint(x: 280, y: 270), CGPoint(x: 420, y: 270)]),
            stroke([CGPoint(x: 140, y: 390), CGPoint(x: 300, y: 460), CGPoint(x: 440, y: 530)], color: .systemRed)
        ]), objects: [
            SpikeObject(kind: .text, frame: CGRect(x: 160, y: 180, width: 240, height: 100), text: "Editable label\nInk underline at y = 270"),
            SpikeObject(kind: .image, frame: CGRect(x: 480, y: 180, width: 120, height: 120), text: "Demo image"),
            SpikeObject(kind: .box, frame: CGRect(x: 160, y: 400, width: 260, height: 120), text: "Opaque box: compare ink order")
        ])
    }

    static func stress() -> SpikeSnapshot {
        let strokes = (0..<2_000).map { index in
            let origin = CGPoint(x: 40 + (index % 40) * 95, y: 40 + (index / 40) * 75)
            let points = (0..<24).map { step in
                CGPoint(x: origin.x + CGFloat(step) * 3,
                        y: origin.y + sin(CGFloat(step) * .pi / 6) * 12)
            }
            return stroke(points, color: index.isMultiple(of: 2) ? .black : .systemBlue)
        }
        let objects = (0..<50).map { index in
            SpikeObject(kind: index.isMultiple(of: 3) ? .image : (index.isMultiple(of: 2) ? .text : .box),
                        frame: CGRect(x: 60 + (index % 10) * 380, y: 60 + (index / 10) * 720,
                                      width: 220, height: 100), text: "Object \(index + 1)")
        }
        return SpikeSnapshot(drawing: PKDrawing(strokes: strokes), objects: objects)
    }
}

/// The same manager is returned by the PKCanvasView subclass. Native PencilKit
/// tool edits use its normal undo path; custom edits restore a complete snapshot
/// with registration suppressed to avoid duplicate programmatic drawing entries.
@MainActor
final class SpikeHistory {
    let manager = UndoManager()
    private let canvas: SpikeCanvasView
    private(set) var objects: [SpikeObject] = []
    var didChange: (() -> Void)?

    init(canvas: SpikeCanvasView) {
        self.canvas = canvas
        manager.groupsByEvent = false
        manager.levelsOfUndo = 50
        canvas.documentUndoManager = manager
    }

    var snapshot: SpikeSnapshot { SpikeSnapshot(drawing: canvas.drawing, objects: objects) }

    func load(_ state: SpikeSnapshot) {
        apply(state)
        manager.removeAllActions()
    }

    /// Preview does not enter history; the gesture records one command on end.
    func apply(_ state: SpikeSnapshot) {
        manager.disableUndoRegistration()
        canvas.drawing = state.drawing
        objects = state.objects
        manager.enableUndoRegistration()
        didChange?()
    }

    func commit(_ state: SpikeSnapshot, named name: String) {
        let old = snapshot
        manager.beginUndoGrouping()
        registerRestore(old, named: name)
        apply(state)
        manager.endUndoGrouping()
    }

    private func registerRestore(_ state: SpikeSnapshot, named name: String) {
        manager.registerUndo(withTarget: self) { target in
            let inverse = target.snapshot
            target.registerRestore(inverse, named: name)
            target.apply(state)
        }
        manager.setActionName(name)
    }
}

@MainActor
final class SpikeCanvasView: PKCanvasView {
    var documentUndoManager: UndoManager?
    override var undoManager: UndoManager? { documentUndoManager ?? super.undoManager }
}
#endif
