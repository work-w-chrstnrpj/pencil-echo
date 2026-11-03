// Ported from PenEcho inspiration/src/server/model-content.js @ 341e34d (AGPL-3.0-only).
import Foundation
import ImageIO

/// Only PNG data URLs are supported in v1. Never recover JSON from surrounding
/// prose as upstream does; the command validator owns the strict JSON boundary.
enum ModelContent {
    static func pngDataURL(_ data: Data, maxBytes: Int) throws -> String {
        guard data.count <= maxBytes else { throw AIError.imageTooLarge }
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8_192, height <= 8_192,
              width * height <= 16_777_216 else { throw AIError.invalidRequest }
        return "data:image/png;base64," + data.base64EncodedString()
    }
}
