import UIKit

/// Draws a `plot` object (ticket 016): grid, axes, tick labels and up to four
/// curves sampled from `PlotSpec` functions. Breaks a curve where it is undefined
/// or jumps off the chart, so tan(x) and 1/x don't draw vertical lines.
@MainActor
enum PlotRenderer {
    static let aspect: CGFloat = 0.68
    static let samples = 480
    static let curveColors: [UIColor] = [
        UIColor(red: 0.10, green: 0.32, blue: 0.78, alpha: 1), UIColor(red: 0.80, green: 0.18, blue: 0.16, alpha: 1),
        UIColor(red: 0.13, green: 0.55, blue: 0.25, alpha: 1), UIColor(red: 0.50, green: 0.25, blue: 0.70, alpha: 1),
    ]

    static func height(width: CGFloat) -> CGFloat { (width * aspect).rounded() }

    static func image(_ spec: PlotSpec, size: CGSize, density: CGFloat, handwritten: Bool, appearance: AIAnswerAppearance? = nil) -> UIImage {
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = min(8, max(1, density))
        let expressions = spec.functions.compactMap { try? MathExpression($0) }
        let xs = (0...samples).map { spec.xRange.lowerBound + (spec.xRange.upperBound - spec.xRange.lowerBound) * Double($0) / Double(samples) }
        let values = expressions.map { expression in xs.map { (try? expression.evaluate(x: $0)).flatMap { $0.isFinite ? $0 : nil } } }
        let yRange = spec.yRange ?? autoRange(values.flatMap { $0.compactMap { $0 } })
        let labelFont = handwritten ? RichTextRenderer.font(appearance, size: 13) : UIFont.systemFont(ofSize: 11)
        let titleFont = handwritten ? RichTextRenderer.font(appearance, size: 17, bold: true) : UIFont.boldSystemFont(ofSize: 14)

        return UIGraphicsImageRenderer(size: size, format: rendererFormat).image { context in
            let cg = context.cgContext
            let titleHeight: CGFloat = spec.title == nil ? 0 : titleFont.lineHeight + 4
            let chart = CGRect(x: 34, y: 8 + titleHeight, width: max(1, size.width - 44), height: max(1, size.height - 30 - titleHeight))
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: chart.minX + chart.width * (x - spec.xRange.lowerBound) / (spec.xRange.upperBound - spec.xRange.lowerBound),
                        y: chart.maxY - chart.height * (y - yRange.lowerBound) / (yRange.upperBound - yRange.lowerBound))
            }
            if let title = spec.title {
                NSString(string: title).draw(at: CGPoint(x: chart.minX, y: 4), withAttributes: [.font: titleFont, .foregroundColor: UIColor.black])
            }
            // Grid and tick labels.
            let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: UIColor.darkGray]
            cg.setLineWidth(0.5)
            cg.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
            for x in ticks(spec.xRange) {
                let p = point(x, yRange.lowerBound)
                cg.move(to: CGPoint(x: p.x, y: chart.minY)); cg.addLine(to: CGPoint(x: p.x, y: chart.maxY))
                let label = NSString(string: format(x))
                let width = label.size(withAttributes: labelAttributes).width
                label.draw(at: CGPoint(x: p.x - width / 2, y: chart.maxY + 3), withAttributes: labelAttributes)
            }
            for y in ticks(yRange) {
                let p = point(spec.xRange.lowerBound, y)
                cg.move(to: CGPoint(x: chart.minX, y: p.y)); cg.addLine(to: CGPoint(x: chart.maxX, y: p.y))
                let label = NSString(string: format(y))
                let labelSize = label.size(withAttributes: labelAttributes)
                label.draw(at: CGPoint(x: chart.minX - labelSize.width - 4, y: p.y - labelSize.height / 2), withAttributes: labelAttributes)
            }
            cg.strokePath()
            // Axes through zero when zero is in range, otherwise the chart edges.
            cg.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor)
            cg.setLineWidth(1)
            let axisY = yRange.contains(0) ? point(0, 0).y : chart.maxY
            let axisX = spec.xRange.contains(0) ? point(0, 0).x : chart.minX
            cg.move(to: CGPoint(x: chart.minX, y: axisY)); cg.addLine(to: CGPoint(x: chart.maxX, y: axisY))
            cg.move(to: CGPoint(x: axisX, y: chart.minY)); cg.addLine(to: CGPoint(x: axisX, y: chart.maxY))
            cg.strokePath()
            // Curves, clipped to the chart.
            cg.saveGState()
            cg.clip(to: chart)
            cg.setLineWidth(2.2)
            cg.setLineJoin(.round)
            cg.setLineCap(.round)
            let span = yRange.upperBound - yRange.lowerBound
            for (index, series) in values.enumerated() {
                cg.setStrokeColor((appearance.map { _ in RichTextRenderer.ink(appearance) } ?? curveColors[index % curveColors.count]).cgColor)
                var previous: Double?
                for (x, value) in zip(xs, series) {
                    guard let value, abs(value - yRange.lowerBound) < span * 20, abs(value - yRange.upperBound) < span * 20 else {
                        previous = nil
                        continue
                    }
                    let p = point(x, value)
                    if let previous, abs(value - previous) < span * 2 { cg.addLine(to: p) } else { cg.move(to: p) }
                    previous = value
                }
                cg.strokePath()
            }
            cg.restoreGState()
            // Legend for more than one curve.
            if spec.functions.count > 1 {
                var y = chart.minY + 4
                for (index, function) in spec.functions.enumerated() {
                    let text = NSString(string: "y = " + function)
                    let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: (appearance.map { _ in RichTextRenderer.ink(appearance) } ?? curveColors[index % curveColors.count])]
                    let width = text.size(withAttributes: attributes).width
                    text.draw(at: CGPoint(x: chart.maxX - width - 4, y: y), withAttributes: attributes)
                    y += labelFont.lineHeight + 2
                }
            }
        }
    }

    /// Fits the sampled values, ignoring the extreme 2% on each side so asymptotes
    /// don't flatten the curve, with 8% headroom.
    static func autoRange(_ values: [Double]) -> ClosedRange<Double> {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return -10...10 }
        let low = sorted[Int(Double(sorted.count - 1) * 0.02)], high = sorted[Int(Double(sorted.count - 1) * 0.98)]
        if high - low < 1e-9 { return (low - 1)...(high + 1) }
        let pad = (high - low) * 0.08
        return (low - pad)...(high + pad)
    }

    /// About six round-numbered ticks: steps of 1, 2 or 5 × 10ⁿ.
    static func ticks(_ range: ClosedRange<Double>) -> [Double] {
        let span = range.upperBound - range.lowerBound
        guard span > 0, span.isFinite else { return [] }
        let raw = span / 6, magnitude = pow(10, floor(log10(raw)))
        let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= raw } ?? raw
        var value = (range.lowerBound / step).rounded(.up) * step, result: [Double] = []
        while value <= range.upperBound + step * 1e-9, result.count < 20 {
            result.append(abs(value) < step * 1e-9 ? 0 : value)
            value += step
        }
        return result
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...4)))
    }
}
