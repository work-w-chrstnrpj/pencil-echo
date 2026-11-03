// Regenerates the ticket 005 document fixtures. Output is deterministic: fixed IDs,
// dates and stroke points. PencilKit traps without a bundle identifier, so neither
// `swift <file>` nor a plain binary works: compile with an embedded Info.plist that
// sets CFBundleIdentifier, then run from the repository root:
//   xcrun swiftc generate-fixtures.swift -o /tmp/genfix \
//     -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker <Info.plist with CFBundleIdentifier>
//   /tmp/genfix
// (Prefix xcrun with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.)
import CryptoKit
import Foundation
import PencilKit

let root = URL(fileURLWithPath: "tests/fixtures/documents", isDirectory: true)
let fileManager = FileManager.default

func id(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }
let created = "2026-11-03T12:00:00.000Z", updated = "2026-11-03T12:30:00.000Z"

func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
}

func writePackage(_ name: String, documentId: String, files: [String: Data]) {
    let folder = root.appendingPathComponent(name).appendingPathComponent("\(documentId).pencilecho")
    try? fileManager.removeItem(at: folder.deletingLastPathComponent())
    for (path, data) in files {
        let url = folder.appendingPathComponent(path)
        try! fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! data.write(to: url)
    }
}

func manifest(_ documentId: String, type: String, title: String, revision: Int, version: Int = 1) -> Data {
    json(["schemaVersion": version, "id": documentId, "type": type, "title": title, "revision": revision,
          "createdAt": created, "updatedAt": updated, "appVersion": "fixture"])
}

func page(_ pageId: String, width: Double = 595, height: Double = 842, style: String = "blank",
          spacing: Double? = nil) -> [String: Any] {
    ["id": pageId, "size": ["width": width, "height": height],
     "background": ["style": style, "spacing": spacing.map { $0 as Any } ?? NSNull()]]
}

func object(_ objectId: String, page pageId: String, type: String, frame: [Double], z: Int, source: String,
            assets: [String] = [], createdBy: String = "user") -> [String: Any] {
    ["id": objectId, "pageId": pageId, "type": type, "zIndex": z, "source": source, "assetRefs": assets,
     "frame": ["x": frame[0], "y": frame[1], "width": frame[2], "height": frame[3]],
     "createdBy": createdBy, "createdAt": created, "updatedAt": updated]
}

func ink(_ points: [(Double, Double)]) -> Data {
    let controls = points.enumerated().map { index, point in
        PKStrokePoint(location: CGPoint(x: point.0, y: point.1), timeOffset: Double(index) / 60,
                      size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
    }
    let stroke = PKStroke(ink: PKInk(.pen, color: .black),
                          path: PKStrokePath(controlPoints: controls, creationDate: Date(timeIntervalSince1970: 0)))
    return PKDrawing(strokes: [stroke]).dataRepresentation()
}

// 1×1 transparent PNG.
let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
let pngName = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined() + ".png"

// Two-page notebook: ink on both pages, all four object types, one asset, one applied request.
let notebook = id(1), page1 = id(11), page2 = id(12), request = id(31)
writePackage("v1-notebook-two-pages", documentId: notebook, files: [
    "manifest.json": manifest(notebook, type: "notebook", title: "Fixture notebook", revision: 12),
    "pages.json": json(["pages": [page(page1, style: "lined", spacing: 24), page(page2)]]),
    "objects.json": json(["objects": [
        object(id(21), page: page1, type: "text", frame: [40, 40, 200, 40], z: 0, source: "Solve for x"),
        object(id(22), page: page1, type: "latex", frame: [40, 100, 160, 48], z: 1, source: "2x + 3 = 11"),
        object(id(23), page: page1, type: "markdown", frame: [240, 100, 240, 96], z: 2,
               source: "**Answer:** $x = 4$", createdBy: "ai:\(request)"),
        object(id(24), page: page2, type: "image", frame: [40, 40, 120, 120], z: 0, source: "Sketch",
               assets: [pngName]),
    ]]),
    "conversation.json": json([
        "appliedRequests": [["requestId": request, "appliedAt": updated]],
        "messages": [
            ["id": id(41), "role": "user", "requestId": request, "text": "Solve and explain", "createdAt": updated],
            ["id": id(42), "role": "assistant", "requestId": request, "text": "Solved for x.", "createdAt": updated],
        ],
    ]),
    "ink/\(page1).drawing": ink([(40, 200), (200, 200), (360, 210)]),
    "ink/\(page2).drawing": ink([(60, 300), (120, 360), (200, 320)]),
    "assets/\(pngName)": png,
])

let canvas = id(2)
writePackage("v1-canvas-empty", documentId: canvas, files: [
    "manifest.json": manifest(canvas, type: "canvas", title: "Untitled Canvas", revision: 0),
    "pages.json": json(["pages": [page(id(13), width: 2_000, height: 2_000)]]),
    "objects.json": json(["objects": []]),
])

let future = id(3)
writePackage("v99-future", documentId: future, files: [
    "manifest.json": manifest(future, type: "canvas", title: "From the future", revision: 5, version: 99),
    "pages.json": json(["pages": [page(id(14), width: 2_000, height: 2_000)]]),
    "objects.json": json(["objects": []]),
])

let damaged = id(4)
let fullManifest = manifest(damaged, type: "notebook", title: "Damaged", revision: 3)
writePackage("damaged-manifest", documentId: damaged, files: [
    "manifest.json": fullManifest.prefix(fullManifest.count / 2),
    "pages.json": json(["pages": [page(id(15))]]),
    "objects.json": json(["objects": []]),
])

let missing = id(5), missingPage = id(16)
writePackage("missing-asset", documentId: missing, files: [
    "manifest.json": manifest(missing, type: "notebook", title: "Missing asset", revision: 2),
    "pages.json": json(["pages": [page(missingPage)]]),
    "objects.json": json(["objects": [
        object(id(25), page: missingPage, type: "image", frame: [40, 40, 120, 120], z: 0, source: "",
               assets: [String(repeating: "a", count: 64) + ".png"]),
    ]]),
])

print("Fixtures written to \(root.path)")
