import PencilKit
import UIKit

/// The PKCanvasView subclass hands PencilKit the session's undo manager, so native
/// strokes and object edits share one stack (approach from the 004 spike).
@MainActor
final class EditorCanvasView: PKCanvasView {
    var documentUndoManager: UndoManager?
    override var undoManager: UndoManager? { documentUndoManager ?? super.undoManager }
}

/// Canvas and notebook editor (ticket 008). Layers, bottom to top: page backgrounds,
/// objects, ink (ink above objects, the 004 recommendation), selection overlay.
/// Reports its own layout. The viewport sits in a stack view, which sizes it after the
/// controller's `viewDidLayoutSubviews` and again when the banner shows or hides.
final class EditorViewportView: UIView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// The canvas view is the only scrolling surface; the other layers follow its
/// zoom and offset: viewport = document × zoom − contentOffset.
@MainActor
final class DocumentEditorController: UIViewController, PKCanvasViewDelegate, UIGestureRecognizerDelegate, PKToolPickerObserver {
    let session: EditorSession
    private let assetsURL: URL?
    let canvas = EditorCanvasView()
    private let viewport = EditorViewportView()
    private let backgroundView = PageBackgroundView()
    private let objectContainer = UIView()
    private let selectionOverlay = UIView()
    private let selectionShape = CAShapeLayer()
    private let draftOutlines = CAShapeLayer()
    private let handleShape = CAShapeLayer()
    /// State the SwiftUI bar and selection bar read (ticket 024). Set before the view loads.
    var chrome: EditorChromeState?
    private var lastPersistentNotice: String?
    private let thinking = UIActivityIndicatorView(style: .medium)
    private var thinkingRegion: CGRect?
    func setThinkingRegion(_ region: CGRect?) {
        thinkingRegion = region
        if region == nil { thinking.stopAnimating() } else { thinking.startAnimating() }
        synchronizeLayers()
    }
    private(set) var handMode = false
    func setHandMode(_ enabled: Bool) {
        guard !toolInUse else { return }
        handMode = enabled
        canvas.panGestureRecognizer.minimumNumberOfTouches = enabled ? 1 : (selectMode ? 2 : 1)
        canvas.isDrawingEnabled = !enabled && !selectMode
        lassoPan.isEnabled = selectMode && !enabled
        selectTap.isEnabled = selectMode && !enabled
        canvas.panGestureRecognizer.allowedTouchTypes = enabled ? [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)] : [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    }
    func exportCurrentPage() -> Data {
        let index = currentPageIndex
        let page = session.pages[index], frame = session.layout.pageRect(index)
        // Bounded export even when a canvas has grown to 20,000 points.
        let scale = min(1, 4096 / max(frame.width, frame.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: frame.width * scale, height: frame.height * scale), format: format).pngData { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            let paper = PageBackgroundView(frame: CGRect(origin: .zero, size: frame.size))
            paper.layout = EditorLayout(type: .canvas, pages: [page]); paper.patternVisible = session.manifest.gridVisible ?? true
            paper.setNeedsDisplay()
            paper.layer.displayIfNeeded()
            paper.layer.render(in: context.cgContext)
            for object in session.objects.filter({ $0.pageId == page.id }).sorted(by: { $0.zIndex < $1.zIndex }) {
                let rect = AskAIController.rect(object.frame)
                if object.type == .image, let name = object.assetRefs.first, let assetsURL {
                    UIImage(contentsOfFile: assetsURL.appendingPathComponent(name).path)?.draw(in: rect)
                } else {
                    RichTextRenderer.draw(source: object.source, type: object.type, in: rect, handwritten: object.rendersHandwritten, appearance: object.aiAppearance)
                }
            }
            session.drawing.image(from: frame, scale: scale).draw(in: CGRect(origin: .zero, size: frame.size))
        }
    }
    /// Every PencilKit tool (ticket 015). The eraser's own options switch between
    /// object and pixel erasing; the autosave name keeps the last tool across documents.
    private lazy var toolPicker: PKToolPicker = {
        let picker = PKToolPicker(toolItems: [
            PKToolPickerInkingItem(type: .pen), PKToolPickerInkingItem(type: .monoline),
            PKToolPickerInkingItem(type: .fountainPen), PKToolPickerInkingItem(type: .marker),
            PKToolPickerInkingItem(type: .pencil), PKToolPickerInkingItem(type: .crayon),
            PKToolPickerInkingItem(type: .watercolor),
            PKToolPickerEraserItem(type: .vector), PKToolPickerLassoItem(), PKToolPickerRulerItem()
        ])
        picker.stateAutosaveName = "editor.toolPicker"
        return picker
    }()
    /// Tool gesture start and end for Auto Ask (ticket 014). `inked` is true for inking tools.
    var onPickerPosition: ((Bool, CGFloat) -> Void)?
    func toolPickerSelectedToolDidChange(_ toolPicker: PKToolPicker) { if handMode { canvas.isDrawingEnabled = false } }
    func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) { reportPickerPosition() }
    private func reportPickerPosition() {
        guard let window = view.window else { return }
        let frame = toolPicker.frameObscured(in: window)
        guard !frame.isNull, !frame.isEmpty else { return }
        let top = frame.midY < window.bounds.midY
        let clearance = top ? frame.maxY - window.safeAreaInsets.top : window.bounds.maxY - frame.minY - window.safeAreaInsets.bottom
        onPickerPosition?(top, max(0, clearance))
    }
    var onSelectionChanged: ((CGRect?) -> Void)?
    var onToolBegan: (() -> Void)?
    var onToolEnded: ((_ inked: Bool) -> Void)?
    private var objectViews: [UUID: UIView] = [:]
    private(set) var selectMode = false
    private var toolInUse = false
    private var inkChangedDuringTool = false
    private var applying = false
    private(set) var selectedStrokes = Set<Int>()
    private(set) var selectedObjects = Set<UUID>()
    private var lassoPoints: [CGPoint] = []
    private enum Drag { case move(start: CGPoint), resize(id: UUID, start: CGPoint, size: CGSize) }
    private var drag: Drag?
    private var dragSnapshot: EditorSnapshot?
    private var lastViewportSize = CGSize.zero
    private lazy var lassoPan = UIPanGestureRecognizer(target: self, action: #selector(handleSelectPan(_:)))
    private lazy var selectTap = UITapGestureRecognizer(target: self, action: #selector(handleSelectTap(_:)))

    static let handleSize: CGFloat = 22

    init(session: EditorSession, assetsURL: URL?) {
        self.session = session
        self.assetsURL = assetsURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var undoManager: UndoManager? { session.manager }
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let undo = UIKeyCommand(title: "Undo", action: #selector(undoAction), input: "z", modifierFlags: .command)
        let redo = UIKeyCommand(title: "Redo", action: #selector(redoAction), input: "z", modifierFlags: [.command, .shift])
        undo.wantsPriorityOverSystemBehavior = true
        redo.wantsPriorityOverSystemBehavior = true
        guard hasSelection else { return [undo, redo] }
        let delete = UIKeyCommand(title: "Delete Selection", action: #selector(deleteSelectionCommand), input: UIKeyCommand.inputDelete)
        return [undo, redo, delete]
    }

    // MARK: - Setup

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        viewport.clipsToBounds = true
        viewport.onLayout = { [weak self] in self?.layoutViewport() }
        // Paper is always white, so ink keeps its light-mode colours.
        viewport.overrideUserInterfaceStyle = .light
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
#if DEBUG
        // The simulator has no Apple Pencil; this lets a finger draw there for diagnosis.
        if ProcessInfo.processInfo.arguments.contains("-anyInputDrawing") { canvas.drawingPolicy = .anyInput }
#endif
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 4
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.documentUndoManager = session.manager
        canvas.delegate = self
        canvas.isUserInteractionEnabled = !session.isReadOnly
        canvas.accessibilityIdentifier = "editor-canvas"
        canvas.accessibilityLabel = session.type == .canvas ? "Canvas" : "Notebook pages"
        canvas.accessibilityHint = "Apple Pencil draws. Fingers pan and zoom."
        objectContainer.isUserInteractionEnabled = false
        objectContainer.layer.anchorPoint = .zero
        selectionOverlay.isUserInteractionEnabled = false
        selectionShape.strokeColor = UIColor.systemBlue.cgColor
        selectionShape.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
        selectionShape.lineWidth = 2
        selectionShape.lineDashPattern = [6, 4]
        handleShape.fillColor = UIColor.systemBlue.cgColor
        handleShape.strokeColor = UIColor.white.cgColor
        handleShape.lineWidth = 2
        selectionOverlay.layer.addSublayer(selectionShape)
        selectionOverlay.layer.addSublayer(handleShape)
        for layer in [backgroundView, objectContainer, canvas, selectionOverlay, thinking] { viewport.addSubview(layer) }

        lassoPan.maximumNumberOfTouches = 1
        lassoPan.delegate = self
        lassoPan.isEnabled = false
        viewport.addGestureRecognizer(lassoPan)
        selectTap.isEnabled = false
        viewport.addGestureRecognizer(selectTap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        viewport.addGestureRecognizer(doubleTap)
        selectTap.require(toFail: doubleTap)

        // One command bar lives in SwiftUI (ticket 024); the viewport fills the safe area.
        viewport.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(viewport)
        NSLayoutConstraint.activate([
            viewport.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            viewport.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            viewport.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            viewport.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        session.onApply = { [weak self] in self?.sessionDidApply() }
        session.onSaveStateChange = { [weak self] _ in self?.refreshStatus() }
        applying = true
        canvas.drawing = session.drawing
        applying = false
        applyLayout()
        renderObjects()
        refreshStatus()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !session.isReadOnly else { return }
        toolPicker.addObserver(canvas)
        toolPicker.addObserver(self)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        canvas.becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutViewport()
        reportPickerPosition()
    }

    /// Sizes the layers to the viewport. Runs on every viewport layout, not only the
    /// controller's: until the stack view lays the viewport out, its bounds are zero.
    private func layoutViewport() {
        canvas.frame = viewport.bounds
        backgroundView.frame = viewport.bounds
        selectionOverlay.frame = viewport.bounds
        let size = viewport.bounds.size
        if size.width > 0, size != lastViewportSize {
            // First layout and rotation: notebooks fit page width, keeping the same
            // document point at the top; a canvas keeps its zoom.
            let topDocumentY = lastViewportSize == .zero ? 0 : (canvas.contentOffset.y + canvas.contentInset.top) / canvas.zoomScale
            lastViewportSize = size
            if session.type == .notebook {
                let zoom = min(canvas.maximumZoomScale, max(canvas.minimumZoomScale, size.width / session.layout.contentSize.width))
                canvas.setZoomScale(zoom, animated: false)
                updateInsets()
                let maxY = max(-canvas.contentInset.top, canvas.contentSize.height - size.height)
                canvas.setContentOffset(CGPoint(x: -canvas.contentInset.left,
                                                y: min(maxY, topDocumentY * zoom - canvas.contentInset.top)), animated: false)
            } else {
                updateInsets()
            }
        }
        synchronizeLayers()
    }

    /// The page in view's background style; the View menu shows it checked.
    var currentPageStyle: BackgroundStyle { session.pages[currentPageIndex].background.style }

    func setPageStyle(_ style: BackgroundStyle) {
        guard !toolInUse, !session.isReadOnly else { return }
        session.setBackground(style, page: currentPageIndex)
        refreshStatus()
    }

    // MARK: - Layout and synchronisation

    private func applyLayout() {
        let content = session.layout.contentSize
        objectContainer.bounds = CGRect(origin: .zero, size: content)
        let scaled = CGSize(width: content.width * canvas.zoomScale, height: content.height * canvas.zoomScale)
        if canvas.contentSize != scaled { canvas.contentSize = scaled }
        backgroundView.layout = session.layout
        backgroundView.patternVisible = session.manifest.gridVisible ?? true
        updateInsets()
    }

    /// Centres content smaller than the viewport. The mapping still holds because
    /// contentOffset goes negative by the inset.
    private func updateInsets() {
        let size = viewport.bounds.size
        let content = canvas.contentSize
        let inset = UIEdgeInsets(top: max(0, (size.height - content.height) / 2), left: max(0, (size.width - content.width) / 2),
                                 bottom: 0, right: 0)
        if canvas.contentInset != inset { canvas.contentInset = inset }
    }

    private func synchronizeLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        objectContainer.transform = CGAffineTransform(scaleX: canvas.zoomScale, y: canvas.zoomScale)
        objectContainer.layer.position = CGPoint(x: -canvas.contentOffset.x, y: -canvas.contentOffset.y)
        CATransaction.commit()
        if let region = thinkingRegion {
            let point = EditorGeometry.viewport(CGPoint(x: region.maxX, y: region.minY), zoom: canvas.zoomScale, offset: canvas.contentOffset)
            thinking.frame = CGRect(x: min(max(8, point.x), max(8, viewport.bounds.width - 40)), y: min(max(8, point.y), max(8, viewport.bounds.height - 40)), width: 32, height: 32)
        }
        backgroundView.zoom = canvas.zoomScale
        backgroundView.offset = canvas.contentOffset
        redrawSelection()
        refreshPageLabel()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { synchronizeLayers() }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateInsets()
        synchronizeLayers()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Re-rasterise object text at the new scale so it stays sharp when magnified.
        canvas.accessibilityValue = "\(Int((scale * 100).rounded()))% zoom"
        renderObjects()
    }

    private func documentPoint(_ location: CGPoint) -> CGPoint {
        EditorGeometry.document(location, zoom: canvas.zoomScale, offset: canvas.contentOffset)
    }

    private var currentPageIndex: Int {
        let center = documentPoint(CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY))
        return session.layout.pageIndex(nearestY: center.y)
    }

    private var viewportCenter: CGPoint { documentPoint(CGPoint(x: viewport.bounds.midX, y: viewport.bounds.midY)) }

    /// The mixed selection plus a 24 pt margin, in document space; nil without one.
    var askAISelection: CGRect? { selectionBounds?.insetBy(dx: -24, dy: -24) }

    /// Ask AI fallback region in document space (ticket 010): the selection, otherwise
    /// the visible area. Ticket 014 tries the newest ink before the visible area.
    var askAIRegion: CGRect {
        if let bounds = askAISelection { return bounds }
        return visiblePageRegion
    }

    var visiblePageRegion: CGRect {
        let topLeft = documentPoint(CGPoint(x: viewport.bounds.minX, y: viewport.bounds.minY))
        let bottomRight = documentPoint(CGPoint(x: viewport.bounds.maxX, y: viewport.bounds.maxY))
        return CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    // MARK: - PencilKit

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        clearSelection()
        toolInUse = true
        onToolBegan?()
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        toolInUse = false
        // One revision step per gesture, even when an eraser changes the drawing many times.
        // The drawing change can arrive after this call, so only the tool type is known here;
        // Ask AI checks for new ink itself when the pause ends.
        let inked = canvas.tool is PKInkingTool
        if inkChangedDuringTool {
            inkChangedDuringTool = false
            session.inkDidChange(canvas.drawing)
        }
        refreshStatus()
        onToolEnded?(inked)
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !applying else { return }
        if toolInUse {
            inkChangedDuringTool = true
        } else {
            session.inkDidChange(canvas.drawing)
        }
        // Stroke-index selections are valid only until the next drawing change.
        if dragSnapshot == nil { clearSelection() }
        refreshStatus()
    }

    private func sessionDidApply() {
        if canvas.drawing != session.drawing {
            applying = true
            canvas.drawing = session.drawing
            applying = false
        }
        applyLayout()
        renderObjects()
        synchronizeLayers()
        refreshStatus()
    }

    // MARK: - Commands

    @objc func undoAction() {
        guard !toolInUse, session.manager.canUndo else { return }
        session.manager.undo()
        clearSelection()
        refreshStatus()
    }

    @objc func redoAction() {
        guard !toolInUse, session.manager.canRedo else { return }
        session.manager.redo()
        clearSelection()
        refreshStatus()
    }

    func toggleSelectMode() {
        guard !toolInUse else { return }
        selectMode.toggle()
        lassoPan.isEnabled = selectMode
        selectTap.isEnabled = selectMode
        canvas.drawingGestureRecognizer.isEnabled = !selectMode && !handMode
        canvas.panGestureRecognizer.minimumNumberOfTouches = selectMode ? 2 : 1
        clearSelection()
        refreshStatus()
    }

    func addText(type: ObjectType = .text) {
        guard !toolInUse, let id = session.addTextObject(at: viewportCenter, source: type == .markdown ? "# Answer\n\nWrite **Markdown** with $x^2$." : type == .latex ? #"\frac{a}{b}"# : type == .plot ? "y = x^2\nx: -5 .. 5" : "Text", type: type) else {
            if session.objects.count >= DocumentLimits.maxObjects { showBanner("This document has the maximum number of objects.") }
            return
        }
        if !selectMode { toggleSelectMode() }
        selectedObjects = [id]
        redrawSelection()
        refreshStatus()
        editText(of: id)
    }

    func editSelectedText() {
        let candidates = session.objects.filter { selectedObjects.contains($0.id) && $0.type != .image }
        guard let object = candidates.first else {
            showBanner("Select a text object first: turn on Select, then tap it.")
            return
        }
        editText(of: object.id)
    }

    private func editText(of id: UUID) {
        guard !session.isReadOnly, let object = session.objects.first(where: { $0.id == id }) else { return }
        let editor = ObjectSourceEditor(object: object) { [weak self] source in
            self?.session.updateSource(of: id, to: source)
        }
        let navigation = UINavigationController(rootViewController: editor)
        navigation.modalPresentationStyle = .formSheet
        navigation.isModalInPresentation = true
        present(navigation, animated: true)
    }

    @objc private func deleteSelectionCommand() { deleteSelection() }

    var hasSelection: Bool { !selectedStrokes.isEmpty || !selectedObjects.isEmpty }

    func deleteSelection() {
        guard !toolInUse, !selectedStrokes.isEmpty || !selectedObjects.isEmpty else { return }
        session.deleteSelection(strokes: selectedStrokes, objectIds: selectedObjects)
        clearSelection()
    }

    func addPage() {
        guard !toolInUse, let index = session.addPage(after: currentPageIndex) else {
            if session.pages.count >= DocumentLimits.maxNotebookPages { showBanner("A notebook can have up to \(DocumentLimits.maxNotebookPages) pages.") }
            return
        }
        scrollToPage(index)
    }

    func confirmDeletePage() {
        guard !toolInUse, session.pages.count > 1 else { return showBanner("A notebook keeps at least one page.") }
        let index = currentPageIndex
        let alert = UIAlertController(title: "Delete page \(index + 1)?",
                                      message: "Its ink and objects are removed. You can undo this.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete Page", style: .destructive) { [weak self] _ in
            self?.clearSelection()
            self?.session.deletePage(at: index)
        })
        present(alert, animated: true)
    }

    private func scrollToPage(_ index: Int) {
        let rect = session.layout.pageRect(index)
        let maxY = max(-canvas.contentInset.top, canvas.contentSize.height - canvas.bounds.height)
        canvas.setContentOffset(CGPoint(x: canvas.contentOffset.x,
                                        y: min(maxY, (rect.minY - EditorLayout.pageGap / 2) * canvas.zoomScale)), animated: true)
    }

    /// Short notices appear as a glass card in the SwiftUI shell (ticket 024).
    private func showBanner(_ text: String?) {
        chrome?.notice = text
        if let text { UIAccessibility.post(notification: .announcement, argument: text) }
    }

    // MARK: - Objects

    private func renderObjects() {
        let layout = session.layout
        let ids = Set(session.objects.map(\.id))
        for (id, item) in objectViews where !ids.contains(id) {
            item.removeFromSuperview()
            objectViews.removeValue(forKey: id)
        }
        let ordered = session.objects.enumerated().sorted { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }
        for (_, object) in ordered {
            let item = objectViews[object.id] ?? makeObjectView(object)
            objectViews[object.id] = item
            objectContainer.addSubview(item)  // Re-adding keeps zIndex order.
            item.frame = layout.documentFrame(of: object)
            if let rich = item as? RichObjectView {
                rich.configure(source: object.source, type: object.type,
                               density: (view.window?.screen.scale ?? 2) * max(1, canvas.zoomScale),
                               handwritten: object.rendersHandwritten, appearance: object.aiAppearance)
                // Handwritten answers read as ink on the page, so they have no box.
                rich.layer.borderWidth = object.rendersHandwritten ? 0 : 0.5
            } else { item.accessibilityLabel = accessibilityLabel(for: object) }
        }
        let path = UIBezierPath()
        for object in session.objects where object.isDraft == true { path.append(UIBezierPath(rect: layout.documentFrame(of: object).insetBy(dx: -3, dy: -3))) }
        for batch in session.draftInk {
            let strokes = session.drawing.strokes.filter { $0.path.creationDate == batch.strokeDate }
            let bounds = strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
            if !bounds.isNull { path.append(UIBezierPath(rect: bounds.insetBy(dx: -4, dy: -4))) }
        }
        draftOutlines.path = path.cgPath
        draftOutlines.strokeColor = UIColor.systemOrange.cgColor
        draftOutlines.fillColor = nil
        draftOutlines.lineWidth = 2 / max(0.25, canvas.zoomScale)
        draftOutlines.lineDashPattern = [6, 4]
        objectContainer.layer.addSublayer(draftOutlines)
    }

    private func makeObjectView(_ object: DocumentObject) -> UIView {
        let item: UIView
        if object.type == .image {
            let image = UIImageView()
            image.contentMode = .scaleAspectFit
            if let name = object.assetRefs.first, let assetsURL,
               let loaded = UIImage(contentsOfFile: assetsURL.appendingPathComponent(name).path) {
                image.image = loaded
            } else {
                image.image = UIImage(systemName: "photo")
                image.tintColor = .systemGray
            }
            item = image
        } else {
            item = RichObjectView()
        }
        item.isAccessibilityElement = true
        item.layer.borderWidth = 0.5
        item.layer.borderColor = UIColor(white: 0.75, alpha: 1).cgColor
        return item
    }

    private func accessibilityLabel(for object: DocumentObject) -> String {
        let kind: String = switch object.type {
        case .text: "Text"
        case .markdown: "Markdown"
        case .latex: "Formula"
        case .image: "Image"
        case .plot: "Graph"
        }
        let source = String(object.source.prefix(200))
        return source.isEmpty ? kind : "\(kind): \(source)"
    }

    // MARK: - Selection

    private func topObject(at point: CGPoint) -> DocumentObject? {
        let layout = session.layout
        return session.objects.enumerated()
            .filter { layout.documentFrame(of: $0.element).contains(point) }
            .max { ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset) }?.element
    }

    func select(polygon: [CGPoint]) {
        let layout = session.layout
        selectedStrokes = Set(session.drawing.strokes.indices.filter { EditorGeometry.intersects(session.drawing.strokes[$0], polygon: polygon) })
        selectedObjects = Set(session.objects.filter { EditorGeometry.intersects(layout.documentFrame(of: $0), polygon: polygon) }.map(\.id))
        redrawSelection()
        refreshStatus()
    }

    private var selectionBounds: CGRect? {
        var bounds = CGRect.null
        for index in selectedStrokes where session.drawing.strokes.indices.contains(index) {
            bounds = bounds.union(session.drawing.strokes[index].renderBounds)
        }
        let layout = session.layout
        for object in session.objects where selectedObjects.contains(object.id) { bounds = bounds.union(layout.documentFrame(of: object)) }
        return bounds.isNull ? nil : bounds
    }

    /// The one selected object that can be resized, when the selection is just that object.
    private var resizableObject: DocumentObject? {
        guard selectedStrokes.isEmpty, selectedObjects.count == 1 else { return nil }
        return session.objects.first { selectedObjects.contains($0.id) }
    }

    @objc private func handleSelectTap(_ gesture: UITapGestureRecognizer) {
        let point = documentPoint(gesture.location(in: viewport))
        selectedStrokes = []
        selectedObjects = topObject(at: point).map { [$0.id] } ?? []
        redrawSelection()
        refreshStatus()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard !toolInUse, let object = topObject(at: documentPoint(gesture.location(in: viewport))), object.type != .image else { return }
        editText(of: object.id)
    }

    @objc func handleSelectPan(_ gesture: UIPanGestureRecognizer) {
        guard !session.isReadOnly else { return }
        let point = documentPoint(gesture.location(in: viewport))
        switch gesture.state {
        case .began:
            let slop = Self.handleSize / canvas.zoomScale
            if let object = resizableObject {
                let frame = session.layout.documentFrame(of: object)
                if hypot(point.x - frame.maxX, point.y - frame.maxY) <= slop {
                    drag = .resize(id: object.id, start: point, size: frame.size)
                    dragSnapshot = session.snapshot
                    return
                }
            }
            if let bounds = selectionBounds, bounds.insetBy(dx: -12 / canvas.zoomScale, dy: -12 / canvas.zoomScale).contains(point) {
                drag = .move(start: point)
                dragSnapshot = session.snapshot
            } else {
                clearSelection()
                lassoPoints = [point]
            }
        case .changed:
            if let state = dragSnapshot, let drag {
                switch drag {
                case .move(let start):
                    let delta = session.clampedDelta(CGPoint(x: point.x - start.x, y: point.y - start.y),
                                                     strokes: selectedStrokes, objectIds: selectedObjects, in: state)
                    session.preview(session.moved(state, strokes: selectedStrokes, objectIds: selectedObjects, delta: delta))
                case .resize(let id, let start, let size):
                    session.preview(session.resized(state, objectId: id, to: CGSize(width: size.width + point.x - start.x,
                                                                                   height: size.height + point.y - start.y)))
                }
            } else {
                lassoPoints.append(point)
            }
            redrawSelection()
        case .ended:
            if let state = dragSnapshot, let drag {
                // Restore the pre-drag state, then commit the final one as a single undo step.
                let final = session.snapshot
                session.preview(state)
                if case .resize = drag { session.commit(final, named: "Resize") } else { session.commit(final, named: "Move") }
                self.drag = nil
                dragSnapshot = nil
            } else {
                lassoPoints.append(point)
                select(polygon: lassoPoints)
            }
            lassoPoints = []
            redrawSelection()
        case .cancelled, .failed:
            if let state = dragSnapshot { session.preview(state) }
            drag = nil
            dragSnapshot = nil
            lassoPoints = []
            redrawSelection()
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { !toolInUse }

    private func clearSelection() {
        selectedStrokes = []
        selectedObjects = []
        lassoPoints = []
        redrawSelection()
    }

    private func redrawSelection() {
        onSelectionChanged?(askAISelection)
        publishSelection()
        let zoom = canvas.zoomScale, offset = canvas.contentOffset
        handleShape.path = nil
        let points: [CGPoint]
        if lassoPoints.count > 1 {
            points = lassoPoints
        } else if let bounds = selectionBounds {
            points = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
                      CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY)]
            if resizableObject != nil {
                let corner = EditorGeometry.viewport(CGPoint(x: bounds.maxX, y: bounds.maxY), zoom: zoom, offset: offset)
                let half = Self.handleSize / 2 - 4
                handleShape.path = UIBezierPath(ovalIn: CGRect(x: corner.x - half, y: corner.y - half, width: half * 2, height: half * 2)).cgPath
            }
        } else {
            selectionShape.path = nil
            return
        }
        selectionShape.path = EditorGeometry.polygon(points.map { EditorGeometry.viewport($0, zoom: zoom, offset: offset) }).cgPath
    }

    // MARK: - Status

    /// The selection's bounds in this controller's view, for the floating selection bar.
    private func publishSelection() {
        guard let chrome else { return }
        let dragging = drag != nil || lassoPoints.count > 1
        var rect: CGRect?
        if !dragging, let bounds = selectionBounds {
            let topLeft = EditorGeometry.viewport(CGPoint(x: bounds.minX, y: bounds.minY), zoom: canvas.zoomScale, offset: canvas.contentOffset)
            let bottomRight = EditorGeometry.viewport(CGPoint(x: bounds.maxX, y: bounds.maxY), zoom: canvas.zoomScale, offset: canvas.contentOffset)
            rect = viewport.convert(CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y), to: view)
        }
        if chrome.selectionRect != rect { chrome.selectionRect = rect }
        if chrome.viewportFrame != viewport.frame { chrome.viewportFrame = viewport.frame }
    }

    private func refreshPageLabel() {
        guard let chrome else { return }
        let index = currentPageIndex
        if chrome.pageIndex != index { chrome.pageIndex = index }
        if chrome.pageCount != session.pages.count { chrome.pageCount = session.pages.count }
        let style = session.pages[index].background.style
        if chrome.pageStyle != style { chrome.pageStyle = style }
    }

    private func refreshStatus() {
        let editable = !session.isReadOnly && !toolInUse
        if let chrome {
            chrome.selectMode = selectMode
            chrome.hasSelection = hasSelection
            chrome.canEditSelection = editable && session.objects.contains { selectedObjects.contains($0.id) && $0.type != .image }
            chrome.isEditable = editable
        }
        refreshPageLabel()
        let notice: String?
        switch session.saveState {
        case .failed(let reason): notice = reason
        case .readOnly(let reason): notice = reason
        default: notice = nil
        }
        // Show a lasting problem once, not on every refresh.
        if notice != lastPersistentNotice {
            lastPersistentNotice = notice
            if let notice { showBanner(notice) }
        }
    }
}
