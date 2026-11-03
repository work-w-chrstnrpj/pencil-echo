#if DEBUG
import SwiftUI
import PencilKit

struct InkObjectSpikeView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> InkObjectSpikeController { InkObjectSpikeController() }
    func updateUIViewController(_ controller: InkObjectSpikeController, context: Context) {}
}

@MainActor
final class InkObjectSpikeController: UIViewController, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    let canvas = SpikeCanvasView()
    private(set) lazy var history = SpikeHistory(canvas: canvas)
    let viewport = UIView()
    let objectContainer = UIView()
    private let selectionOverlay = UIView()
    private let selectionShape = CAShapeLayer()
    private let status = UILabel()
    private let metricsLabel = UILabel()
    private let metrics = SpikeMetrics()
    private var objectViews: [UUID: UIView] = [:]
    private var lassoMode = false
    private var inkAbove = true
    private var halted = false
    private var toolGroupOpen = false
    private var selectedStrokes = Set<Int>()
    private var selectedObjects = Set<UUID>()
    private var lassoPoints: [CGPoint] = []
    private var dragStart: CGPoint?
    private var dragSnapshot: SpikeSnapshot?
    private var dragBounds: CGRect?
    private var lastDragDelta = CGPoint.zero
    private var lassoButton: UIButton!
    private var orderButton: UIButton!
    private var undoButton: UIButton!
    private var redoButton: UIButton!
    private var hasInitialViewport = false
    private lazy var lassoPan = UIPanGestureRecognizer(target: self, action: #selector(handleLasso(_:)))
    override var undoManager: UndoManager? { history.manager }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        viewport.backgroundColor = .white
        viewport.clipsToBounds = true
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 4
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.contentSize = SpikeGeometry.documentSize
        canvas.delegate = self
        canvas.accessibilityLabel = "Spike canvas. Pencil draws; fingers pan and zoom."
        objectContainer.isUserInteractionEnabled = false
        objectContainer.layer.anchorPoint = .zero
        objectContainer.bounds = CGRect(origin: .zero, size: SpikeGeometry.documentSize)
        selectionOverlay.isUserInteractionEnabled = false
        selectionShape.strokeColor = UIColor.systemBlue.cgColor
        selectionShape.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
        selectionShape.lineWidth = 2
        selectionShape.lineDashPattern = [6, 4]
        selectionOverlay.layer.addSublayer(selectionShape)
        viewport.addSubview(canvas)
        viewport.addSubview(objectContainer)
        viewport.addSubview(selectionOverlay)
        lassoPan.maximumNumberOfTouches = 1
        lassoPan.delegate = self
        lassoPan.isEnabled = false
        viewport.addGestureRecognizer(lassoPan)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(editText))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        viewport.addGestureRecognizer(doubleTap)

        let firstRow = UIStackView()
        firstRow.spacing = 12
        lassoButton = button("Mode: Ink", in: firstRow) { [weak self] in self?.toggleLasso() }
        _ = button("Pen", in: firstRow) { [weak self] in self?.canvas.tool = PKInkingTool(.pen, color: .black, width: 4) }
        _ = button("Eraser", in: firstRow) { [weak self] in self?.canvas.tool = PKEraserTool(.vector) }
        _ = button("Insert answer", in: firstRow) { [weak self] in self?.insertAnswer() }
        _ = button("Edit text", in: firstRow) { [weak self] in self?.editText() }
        undoButton = button("Undo", in: firstRow) { [weak self] in self?.history.manager.undo(); self?.refreshSelectionAndStatus() }
        redoButton = button("Redo", in: firstRow) { [weak self] in self?.history.manager.redo(); self?.refreshSelectionAndStatus() }
        let secondRow = UIStackView()
        secondRow.spacing = 12
        for scale: CGFloat in [0.25, 1, 4] {
            _ = button("\(scale.formatted())×", in: secondRow) { [weak self] in self?.setViewport(zoom: scale) }
        }
        orderButton = button("Ink above", in: secondRow) { [weak self] in self?.toggleOrder() }
        _ = button("Load 2,000 / 50", in: secondRow) { [weak self] in self?.loadFixture(stress: true) }
        _ = button("Reset sample", in: secondRow) { [weak self] in self?.loadFixture(stress: false) }
        status.font = .preferredFont(forTextStyle: .caption1)
        status.adjustsFontForContentSizeCategory = true
        status.numberOfLines = 2
        metricsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        metricsLabel.numberOfLines = 2
        let stack = UIStackView(arrangedSubviews: [scrollingRow(firstRow), scrollingRow(secondRow), status, metricsLabel, viewport])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            viewport.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])
        history.didChange = { [weak self] in self?.renderObjects(); self?.refreshSelectionAndStatus() }
        metrics.report = { [weak self] message, limit in
            guard let self else { return }
            metricsLabel.text = message
            if limit {
                halted = true
                canvas.isUserInteractionEnabled = false
                lassoPan.isEnabled = false
                metrics.stop()
                status.text = "STOP: memory reached 1 GiB. End the spike and record this failure."
            }
        }
        history.load(ProcessInfo.processInfo.arguments.contains("-spikeStress") ? SpikeFixtures.stress() : SpikeFixtures.baseline())
        setLayerOrder()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvas.becomeFirstResponder()
        if !halted { metrics.start() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        metrics.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        canvas.frame = viewport.bounds
        selectionOverlay.frame = viewport.bounds
        if !hasInitialViewport, viewport.bounds.width > 0 {
            hasInitialViewport = true
            let args = ProcessInfo.processInfo.arguments
            let zoom = args.firstIndex(of: "-spikeZoom").flatMap { index in
                args.indices.contains(index + 1) ? Double(args[index + 1]) : nil
            } ?? 1
            setViewport(zoom: min(4, max(0.25, zoom)))
            if args.contains("-spikeInkBelow") { toggleOrder() }
        }
        synchronizeOverlay()
    }

    private func scrollingRow(_ row: UIStackView) -> UIView {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        NSLayoutConstraint.activate([
            scroll.heightAnchor.constraint(equalToConstant: 44),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        return scroll
    }

    private func button(_ title: String, in row: UIStackView, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        row.addArrangedSubview(button)
        return button
    }

    func setViewport(zoom: CGFloat) {
        // Focus the same known ink/object crossing at all three evidence scales.
        canvas.setZoomScale(zoom, animated: false)
        let focus = CGPoint(x: 300, y: 450)
        let maxX = max(0, SpikeGeometry.documentSize.width * zoom - canvas.bounds.width)
        let maxY = max(0, SpikeGeometry.documentSize.height * zoom - canvas.bounds.height)
        canvas.setContentOffset(CGPoint(x: min(maxX, max(0, focus.x * zoom - canvas.bounds.width / 2)),
                                       y: min(maxY, max(0, focus.y * zoom - canvas.bounds.height / 2))), animated: false)
        synchronizeOverlay()
    }

    func synchronizeOverlay() {
        // Sibling layers use viewport coordinates; do not inspect PencilKit's subviews.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        objectContainer.transform = CGAffineTransform(scaleX: canvas.zoomScale, y: canvas.zoomScale)
        objectContainer.layer.position = CGPoint(x: -canvas.contentOffset.x, y: -canvas.contentOffset.y)
        CATransaction.commit()
        redrawSelection()
        refreshStatus()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { synchronizeOverlay() }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { synchronizeOverlay() }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        clearSelection()
        if !toolGroupOpen {
            history.manager.beginUndoGrouping()
            toolGroupOpen = true
        }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        if toolGroupOpen {
            history.manager.endUndoGrouping()
            toolGroupOpen = false
        }
        refreshStatus()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        // Index selections are valid only until another drawing transaction occurs.
        if dragSnapshot == nil { clearSelection() }
        refreshStatus()
    }

    private func toggleLasso() {
        guard !halted, !toolGroupOpen else { return }
        lassoMode.toggle()
        lassoPan.isEnabled = lassoMode
        canvas.drawingGestureRecognizer.isEnabled = !lassoMode
        canvas.panGestureRecognizer.minimumNumberOfTouches = lassoMode ? 2 : 1
        lassoButton.setTitle(lassoMode ? "Mode: Mixed lasso" : "Mode: Ink", for: .normal)
        clearSelection()
        refreshStatus()
    }

    func toggleOrder() {
        inkAbove.toggle()
        setLayerOrder()
    }

    private func setLayerOrder() {
        if inkAbove { viewport.insertSubview(objectContainer, belowSubview: canvas) }
        else { viewport.insertSubview(objectContainer, aboveSubview: canvas) }
        viewport.bringSubviewToFront(selectionOverlay)
        orderButton?.setTitle(inkAbove ? "Ink above" : "Ink below", for: .normal)
    }

    private func loadFixture(stress: Bool) {
        guard !halted, !toolGroupOpen else { return }
        clearSelection()
        history.load(stress ? SpikeFixtures.stress() : SpikeFixtures.baseline())
        canvas.contentSize = CGSize(width: SpikeGeometry.documentSize.width * canvas.zoomScale,
                                    height: SpikeGeometry.documentSize.height * canvas.zoomScale)
        metrics.start()
        setViewport(zoom: stress ? 0.25 : 1)
    }

    func insertAnswer() {
        guard !halted, !toolGroupOpen else { return }
        clearSelection()
        var next = history.snapshot
        let center = SpikeGeometry.document(CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY),
                                            zoom: canvas.zoomScale, offset: canvas.contentOffset)
        let x = min(3_700, max(0, center.x - 120)), y = min(3_800, max(0, center.y - 50))
        next.objects.append(SpikeObject(kind: .text, frame: CGRect(x: x, y: y, width: 240, height: 100),
                                        text: "Answer placeholder\nDouble-tap to edit"))
        // An object and ink annotation deliberately share a single transaction.
        next.drawing = PKDrawing(strokes: next.drawing.strokes + [SpikeFixtures.stroke([
            CGPoint(x: x, y: y + 105), CGPoint(x: x + 120, y: y + 105), CGPoint(x: x + 240, y: y + 105)
        ], color: .systemBlue)])
        history.commit(next, named: "Insert answer")
        refreshStatus()
    }

    @objc private func editText() {
        guard !halted, !toolGroupOpen else { return }
        let object = history.objects.first { $0.kind == .text && selectedObjects.contains($0.id) } ??
                     history.objects.first { $0.kind == .text }
        guard let object else { return }
        let alert = UIAlertController(title: "Edit sample text", message: "Edits are one undo step. Nothing is saved to disk.", preferredStyle: .alert)
        alert.addTextField { $0.text = object.text }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text,
                  let index = history.objects.firstIndex(where: { $0.id == object.id }),
                  text != history.objects[index].text else { return }
            var next = history.snapshot
            next.objects[index].text = String(text.prefix(2_000))
            clearSelection()
            history.commit(next, named: "Edit text")
        })
        present(alert, animated: true)
    }

    private func renderObjects() {
        let ids = Set(history.objects.map(\.id))
        for (id, item) in objectViews where !ids.contains(id) { item.removeFromSuperview(); objectViews.removeValue(forKey: id) }
        for object in history.objects {
            let item: UIView
            if let existing = objectViews[object.id] { item = existing }
            else {
                if object.kind == .image {
                    let image = UIImageView(image: UIImage(systemName: "scribble.variable"))
                    image.contentMode = .scaleAspectFit
                    image.tintColor = .systemIndigo
                    item = image
                } else {
                    let label = UILabel()
                    label.numberOfLines = 0
                    label.font = .systemFont(ofSize: 20)
                    label.textColor = .black
                    label.textAlignment = .center
                    item = label
                }
                item.isAccessibilityElement = true
                objectContainer.addSubview(item)
                objectViews[object.id] = item
            }
            item.frame = object.frame
            (item as? UILabel)?.text = object.text
            item.backgroundColor = object.kind == .box ? .systemYellow : .white
            item.layer.borderWidth = 1
            item.layer.borderColor = UIColor.gray.cgColor
            item.accessibilityLabel = object.text
        }
    }

    func select(polygon: [CGPoint]) {
        selectedStrokes = Set(canvas.drawing.strokes.indices.filter { SpikeGeometry.intersects(canvas.drawing.strokes[$0], polygon: polygon) })
        selectedObjects = Set(history.objects.filter { SpikeGeometry.intersects($0.frame, polygon: polygon) }.map(\.id))
        redrawSelection()
        refreshStatus()
    }

    private var selectionBounds: CGRect? {
        var bounds = CGRect.null
        for index in selectedStrokes where canvas.drawing.strokes.indices.contains(index) {
            bounds = bounds.union(canvas.drawing.strokes[index].renderBounds)
        }
        for object in history.objects where selectedObjects.contains(object.id) { bounds = bounds.union(object.frame) }
        return bounds.isNull ? nil : bounds
    }

    /// Used by the gesture and deterministic transaction tests. Stroke transforms
    /// preserve masks, seeds and all other stroke metadata by copying the value.
    func moved(_ state: SpikeSnapshot, delta: CGPoint) -> SpikeSnapshot {
        var next = state
        var strokes = state.drawing.strokes
        for index in selectedStrokes where strokes.indices.contains(index) {
            strokes[index].transform = strokes[index].transform.concatenating(CGAffineTransform(translationX: delta.x, y: delta.y))
        }
        next.drawing = PKDrawing(strokes: strokes)
        for index in next.objects.indices where selectedObjects.contains(next.objects[index].id) {
            next.objects[index].frame = next.objects[index].frame.offsetBy(dx: delta.x, dy: delta.y)
        }
        return next
    }

    @objc func handleLasso(_ gesture: UIPanGestureRecognizer) {
        guard !halted else { return }
        let point = SpikeGeometry.document(gesture.location(in: viewport), zoom: canvas.zoomScale, offset: canvas.contentOffset)
        switch gesture.state {
        case .began:
            if let bounds = selectionBounds, bounds.insetBy(dx: -12 / canvas.zoomScale, dy: -12 / canvas.zoomScale).contains(point) {
                dragStart = point
                dragBounds = bounds
                dragSnapshot = history.snapshot
                lastDragDelta = .zero
            } else {
                clearSelection()
                lassoPoints = [point]
            }
        case .changed:
            if let start = dragStart, let state = dragSnapshot, let bounds = dragBounds {
                lastDragDelta = SpikeGeometry.clampedTranslation(CGPoint(x: point.x - start.x, y: point.y - start.y), bounds: bounds)
                history.apply(moved(state, delta: lastDragDelta))
            } else {
                lassoPoints.append(point)
            }
            redrawSelection()
        case .ended:
            if let state = dragSnapshot {
                let final = history.snapshot
                history.apply(state)
                if lastDragDelta != .zero { history.commit(final, named: "Move mixed selection") }
                dragSnapshot = nil
                dragStart = nil
                dragBounds = nil
            } else {
                lassoPoints.append(point)
                select(polygon: lassoPoints)
            }
            lassoPoints = []
            redrawSelection()
        case .cancelled, .failed:
            if let state = dragSnapshot { history.apply(state) }
            dragSnapshot = nil
            dragStart = nil
            dragBounds = nil
            lassoPoints = []
            redrawSelection()
        default: break
        }
    }

    private func clearSelection() {
        selectedStrokes = []
        selectedObjects = []
        lassoPoints = []
        redrawSelection()
    }

    private func refreshSelectionAndStatus() {
        if dragSnapshot == nil { clearSelection() }
        refreshStatus()
    }

    private func redrawSelection() {
        let points: [CGPoint]
        if lassoPoints.count > 1 { points = lassoPoints }
        else if let bounds = selectionBounds {
            points = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                      CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY)]
        } else { selectionShape.path = nil; return }
        selectionShape.path = SpikeGeometry.polygon(points.map {
            SpikeGeometry.viewport($0, zoom: canvas.zoomScale, offset: canvas.contentOffset)
        }).cgPath
    }

    private func refreshStatus() {
        guard !halted else { return }
        status.text = "\(canvas.drawing.strokes.count) strokes • \(history.objects.count) objects • \(String(format: "%.2f", canvas.zoomScale))× • selected \(selectedStrokes.count) ink / \(selectedObjects.count) objects\n" +
            (lassoMode ? "Trace a loop; drag inside selection. Two fingers pan/zoom." : "Pencil draws. Fingers pan/zoom. Double-tap edits sample text. Nothing is saved.")
        undoButton?.isEnabled = history.manager.canUndo && !toolGroupOpen
        redoButton?.isEnabled = history.manager.canRedo && !toolGroupOpen
    }
}
#endif
