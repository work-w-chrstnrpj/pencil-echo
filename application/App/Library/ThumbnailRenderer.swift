import PencilKit
import UIKit
import ImageIO

/// Renders `thumbnail.png` for the library (docs/database/document-schema-v1.md).
/// The editor (ticket 008) sets `Document.thumbnail` from this before each save.
@MainActor
enum ThumbnailRenderer {
    static let maxPixelSide = 512.0

    /// First page only, ink above objects, white background. Nil if the document has no pages.
    static func render(_ document: Document, assetsURL: URL? = nil) -> Data? {
        guard let page = document.pages.first, page.size.width.isFinite, page.size.height.isFinite,
              page.size.width > 0, page.size.height > 0,
              page.size.width <= DocumentLimits.maxCanvasSide, page.size.height <= DocumentLimits.maxCanvasSide else { return nil }
        // A canvas page can be huge; show the area that has content, not the whole page.
        let area = contentArea(document, page: page)
        let scale = min(1, maxPixelSide / max(area.width, area.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: (area.width * scale).rounded(.up), height: (area.height * scale).rounded(.up))

        let drawing = document.ink[page.id].flatMap { try? PKDrawing(data: $0) }
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: -area.minX, y: -area.minY)
            for object in document.objects.filter({ $0.pageId == page.id }).sorted(by: { $0.zIndex < $1.zIndex }) {
                draw(object, document: document, assetsURL: assetsURL)
            }
            if let drawing {
                // Render at the thumbnail's pixel density, then place in page coordinates.
                drawing.image(from: area, scale: scale).draw(in: area)
            }
        }
    }

    private static func contentArea(_ document: Document, page: Page) -> CGRect {
        let pageRect = CGRect(x: 0, y: 0, width: page.size.width, height: page.size.height)
        // Notebook pages are shown whole so pages look like paper.
        guard document.manifest.type == .canvas else { return pageRect }
        var bounds = CGRect.null
        if let data = document.ink[page.id], let drawing = try? PKDrawing(data: data), !drawing.strokes.isEmpty {
            bounds = drawing.bounds
        }
        for object in document.objects where object.pageId == page.id && validFrame(object.frame) {
            bounds = bounds.union(CGRect(x: object.frame.x, y: object.frame.y,
                                         width: object.frame.width, height: object.frame.height))
        }
        guard !bounds.isNull else { return CGRect(x: 0, y: 0, width: min(page.size.width, 800), height: min(page.size.height, 600)) }
        // Pad, and keep at least 400 × 300 so a single dot doesn't fill the thumbnail.
        var area = bounds.insetBy(dx: -40, dy: -40)
        if area.width < 400 { area = area.insetBy(dx: -(400 - area.width) / 2, dy: 0) }
        if area.height < 300 { area = area.insetBy(dx: 0, dy: -(300 - area.height) / 2) }
        area = area.intersection(pageRect)
        return area.isNull || area.isEmpty ? pageRect : area
    }

    private static func validFrame(_ frame: PageRect) -> Bool {
        [frame.x, frame.y, frame.width, frame.height].allSatisfy(\.isFinite) &&
            frame.x >= 0 && frame.y >= 0 && frame.width > 0 && frame.height > 0 &&
            frame.x + frame.width <= DocumentLimits.maxCanvasSide && frame.y + frame.height <= DocumentLimits.maxCanvasSide
    }

    private static func draw(_ object: DocumentObject, document: Document, assetsURL: URL?) {
        guard validFrame(object.frame) else { return }
        let rect = CGRect(x: object.frame.x, y: object.frame.y, width: object.frame.width, height: object.frame.height)
        switch object.type {
        case .image:
            if let name = object.assetRefs.first, AssetName.isValid(name),
               let image = assetImage(name, document: document, assetsURL: assetsURL) {
                let fit = min(rect.width / image.size.width, rect.height / image.size.height)
                let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
                image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                      width: size.width, height: size.height))
            } else {
                UIColor.systemGray5.setFill()
                UIBezierPath(rect: rect).fill()
            }
        case .markdown, .latex, .plot:
            RichTextRenderer.draw(source: object.source, type: object.type, in: rect, handwritten: object.rendersHandwritten)
        case .text where object.rendersHandwritten:
            RichTextRenderer.draw(source: object.source, type: object.type, in: rect, handwritten: true)
        case .text:
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            NSString(string: String(object.source.prefix(DocumentLimits.maxSourceBytes))).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                                 attributes: [.font: UIFont.systemFont(ofSize: 18),
                                                              .foregroundColor: UIColor.darkGray,
                                                              .paragraphStyle: style], context: nil)
        }
    }

    private static func assetImage(_ name: String, document: Document, assetsURL: URL?) -> UIImage? {
        let source: CGImageSource?
        if let data = document.pendingAssets[name], data.count <= DocumentLimits.maxAssetBytes {
            source = CGImageSourceCreateWithData(data as CFData, nil)
        } else if let url = assetsURL?.appendingPathComponent(name),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= DocumentLimits.maxAssetBytes {
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        } else { return nil }
        guard let source, let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSide),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

}
