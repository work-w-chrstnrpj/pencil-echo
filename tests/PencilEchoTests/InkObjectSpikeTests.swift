#if DEBUG
import Testing
import PencilKit
@testable import PencilEcho

@MainActor
struct InkObjectSpikeTests {
    private let polygon = [CGPoint(x: 100, y: 150), CGPoint(x: 450, y: 150),
                           CGPoint(x: 450, y: 300), CGPoint(x: 100, y: 300)]

    @Test func coordinateRoundTripAtZoomExtremes() {
        for zoom: CGFloat in [0.25, 1, 4] {
            for offset in [CGPoint.zero, CGPoint(x: 340, y: 910)] {
                let point = CGPoint(x: 232, y: 489)
                let viewport = SpikeGeometry.viewport(point, zoom: zoom, offset: offset)
                let result = SpikeGeometry.document(viewport, zoom: zoom, offset: offset)
                #expect(abs(result.x - point.x) < 0.00001)
                #expect(abs(result.y - point.y) < 0.00001)
            }
        }
    }

    @Test func lassoUsesVisibleTransformedPathsNotBoundingBoxes() {
        var stroke = SpikeFixtures.stroke([CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0), CGPoint(x: 120, y: 0)])
        stroke.transform = CGAffineTransform(translationX: 130, y: 240)
        #expect(SpikeGeometry.intersects(stroke, polygon: polygon))
        let diagonal = SpikeFixtures.stroke([CGPoint(x: 0, y: 0), CGPoint(x: 250, y: 250), CGPoint(x: 500, y: 500)])
        let emptyCorner = [CGPoint(x: 10, y: 400), CGPoint(x: 100, y: 400), CGPoint(x: 100, y: 480), CGPoint(x: 10, y: 480)]
        #expect(!SpikeGeometry.intersects(diagonal, polygon: emptyCorner))
        let mask = UIBezierPath(rect: CGRect(x: 0, y: -10, width: 30, height: 20))
        stroke.mask = mask
        let hiddenEnd = [CGPoint(x: 210, y: 230), CGPoint(x: 280, y: 230), CGPoint(x: 280, y: 250), CGPoint(x: 210, y: 250)]
        #expect(!SpikeGeometry.intersects(stroke, polygon: hiddenEnd))
    }

    @Test func objectHitTestingIncludesEdgeCrossingAndContainedLasso() {
        #expect(SpikeGeometry.intersects(CGRect(x: 160, y: 180, width: 240, height: 100), polygon: polygon))
        #expect(!SpikeGeometry.intersects(CGRect(x: 480, y: 180, width: 120, height: 120), polygon: polygon))
        #expect(SpikeGeometry.intersects(CGRect(x: 0, y: 0, width: 1_000, height: 1_000), polygon: polygon))
        let stripe = [CGPoint(x: 0, y: 210), CGPoint(x: 600, y: 210), CGPoint(x: 600, y: 220), CGPoint(x: 0, y: 220)]
        #expect(SpikeGeometry.intersects(CGRect(x: 160, y: 180, width: 240, height: 100), polygon: stripe))
        #expect(!SpikeGeometry.intersects(.zero, polygon: []))
    }

    @Test func answerObjectAndInkAreOneUndoStepWithRedo() {
        let controller = InkObjectSpikeController()
        controller.loadViewIfNeeded()
        let old = controller.history.snapshot
        controller.insertAnswer()
        #expect(controller.history.objects.count == old.objects.count + 1)
        #expect(controller.canvas.drawing.strokes.count == old.drawing.strokes.count + 1)
        controller.history.manager.undo()
        #expect(controller.history.objects.count == old.objects.count)
        #expect(controller.canvas.drawing.dataRepresentation() == old.drawing.dataRepresentation())
        #expect(!controller.history.manager.canUndo)
        controller.history.manager.redo()
        #expect(controller.history.objects.count == old.objects.count + 1)
        #expect(controller.canvas.drawing.strokes.count == old.drawing.strokes.count + 1)
    }

    @Test func mixedMovePreservesRelativeGeometryAndUndoesTogether() {
        let controller = InkObjectSpikeController()
        controller.loadViewIfNeeded()
        controller.select(polygon: polygon)
        let old = controller.history.snapshot
        let next = controller.moved(old, delta: CGPoint(x: 75, y: 40))
        #expect(next.objects[0].frame.minX == old.objects[0].frame.minX + 75)
        #expect(next.objects[1].frame == old.objects[1].frame)
        #expect(next.drawing.strokes[0].renderBounds.minX == old.drawing.strokes[0].renderBounds.minX + 75)
        #expect(next.drawing.strokes[1].renderBounds == old.drawing.strokes[1].renderBounds)
        controller.history.commit(next, named: "Move mixed selection")
        controller.history.manager.undo()
        #expect(controller.history.objects[0].frame == old.objects[0].frame)
        #expect(controller.canvas.drawing.dataRepresentation() == old.drawing.dataRepresentation())
        controller.history.manager.redo()
        #expect(controller.history.objects[0].frame == next.objects[0].frame)
        #expect(controller.canvas.drawing.dataRepresentation() == next.drawing.dataRepresentation())
    }

    @Test func groupClampingPreservesSpacingAtDocumentEdges() {
        let bounds = CGRect(x: 100, y: 200, width: 300, height: 100)
        #expect(SpikeGeometry.clampedTranslation(CGPoint(x: -500, y: 5_000), bounds: bounds) == CGPoint(x: -100, y: 3_700))
    }

    @Test func canvasAndObjectsShareManagerAndPublicCoordinateTransform() {
        let controller = InkObjectSpikeController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 820, height: 1_180)
        controller.view.layoutIfNeeded()
        #expect(controller.canvas.undoManager === controller.history.manager)
        #expect(controller.canvas.drawingPolicy == .pencilOnly)
        for size in [CGSize(width: 820, height: 1_180), CGSize(width: 1_180, height: 820)] {
            controller.view.frame.size = size
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            for zoom: CGFloat in [0.25, 1, 4] {
                controller.setViewport(zoom: zoom)
                let actual = controller.objectContainer.convert(CGPoint(x: 300, y: 450), to: controller.viewport)
                let expected = SpikeGeometry.viewport(CGPoint(x: 300, y: 450), zoom: controller.canvas.zoomScale,
                                                      offset: controller.canvas.contentOffset)
                #expect(abs(actual.x - expected.x) < 0.001)
                #expect(abs(actual.y - expected.y) < 0.001)
            }
        }
    }

    @Test func syntheticLoadHasRequiredCountsAndStaysInsideBounds() {
        let state = SpikeFixtures.stress()
        #expect(state.drawing.strokes.count == 2_000)
        #expect(state.objects.count == 50)
        let bounds = CGRect(origin: .zero, size: SpikeGeometry.documentSize)
        #expect(state.objects.allSatisfy { bounds.contains($0.frame) })
        #expect(bounds.contains(state.drawing.bounds))
    }

    @Test func inkOnlyEditsAndAnswerStaySeparateInHistory() {
        // Programmatic ink edits test transaction ordering, not Pencil hardware.
        let canvas = SpikeCanvasView()
        let history = SpikeHistory(canvas: canvas)
        history.load(SpikeSnapshot(drawing: PKDrawing(), objects: []))
        for index in 0..<2 {
            var next = history.snapshot
            next.drawing = PKDrawing(strokes: next.drawing.strokes + [SpikeFixtures.stroke([
                CGPoint(x: 10, y: 10 + index * 20), CGPoint(x: 100, y: 10 + index * 20)
            ])])
            history.commit(next, named: "Synthetic stroke")
        }
        history.manager.undo()
        #expect(canvas.drawing.strokes.count == 1)
        history.manager.undo()
        #expect(canvas.drawing.strokes.isEmpty)
        history.manager.redo()
        #expect(canvas.drawing.strokes.count == 1)
    }

    @Test func lassoGestureSelectsAndMovesBothLayersAsOneUndoStep() {
        let controller = InkObjectSpikeController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 820, height: 1_180)
        controller.view.layoutIfNeeded()
        controller.setViewport(zoom: 1)
        let gesture = SamplePan()
        func send(_ state: UIGestureRecognizer.State, _ point: CGPoint) {
            gesture.sampleState = state
            gesture.samplePoint = SpikeGeometry.viewport(point, zoom: controller.canvas.zoomScale,
                                                         offset: controller.canvas.contentOffset)
            controller.handleLasso(gesture)
        }
        send(.began, polygon[0])
        for point in polygon.dropFirst() { send(.changed, point) }
        send(.ended, polygon[0])
        let old = controller.history.snapshot
        send(.began, CGPoint(x: 250, y: 230))
        send(.changed, CGPoint(x: 325, y: 270))
        send(.ended, CGPoint(x: 325, y: 270))
        #expect(controller.history.objects[0].frame == old.objects[0].frame.offsetBy(dx: 75, dy: 40))
        #expect(controller.canvas.drawing.strokes[0].renderBounds.minY == old.drawing.strokes[0].renderBounds.minY + 40)
        controller.history.manager.undo()
        #expect(controller.history.objects[0].frame == old.objects[0].frame)
        #expect(controller.canvas.drawing.dataRepresentation() == old.drawing.dataRepresentation())
        #expect(!controller.history.manager.canUndo)
    }

    @Test func cancelledMoveRestoresBothLayersWithoutCreatingUndo() {
        let controller = InkObjectSpikeController()
        controller.loadViewIfNeeded()
        controller.select(polygon: polygon)
        let old = controller.history.snapshot
        let gesture = SamplePan()
        for (state, point) in [(UIGestureRecognizer.State.began, CGPoint(x: 250, y: 230)),
                               (.changed, CGPoint(x: 325, y: 270)), (.cancelled, CGPoint(x: 325, y: 270))] {
            gesture.sampleState = state
            gesture.samplePoint = SpikeGeometry.viewport(point, zoom: controller.canvas.zoomScale,
                                                         offset: controller.canvas.contentOffset)
            controller.handleLasso(gesture)
        }
        #expect(controller.history.objects[0].frame == old.objects[0].frame)
        #expect(controller.canvas.drawing.dataRepresentation() == old.drawing.dataRepresentation())
        #expect(!controller.history.manager.canUndo)
    }

}

/// Feeds deterministic gesture states to the real handler. This does not simulate
/// UIKit's touch dispatch, pinch arbitration, or physical Apple Pencil input.
@MainActor
private final class SamplePan: UIPanGestureRecognizer {
    var sampleState: UIGestureRecognizer.State = .possible
    var samplePoint = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { sampleState }
        set { sampleState = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { samplePoint }
}
#endif
