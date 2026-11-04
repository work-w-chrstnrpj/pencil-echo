import UIKit
import SwiftMath

/// Bounded native layout. Failures retain the original source in the model/editor.
enum RichRenderError: Error { case invalidFormula, limit }

@MainActor
enum NativeMathRenderer {
    static func image(_ source: String, display: Bool, width: CGFloat, density: CGFloat,
                      color: UIColor = .black) throws -> (UIImage, CGSize) {
        guard source.utf8.count <= 8_192, source.unicodeScalars.allSatisfy({ (32..<127).contains($0.value) || $0 == "\n" || $0 == "\t" || $0 == "\r" }),
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RichRenderError.invalidFormula }
        let chars = Array(source)
        var depth = 0, commands = 0, index = 0
        while index < chars.count {
            if chars[index] == "\\" { commands += 1; index += 2; continue }
            if chars[index] == "{" { depth += 1 }
            if chars[index] == "}" { depth -= 1 }
            guard (0...32).contains(depth) else { throw RichRenderError.limit }
            index += 1
        }
        guard depth == 0, commands <= 128, source.filter({ $0 == "&" }).count <= 64 else { throw RichRenderError.limit }
        let label = MTMathUILabel()
        label.fontSize = 20
        label.labelMode = display ? .display : .text
        label.textColor = color
        label.displayErrorInline = false
        // SwiftMath lacks the AMS macro \iint. Expand its mathematical
        // equivalent for rendering only; the editable source remains untouched.
        label.latex = source.replacingOccurrences(of: #"\\iint(?![A-Za-z])"#, with: #"\\int\\!\\!\\int"#, options: .regularExpression)
        guard label.error == nil else { throw RichRenderError.invalidFormula }
        let natural = label.intrinsicContentSize
        guard natural.width.isFinite, natural.height.isFinite, natural.width > 0, natural.height > 0,
              width.isFinite, width > 0 else { throw RichRenderError.invalidFormula }
        let fit = min(1, width / natural.width)
        let size = CGSize(width: ceil(natural.width * fit + 2), height: ceil(natural.height * fit + 2))
        let density = min(8, max(1, density))
        guard size.width * density <= 4_096, size.height * density <= 4_096,
              size.width * size.height * density * density <= 4_194_304 else { throw RichRenderError.limit }
        label.frame = CGRect(origin: .zero, size: natural)
        label.layoutIfNeeded()
        guard let displayList = label.displayList else { throw RichRenderError.invalidFormula }
        let format = UIGraphicsImageRendererFormat()
        format.scale = density
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.scaleBy(x: fit, y: fit)
            // SwiftMath's display list uses a bottom-left coordinate system.
            context.cgContext.translateBy(x: 0, y: natural.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            displayList.draw(context.cgContext)
        }
        return (image, size)
    }
}

struct RichTextResult {
    let text: NSAttributedString
    let warning: Bool
}

extension DocumentObject {
    /// AI answers are written in a handwriting style beside the user's ink (ticket 014).
    var rendersHandwritten: Bool {
        if case .ai = createdBy, type != .image { true } else { false }
    }
}

@MainActor
enum RichTextRenderer {
    static let fontSize: CGFloat = 18
    static let inset: CGFloat = 8
    static let maxHeight: CGFloat = 2_048
    /// Handwritten style for AI answers (ticket 014): a built-in handwriting face in a
    /// blue ink that reads as written beside the user's black ink.
    static let handwrittenSize: CGFloat = 26
    static let handwrittenInk = UIColor(red: 0.10, green: 0.32, blue: 0.78, alpha: 1)

    static func handwrittenFont(size: CGFloat, bold: Bool = false) -> UIFont {
        UIFont(name: bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    static func ink(_ appearance: AIAnswerAppearance?) -> UIColor {
        InkAnswer.color(InkStrokeSpec.Color(rawValue: appearance?.ink.rawValue ?? "blue") ?? .blue)
    }
    static func font(_ appearance: AIAnswerAppearance?, size: CGFloat, bold: Bool = false) -> UIFont {
        switch appearance?.font ?? .handwritten {
        case .handwritten: return handwrittenFont(size: size, bold: bold)
        case .system: return UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .rounded:
            let base = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            return UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size)
        }
    }

    static func build(source: String, type: ObjectType, width: CGFloat, density: CGFloat = 1,
                      handwritten: Bool = false, appearance: AIAnswerAppearance? = nil) -> RichTextResult {
        let ink: UIColor = handwritten ? self.ink(appearance) : .black
        let bodyFont = handwritten ? font(appearance, size: handwrittenSize) : UIFont.systemFont(ofSize: fontSize)
        let base: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: ink]
        guard source.utf8.count <= 32 * 1_024, width.isFinite, width >= 24, width <= 2_048 else {
            return fallback(source)
        }
        if type == .text { return RichTextResult(text: NSAttributedString(string: source, attributes: base), warning: false) }
        if type == .plot {
            guard let spec = try? PlotSpec.parse(source) else { return fallback(source) }
            let size = CGSize(width: width - 2 * inset, height: PlotRenderer.height(width: width - 2 * inset))
            let attachment = NSTextAttachment()
            attachment.image = PlotRenderer.image(spec, size: size, density: density, handwritten: handwritten, appearance: appearance)
            attachment.bounds = CGRect(origin: .zero, size: size)
            return RichTextResult(text: NSAttributedString(attachment: attachment), warning: false)
        }
        let segments: [MarkdownMathSplitter.Segment] = type == .latex ? [.math(source, display: true)] : MarkdownMathSplitter.split(source)
        guard segments.count <= 128, segments.filter({ if case .math = $0 { true } else { false } }).count <= 32 else { return fallback(source) }
        // A unique placeholder lets Foundation parse the entire Markdown document,
        // retaining emphasis spanning a formula and block/list semantics.
        let prefix = "PEMATH" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var markdown = "", formulas: [(String, String, Bool)] = []
        for segment in segments {
            switch segment {
            case .markdown(let text): markdown += text
            case .math(let source, let display):
                let token = prefix + "N" + String(formulas.count) + "END"
                formulas.append((token, source, display))
                markdown += display ? "\n\n" + token + "\n\n" : token
            }
        }
        guard let parsed = try? AttributedString(markdown: markdown) else { return fallback(source) }
        let output = NSMutableAttributedString(string: "")
        var previousBlock: Int?, previousList: Int?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            let list = components.first { if case .listItem = $0.kind { true } else { false } }
            if let block, block != previousBlock {
                if output.length > 0 { output.append(NSAttributedString(string: list != nil && previousList != nil ? "\n" : "\n\n", attributes: base)) }
                if let list, case .listItem(let ordinal) = list.kind {
                    let ordered = components.contains { $0.kind == .orderedList }
                    output.append(NSAttributedString(string: ordered ? "\(ordinal). " : "• ", attributes: base))
                }
                previousBlock = block
                previousList = list?.identity
            }
            let intent = run.inlinePresentationIntent ?? []
            var size = fontSize, traits: UIFontDescriptor.SymbolicTraits = []
            for component in components {
                if case .header(let level) = component.kind { size = max(19, 30 - CGFloat(level - 1) * 2); traits.insert(.traitBold) }
            }
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            let codeBlock = components.contains { if case .codeBlock = $0.kind { true } else { false } }
            var font: UIFont
            if intent.contains(.code) || codeBlock {
                font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            } else if handwritten {
                font = self.font(appearance, size: size * handwrittenSize / fontSize, bold: traits.contains(.traitBold))
            } else {
                font = UIFont.systemFont(ofSize: size)
                if let descriptor = font.fontDescriptor.withSymbolicTraits(traits), !traits.isEmpty { font = UIFont(descriptor: descriptor, size: size) }
            }
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            if intent.contains(.code) || codeBlock { attributes[.backgroundColor] = UIColor(white: 0.95, alpha: 1) }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        var warning = false
        for (token, formula, display) in formulas {
            let range = (output.string as NSString).range(of: token)
            guard range.location != NSNotFound else { return fallback(source) }
            do {
                let (image, size) = try NativeMathRenderer.image(formula, display: display, width: max(1, width - 2 * inset),
                                                                 density: density, color: ink)
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: display ? 0 : bodyFont.descender,
                                           width: size.width, height: size.height)
                output.replaceCharacters(in: range, with: NSAttributedString(attachment: attachment))
            } catch {
                warning = true
                output.replaceCharacters(in: range, with: NSAttributedString(string: display ? "$$" + formula + "$$" : "$" + formula + "$", attributes: base))
            }
        }
        return RichTextResult(text: output, warning: warning)
    }

    static func fallback(_ source: String) -> RichTextResult {
        RichTextResult(text: NSAttributedString(string: String(source.prefix(2_000)), attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular), .foregroundColor: UIColor.black
        ]), warning: true)
    }

    static func height(source: String, type: ObjectType, width: CGFloat, handwritten: Bool = false) -> CGFloat {
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = build(source: source, type: type, width: width, handwritten: handwritten).text
        let height = label.sizeThatFits(CGSize(width: max(1, width - 2 * inset), height: maxHeight)).height
        return min(maxHeight, max(32, ceil(height + 2 * inset)))
    }

    /// The width that fits `source` on its own lines, up to `maxWidth`, so a short
    /// answer such as "4" takes only the room it needs.
    static func fittingWidth(source: String, type: ObjectType, maxWidth: CGFloat, handwritten: Bool = false) -> CGFloat {
        let text = build(source: source, type: type, width: max(24, maxWidth), handwritten: handwritten).text
        let natural = text.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: maxHeight),
                                        options: [.usesLineFragmentOrigin], context: nil).width
        return min(maxWidth, max(48, ceil(natural + 2 * inset + 4)))
    }

    static func draw(source: String, type: ObjectType, in rect: CGRect, density: CGFloat = 1, handwritten: Bool = false, appearance: AIAnswerAppearance? = nil) {
        let result = build(source: source, type: type, width: rect.width, density: density, handwritten: handwritten, appearance: appearance)
        let content = CGRect(x: rect.minX + inset, y: rect.minY + inset,
                             width: max(0, rect.width - 2 * inset), height: max(0, rect.height - 2 * inset))
        if content.width > 0, content.height > 0 {
            result.text.draw(with: content, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
        if result.warning { NSString(string: "⚠︎").draw(at: rect.origin, withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.systemOrange]) }
    }
}

@MainActor
final class RichObjectView: UIView {
    private let label = UILabel()
    private let badge = UILabel()
    private var source = ""
    private var type: ObjectType = .text
    private var density: CGFloat = 1
    private var handwritten = false
    private var appearance: AIAnswerAppearance?
    private var renderWidth: CGFloat = 0
    private(set) var hasWarning = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isAccessibilityElement = true
        label.numberOfLines = 0
        label.isUserInteractionEnabled = false
        badge.text = "⚠︎"
        badge.textColor = .systemOrange
        badge.font = .systemFont(ofSize: 16)
        addSubview(label)
        addSubview(badge)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(source: String, type: ObjectType, density: CGFloat, handwritten: Bool = false, appearance: AIAnswerAppearance? = nil) {
        let nextDensity = min(8, max(1, density))
        if self.source == source, self.type == type, self.density == nextDensity, self.handwritten == handwritten, self.appearance == appearance,
           renderWidth == bounds.width { return }
        self.source = source; self.type = type; self.density = nextDensity; self.handwritten = handwritten; self.appearance = appearance
        renderWidth = bounds.width
        let result = RichTextRenderer.build(source: source, type: type, width: bounds.width, density: nextDensity,
                                            handwritten: handwritten, appearance: appearance)
        label.attributedText = result.text
        hasWarning = result.warning
        let area = max(1, bounds.width * bounds.height)
        label.contentScaleFactor = min(nextDensity, max(1, sqrt(4_194_304 / area)))
        label.setNeedsDisplay()
        accessibilityLabel = (type == .latex ? "Formula: " : type == .markdown ? "Markdown: " : type == .plot ? "Graph: " : "Text: ") + source
        accessibilityHint = "Double-tap to edit the source."
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: RichTextRenderer.inset, y: RichTextRenderer.inset,
                             width: max(0, bounds.width - 2 * RichTextRenderer.inset),
                             height: max(0, bounds.height - 2 * RichTextRenderer.inset))
        let overflow = label.sizeThatFits(CGSize(width: max(1, label.bounds.width), height: .greatestFiniteMagnitude)).height > label.bounds.height + 1
        badge.isHidden = !hasWarning && !overflow
        badge.frame = CGRect(x: max(0, bounds.width - 22), y: 0, width: 22, height: 22)
        accessibilityValue = badge.isHidden ? nil : "Rendering warning; source is available in the editor."
    }
}
