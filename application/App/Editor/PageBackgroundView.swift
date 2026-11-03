import UIKit

/// Paper and page backgrounds, drawn below objects and ink and never part of the ink.
/// The view covers the viewport and draws only the visible document region, so a
/// 20,000-point canvas at 4× costs no more than a small one.
@MainActor
final class PageBackgroundView: UIView {
    var layout: EditorLayout? { didSet { setNeedsDisplay() } }
    var zoom: CGFloat = 1 { didSet { setNeedsDisplay() } }
    var offset: CGPoint = .zero { didSet { setNeedsDisplay() } }

    /// Patterns closer than this on screen are skipped; they would read as grey.
    static let minimumScreenSpacing: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isOpaque = true
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let layout, let context = UIGraphicsGetCurrentContext() else { return }
        let desk = layout.type == .notebook ? UIColor(white: 0.9, alpha: 1) : UIColor.white
        desk.setFill()
        context.fill(rect)
        let visible = CGRect(origin: EditorGeometry.document(rect.origin, zoom: zoom, offset: offset),
                             size: CGSize(width: rect.width / zoom, height: rect.height / zoom))
        for index in layout.pages.indices {
            let page = layout.pageRect(index)
            guard page.intersects(visible) else { continue }
            let onScreen = screenRect(page)
            if layout.type == .notebook {
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: UIColor(white: 0, alpha: 0.18).cgColor)
                UIColor.white.setFill()
                context.fill(onScreen)
                context.restoreGState()
            }
            drawPattern(layout.pages[index].background, page: page, visible: visible.intersection(page), in: context)
        }
    }

    private func screenRect(_ rect: CGRect) -> CGRect {
        let origin = EditorGeometry.viewport(rect.origin, zoom: zoom, offset: offset)
        return CGRect(origin: origin, size: CGSize(width: rect.width * zoom, height: rect.height * zoom))
    }

    private func drawPattern(_ background: PageBackground, page: CGRect, visible: CGRect, in context: CGContext) {
        guard background.style != .blank, !visible.isNull else { return }
        let spacing = CGFloat(background.spacing ?? PageBackground.defaultSpacing)
        guard spacing * zoom >= Self.minimumScreenSpacing else { return }
        // Lines and dots sit at page origin + k × spacing; only visible ones are drawn.
        let firstColumn = Int(((visible.minX - page.minX) / spacing).rounded(.up))
        let lastColumn = Int(((visible.maxX - page.minX) / spacing).rounded(.down))
        let firstRow = Int(((visible.minY - page.minY) / spacing).rounded(.up))
        let lastRow = Int(((visible.maxY - page.minY) / spacing).rounded(.down))
        let xs = firstColumn <= lastColumn ? (firstColumn...lastColumn).map { page.minX + CGFloat($0) * spacing } : []
        let ys = firstRow <= lastRow ? (firstRow...lastRow).map { page.minY + CGFloat($0) * spacing } : []
        let clip = screenRect(page)
        context.saveGState()
        context.clip(to: clip)
        let color = UIColor(red: 0.62, green: 0.72, blue: 0.85, alpha: background.style == .dotted ? 0.9 : 0.55)
        switch background.style {
        case .dotted:
            color.setFill()
            let radius = max(0.8, min(1.6, zoom))
            for x in xs { for y in ys {
                let point = EditorGeometry.viewport(CGPoint(x: x, y: y), zoom: zoom, offset: offset)
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            } }
        case .lined, .grid:
            color.setStroke()
            context.setLineWidth(max(0.5, min(1, zoom)))
            for y in ys where y > page.minY {
                let screenY = EditorGeometry.viewport(CGPoint(x: 0, y: y), zoom: zoom, offset: offset).y
                context.move(to: CGPoint(x: clip.minX, y: screenY))
                context.addLine(to: CGPoint(x: clip.maxX, y: screenY))
            }
            if background.style == .grid {
                for x in xs where x > page.minX {
                    let screenX = EditorGeometry.viewport(CGPoint(x: x, y: 0), zoom: zoom, offset: offset).x
                    context.move(to: CGPoint(x: screenX, y: clip.minY))
                    context.addLine(to: CGPoint(x: screenX, y: clip.maxY))
                }
            }
            context.strokePath()
        case .blank:
            break
        }
        context.restoreGState()
    }
}
