#if DEBUG
import PencilKit

/// Spike-only document geometry. Selection means any visible centerline intersects
/// the polygon; it is not PencilKit's native partial-stroke lasso semantics.
enum SpikeGeometry {
    static let documentSize = CGSize(width: 4_000, height: 4_000)

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

    /// Clamp a group as a whole, preserving the relative positions of ink/objects.
    static func clampedTranslation(_ delta: CGPoint, bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(delta.x, -bounds.minX), documentSize.width - bounds.maxX),
                y: min(max(delta.y, -bounds.minY), documentSize.height - bounds.maxY))
    }
}
#endif
