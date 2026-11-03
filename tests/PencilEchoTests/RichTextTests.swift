import Testing
import UIKit
@testable import PencilEcho

@MainActor
struct RichTextTests {
    struct Formula: Decodable { let id: String; let source: String }
    @Test func nativeCorpus() throws {
        let url = try #require(Bundle(for: BundleMarker.self).url(forResource: "corpus", withExtension: "json", subdirectory: "latex"))
        let formulas = try JSONDecoder().decode([Formula].self, from: Data(contentsOf: url))
        #expect(formulas.count == 30)
        for formula in formulas {
            let result = RichTextRenderer.build(source: formula.source, type: .latex, width: 520, density: 2)
            #expect(!result.warning, "Native corpus: \(formula.id)")
            #expect(result.text.attribute(.attachment, at: 0, effectiveRange: nil) is NSTextAttachment)
        }
    }
    @Test func renderEvidence() throws {
        let url = try #require(Bundle(for: BundleMarker.self).url(forResource: "corpus", withExtension: "json", subdirectory: "latex"))
        let formulas = try JSONDecoder().decode([Formula].self, from: Data(contentsOf: url))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_200, height: 1_600), format: format).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 1_600))
            for (index, formula) in formulas.enumerated() {
                let x = CGFloat(index % 3) * 400, y = CGFloat(index / 3) * 160
                NSString(string: formula.id).draw(at: CGPoint(x: x + 12, y: y + 8), withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.gray])
                RichTextRenderer.draw(source: formula.source, type: .latex, in: CGRect(x: x + 8, y: y + 34, width: 380, height: 120), density: 2)
            }
        }
        try image.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("011-corpus.png"))
        let zoom = try NativeMathRenderer.image(#"\frac{-b\pm\sqrt{b^2-4ac}}{2a}"#, display: true, width: 400, density: 8)
        let zoomFormat = UIGraphicsImageRendererFormat()
        zoomFormat.scale = 8
        zoomFormat.opaque = true
        let zoomData = UIGraphicsImageRenderer(size: zoom.1, format: zoomFormat).pngData { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: zoom.1))
            zoom.0.draw(at: .zero)
        }
        try zoomData.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("011-math-4x.png"))
    }
    @Test func mixedDelimiters() {
        #expect(MarkdownMathSplitter.split("Before $x^2$ after\n$$\\frac{1}{2}$$") == [
            .markdown("Before "), .math("x^2", display: false), .markdown(" after\n"), .math(#"\frac{1}{2}"#, display: true)])
    }
    @Test func escapedCodeAndUnclosedDelimiters() {
        for source in [#"\$5 and \$10"#, "`$x$`", "```latex\n$x$\n```", "~~~\n$$x$$\n~~~", "$unclosed", "$$x$", "$$x", "$one\ntwo$", "Pay $5 and $10"] {
            #expect(MarkdownMathSplitter.split(source) == [.markdown(source)], "Literal source \(source)")
        }
        let unmatched = String(repeating: "$x ", count: 2_000)
        #expect(MarkdownMathSplitter.split(unmatched) == [.markdown(unmatched)])
        #expect(MarkdownMathSplitter.split(#"\\$x$"#) == [.markdown(#"\\"#), .math("x", display: false)])
    }
    @Test func markdownStylesAndMath() throws {
        let result = RichTextRenderer.build(source: "# Heading\n\n**Bold** and *italic* with $x$\n\n- One\n- `Two`", type: .markdown, width: 400)
        #expect(!result.warning)
        #expect(result.text.string.contains("• One\n• Two"))
        let heading = try #require(result.text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(heading.pointSize == 30)
        let boldRange = (result.text.string as NSString).range(of: "Bold")
        let bold = try #require(result.text.attribute(.font, at: boldRange.location, effectiveRange: nil) as? UIFont)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.traitBold))
    }
    @Test func failuresAndBoundsRetainSource() {
        for source in [#"\unknown{a}"#, #"\frac{1}{"#, "α", String(repeating: "{", count: 33)] {
            let result = RichTextRenderer.build(source: source, type: .latex, width: 240)
            #expect(result.warning)
            #expect(result.text.string.contains(source))
        }
        let source = String(repeating: "long ", count: 7_000)
        #expect(RichTextRenderer.build(source: source, type: .markdown, width: 240).warning)
        let view = RichObjectView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        view.configure(source: source, type: .markdown, density: 8)
        #expect(view.accessibilityLabel?.contains(source) == true)
    }
    @Test func minimumSizeObjectHasSafeLayoutAndWarning() {
        let view = RichObjectView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        view.configure(source: "x^2", type: .latex, density: 8)
        view.layoutIfNeeded()
        #expect(view.hasWarning)
        #expect(view.subviews.allSatisfy { $0.frame.width.isFinite && $0.frame.height.isFinite })
    }
    @Test func zoomRebuildsMathPixels() throws {
        let source = #"\frac{1}{2}+\sqrt{x}"#
        let one = try NativeMathRenderer.image(source, display: true, width: 240, density: 2)
        let four = try NativeMathRenderer.image(source, display: true, width: 240, density: 8)
        #expect(one.1 == four.1)
        #expect(four.0.cgImage!.width == one.0.cgImage!.width * 4)
        #expect(four.0.cgImage!.height == one.0.cgImage!.height * 4)
    }
    @Test func saveReopenResizeAndSingleUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RichText-\(UUID().uuidString)")
        let store = DocumentStore(rootURL: root.appendingPathComponent("Documents"), preMigrationURL: root.appendingPathComponent("PreMigration"), appVersion: "test")
        let created = try await store.create(type: .canvas)
        let session = EditorSession(loaded: try await store.load(id: created.id), store: store)
        let id = try #require(session.addTextObject(at: CGPoint(x: 300, y: 100), source: "Before", type: .markdown))
        try await Task.sleep(for: .milliseconds(30))
        let original = session.objects[0]
        let revision = session.revision
        let source = "# Saved\n\n" + String(repeating: "Editable **words** with $x^2$. ", count: 12)
        session.updateSource(of: id, to: source)
        #expect(session.revision == revision + 1)
        #expect(session.objects[0].frame.height > original.frame.height)
        try await Task.sleep(for: .milliseconds(30))
        session.manager.undo()
        #expect(session.objects[0].source == "Before")
        #expect(session.objects[0].frame == original.frame)
        session.manager.redo()
        #expect(session.objects[0].source == source)
        let oldHeight = session.objects[0].frame.height
        let next = session.resized(session.snapshot, objectId: id, to: CGSize(width: 400, height: 8))
        session.commit(next, named: "Resize")
        #expect(session.objects[0].frame.height < oldHeight)
        #expect(await session.saveNow())
        let reopened = try await store.load(id: created.id).document
        #expect(reopened.objects[0].source == source)
        #expect(reopened.objects[0].frame == session.objects[0].frame)
        #expect(reopened.manifest.revision == session.revision)
    }
}
private final class BundleMarker: NSObject {}
