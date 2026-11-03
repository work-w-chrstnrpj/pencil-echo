import PencilKit

// Editor document space for ticket 008. One PKCanvasView shows every page: the
// canvas has one page at the origin, notebook pages stack vertically with a gap.
// Ink files stay page-relative (docs/database/document-schema-v1.md, ink), so
// strokes are translated on load and split back per page on save.
struct EditorLayout: Equatable {
    static let pageGap: CGFloat = 32

    let type: DocumentType
    let pages: [Page]

    var contentSize: CGSize {
        guard type == .notebook else {
            let size = pages.first?.size ?? DocumentSchema.newCanvasSize
            return CGSize(width: size.width, height: size.height)
        }
        let page = DocumentSchema.a4
        return CGSize(width: page.width + Self.pageGap * 2,
                      height: Self.pageGap + CGFloat(pages.count) * (page.height + Self.pageGap))
    }

    func pageRect(_ index: Int) -> CGRect {
        let size = pages[index].size
        guard type == .notebook else { return CGRect(x: 0, y: 0, width: size.width, height: size.height) }
        return CGRect(x: Self.pageGap, y: Self.pageGap + CGFloat(index) * (size.height + Self.pageGap),
                      width: size.width, height: size.height)
    }

    func pageIndex(of pageId: UUID) -> Int? { pages.firstIndex { $0.id == pageId } }

    /// The page whose vertical band (including half the gap on each side) holds `y`.
    func pageIndex(nearestY y: CGFloat) -> Int {
        guard type == .notebook, pages.count > 1 else { return 0 }
        let pitch = DocumentSchema.a4.height + Self.pageGap
        return min(pages.count - 1, max(0, Int(((y - Self.pageGap / 2) / pitch).rounded(.down))))
    }

    /// An object's frame in document space.
    func documentFrame(of object: DocumentObject) -> CGRect {
        let origin = pageIndex(of: object.pageId).map { pageRect($0).origin } ?? .zero
        return CGRect(x: origin.x + object.frame.x, y: origin.y + object.frame.y,
                      width: object.frame.width, height: object.frame.height)
    }

    /// Page-relative drawings → one drawing in document space.
    func compose(_ ink: [UUID: PKDrawing]) -> PKDrawing {
        var strokes: [PKStroke] = []
        for index in pages.indices {
            guard let drawing = ink[pages[index].id] else { continue }
            let origin = pageRect(index).origin
            let shift = CGAffineTransform(translationX: origin.x, y: origin.y)
            strokes += drawing.strokes.map { stroke in
                var moved = stroke
                moved.transform = stroke.transform.concatenating(shift)
                return moved
            }
        }
        return PKDrawing(strokes: strokes)
    }

    /// Index of the page each stroke belongs to, by the vertical centre of its bounds.
    func pageIndices(of drawing: PKDrawing) -> [Int] {
        drawing.strokes.map { pageIndex(nearestY: $0.renderBounds.midY) }
    }

    /// One drawing in document space → page-relative drawings. Pages without ink are absent.
    func decompose(_ drawing: PKDrawing) -> [UUID: PKDrawing] {
        var strokes: [Int: [PKStroke]] = [:]
        for (stroke, index) in zip(drawing.strokes, pageIndices(of: drawing)) {
            let origin = pageRect(index).origin
            var local = stroke
            local.transform = stroke.transform.concatenating(CGAffineTransform(translationX: -origin.x, y: -origin.y))
            strokes[index, default: []].append(local)
        }
        return Dictionary(uniqueKeysWithValues: strokes.map { (pages[$0.key].id, PKDrawing(strokes: $0.value)) })
    }
}

/// Canvas pages grow right and down as ink nears an edge. Growth to the left or
/// top would shift every stroke and object, so v1 doesn't do it. Margin and step
/// are provisional until the 004 A16 measurements; the cap is the schema limit.
enum CanvasGrowth {
    static let edgeMargin: CGFloat = 400
    static let step: CGFloat = 1_000

    static func grown(_ size: PageSize, toFit bounds: CGRect) -> PageSize {
        guard !bounds.isNull, !bounds.isEmpty else { return size }
        var next = size
        let cap = DocumentLimits.maxCanvasSide
        while bounds.maxX > next.width - edgeMargin, next.width < cap { next.width = min(cap, next.width + step) }
        while bounds.maxY > next.height - edgeMargin, next.height < cap { next.height = min(cap, next.height + step) }
        return next
    }
}

/// Lasso hit-testing, promoted from the 004 spike. Selection means any visible
/// centreline intersects the polygon; it is not PencilKit's partial-stroke lasso.
enum EditorGeometry {
    static func viewport(_ point: CGPoint, zoom: CGFloat, offset: CGPoint) -> CGPoint {
        CGPoint(x: point.x * zoom - offset.x, y: point.y * zoom - offset.y)
    }

    static func document(_ point: CGPoint, zoom: CGFloat, offset: CGPoint) -> CGPoint {
        CGPoint(x: (point.x + offset.x) / zoom, y: (point.y + offset.y) / zoom)
    }

    static func polygon(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.close()
        return path
    }

    static func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func cross(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        func onSegment(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Bool {
            abs(cross(p, q, r)) < 0.0001 && r.x >= min(p.x, q.x) - 0.0001 &&
            r.x <= max(p.x, q.x) + 0.0001 && r.y >= min(p.y, q.y) - 0.0001 &&
            r.y <= max(p.y, q.y) + 0.0001
        }
        let abC = cross(a, b, c), abD = cross(a, b, d)
        let cdA = cross(c, d, a), cdB = cross(c, d, b)
        if ((abC > 0 && abD < 0) || (abC < 0 && abD > 0)) &&
            ((cdA > 0 && cdB < 0) || (cdA < 0 && cdB > 0)) { return true }
        return onSegment(a, b, c) || onSegment(a, b, d) || onSegment(c, d, a) || onSegment(c, d, b)
    }

    static func intersects(_ a: CGPoint, _ b: CGPoint, polygon points: [CGPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        let path = polygon(points)
        if path.contains(a) || path.contains(b) { return true }
        return points.indices.contains { i in
            segmentsIntersect(a, b, points[i], points[(i + 1) % points.count])
        }
    }

    static func intersects(_ frame: CGRect, polygon points: [CGPoint]) -> Bool {
        guard points.count >= 3 else { return false }
        if points.contains(where: { frame.contains($0) }) { return true }
        let corners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)]
        return corners.indices.contains { intersects(corners[$0], corners[($0 + 1) % 4], polygon: points) }
    }

    static func intersects(_ stroke: PKStroke, polygon points: [CGPoint]) -> Bool {
        guard points.count >= 3, !stroke.path.isEmpty else { return false }
        let selectionPath = polygon(points)
        guard stroke.renderBounds.intersects(selectionPath.bounds) else { return false }
        let ranges = stroke.mask == nil ? [CGFloat(0)...CGFloat(max(0, stroke.path.count - 1))] : stroke.maskedPathRanges
        for range in ranges {
            var previous: CGPoint?
            for sample in stroke.path.interpolatedPoints(in: range, by: .distance(2)) {
                let point = sample.location.applying(stroke.transform)
                if selectionPath.contains(point) { return true }
                if let previous, intersects(previous, point, polygon: points) { return true }
                previous = point
            }
        }
        return false
    }
}
