import Foundation
import PencilKit
import Testing
@testable import PencilEcho

// Ticket 005 acceptance: docs/database/document-schema-v1.md "Test cases".
// Fixtures live in tests/fixtures/documents/ and are copied into a temporary
// store root, so tests never modify them.
final class DocumentStoreTests {
    static let notebookId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let futureId = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static let damagedId = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    static let missingAssetId = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
    static let canvasId = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let pngName = "c414cd0e204de974f73753c7e28d7638e7b3691bb8b1a2bab6b25bb7fed7ce77.png"

    let base: URL
    let root: URL
    let preMigration: URL

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("DocumentStoreTests-\(UUID().uuidString)")
        root = base.appendingPathComponent("Documents", isDirectory: true)
        preMigration = base.appendingPathComponent("PreMigration", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: base) }

    // MARK: Helpers

    func makeStore(migrator: DocumentMigrator = .standard, writer: PackageFileWriter = .standard) -> DocumentStore {
        DocumentStore(rootURL: root, preMigrationURL: preMigration, migrator: migrator, writer: writer,
                      appVersion: "test")
    }

    /// Copies `tests/fixtures/documents/<name>/<id>.pencilecho` into the store root.
    @discardableResult
    func install(_ name: String) throws -> URL {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/documents/\(name)", isDirectory: true)
        let package = try #require(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == DocumentSchema.packageExtension })
        let target = root.appendingPathComponent(package.lastPathComponent, isDirectory: true)
        try FileManager.default.copyItem(at: package, to: target)
        return target
    }

    /// Relative path → bytes for every file in a package.
    func snapshot(_ url: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let enumerator = try #require(FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let file as URL in enumerator where (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            files[String(file.path.dropFirst(url.path.count))] = try Data(contentsOf: file)
        }
        return files
    }

    func editJSON(_ url: URL, _ change: (inout [String: Any]) -> Void) throws {
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        change(&object)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    // MARK: Round trip

    @Test func loadsTwoPageFixture() async throws {
        try install("v1-notebook-two-pages")
        let loaded = try await makeStore().load(id: Self.notebookId)
        let document = loaded.document
        #expect(loaded.issues.isEmpty)
        #expect(document.manifest.type == .notebook && document.manifest.revision == 12)
        #expect(document.pages.count == 2 && document.pages[0].background == PageBackground(style: .lined, spacing: 24))
        #expect(Set(document.objects.map(\.type)) == [.text, .markdown, .latex, .image])
        #expect(document.objects.first { $0.type == .markdown }?.createdBy ==
            .ai(requestId: UUID(uuidString: "00000000-0000-4000-8000-000000000031")!))
        #expect(document.conversation?.appliedRequests.count == 1 && document.conversation?.messages.count == 2)
        for page in document.pages {
            let drawing = try PKDrawing(data: try #require(document.ink[page.id]))
            #expect(drawing.strokes.count == 1)
        }
    }

    @Test func roundTripInPlace() async throws {
        let url = try install("v1-notebook-two-pages")
        let store = makeStore()
        let before = try await store.load(id: Self.notebookId).document
        let assetBytes = try Data(contentsOf: url.appendingPathComponent("assets/\(Self.pngName)"))

        try await store.save(before, expectedRevision: 12)
        let after = try await store.load(id: Self.notebookId)

        #expect(after.issues.isEmpty)
        #expect(after.document.pages == before.pages)
        #expect(after.document.objects == before.objects)
        #expect(after.document.ink == before.ink)
        #expect(after.document.conversation == before.conversation)
        // Same revision and title: updatedAt is kept.
        #expect(after.document.manifest.updatedAt == before.manifest.updatedAt)
        #expect(try Data(contentsOf: url.appendingPathComponent("assets/\(Self.pngName)")) == assetBytes)
    }

    @Test func roundTripToNewLocationWithPendingAsset() async throws {
        let url = try install("v1-notebook-two-pages")
        var document = try await makeStore().load(id: Self.notebookId).document
        document.pendingAssets[Self.pngName] = try Data(contentsOf: url.appendingPathComponent("assets/\(Self.pngName)"))
        try FileManager.default.removeItem(at: url)

        let store = makeStore()
        try await store.save(document, expectedRevision: nil)
        let reloaded = try await store.load(id: Self.notebookId)
        #expect(reloaded.issues.isEmpty)
        #expect(reloaded.document.objects == document.objects && reloaded.document.ink == document.ink)
    }

    // MARK: Atomic save

    @Test func interruptedSaveLeavesPreviousVersion() async throws {
        let url = try install("v1-notebook-two-pages")
        let before = try snapshot(url)
        struct Interrupted: Error {}
        let store = makeStore(writer: PackageFileWriter { data, target in
            if target.lastPathComponent == DocumentStore.FileName.manifest { throw Interrupted() }
            try data.write(to: target)
        })
        var document = try await store.load(id: Self.notebookId).document
        document.objects.removeAll()
        document.manifest.revision += 1

        await #expect(throws: Interrupted.self) { try await store.save(document, expectedRevision: 12) }

        #expect(try snapshot(url) == before)
        let staging = try #require(await store.lastStagingRoot)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(try await makeStore().load(id: Self.notebookId).document.manifest.revision == 12)
    }

    @Test func staleExpectedRevisionIsConflict() async throws {
        let url = try install("v1-notebook-two-pages")
        let before = try snapshot(url)
        let store = makeStore()
        let document = try await store.load(id: Self.notebookId).document
        await #expect(throws: DocumentStoreError.conflict(onDisk: 12)) {
            try await store.save(document, expectedRevision: 11)
        }
        #expect(try snapshot(url) == before)
    }

    @Test func savedRevisionAndUpdatedAt() async throws {
        try install("v1-notebook-two-pages")
        let store = makeStore()
        var document = try await store.load(id: Self.notebookId).document
        document.manifest.revision = 13
        let receipt = try await store.save(document, expectedRevision: 12)
        #expect(receipt.revision == 13)
        #expect(receipt.updatedAt > document.manifest.updatedAt)
        let manifest = try await store.load(id: Self.notebookId).document.manifest
        #expect(manifest.revision == 13 && manifest.appVersion == "test")
    }

    // MARK: Load failures and issues

    @Test func unsupportedVersionModifiesNothing() async throws {
        let url = try install("v99-future")
        let before = try snapshot(url)
        let dateBefore = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent("manifest.json").path)[.modificationDate] as? Date
        await #expect(throws: DocumentStoreError.unsupportedVersion(found: 99, supported: 1)) {
            try await makeStore().load(id: Self.futureId)
        }
        #expect(try snapshot(url) == before)
        let dateAfter = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent("manifest.json").path)[.modificationDate] as? Date
        #expect(dateAfter == dateBefore)
    }

    @Test func damagedManifestFailsButIsListed() async throws {
        try install("damaged-manifest")
        try install("v1-canvas-empty")
        let store = makeStore()
        await #expect(throws: DocumentStoreError.damaged("manifest.json")) { try await store.load(id: Self.damagedId) }
        let summaries = await store.list()
        #expect(summaries.count == 2)
        #expect(summaries.first?.state == .ok)
        let damaged = try #require(summaries.first { $0.documentId == Self.damagedId })
        #expect(damaged.state == .damaged && damaged.title == Self.damagedId.uuidString)
    }

    @Test func futureVersionIsListedAsUnsupported() async throws {
        try install("v99-future")
        #expect(await makeStore().list().first?.state == .unsupported(version: 99))
    }

    @Test func missingAssetIsAnIssue() async throws {
        try install("missing-asset")
        let loaded = try await makeStore().load(id: Self.missingAssetId)
        #expect(loaded.issues == [.assetMissing(String(repeating: "a", count: 64) + ".png")])
    }

    @Test func unreadableInkIsKeptAndReported() async throws {
        let url = try install("v1-notebook-two-pages")
        let pageId = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
        let inkURL = url.appendingPathComponent("ink/\(pageId.uuidString).drawing")
        let garbage = Data("not a drawing".utf8)
        try garbage.write(to: inkURL)

        let store = makeStore()
        let loaded = try await store.load(id: Self.notebookId)
        #expect(loaded.issues == [.inkUnreadable(pageId)])
        try await store.save(loaded.document, expectedRevision: 12)
        #expect(try Data(contentsOf: inkURL) == garbage)
    }

    @Test func structuralDamageThrows() async throws {
        let url = try install("v1-notebook-two-pages")
        try editJSON(url.appendingPathComponent("objects.json")) { json in
            var objects = json["objects"] as! [[String: Any]]
            objects[0]["pageId"] = UUID().uuidString
            json["objects"] = objects
        }
        await #expect(throws: DocumentStoreError.damaged("object on a missing page")) {
            try await makeStore().load(id: Self.notebookId)
        }
    }

    @Test func outOfBoundsObjectIsAnIssue() async throws {
        let url = try install("v1-notebook-two-pages")
        try editJSON(url.appendingPathComponent("objects.json")) { json in
            var objects = json["objects"] as! [[String: Any]]
            objects[0]["frame"] = ["x": 500, "y": 10, "width": 200, "height": 40]
            json["objects"] = objects
        }
        let issues = try await makeStore().load(id: Self.notebookId).issues
        #expect(issues == [.objectOutOfBounds(UUID(uuidString: "00000000-0000-4000-8000-000000000021")!)])
    }

    // MARK: Save rules

    @Test func orphanAssetIsDroppedOnSave() async throws {
        let url = try install("v1-notebook-two-pages")
        let store = makeStore()
        var document = try await store.load(id: Self.notebookId).document
        document.objects.removeAll { $0.type == .image }
        document.manifest.revision += 1
        try await store.save(document, expectedRevision: 12)
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("assets/\(Self.pngName)").path))
    }

    @Test func unknownFilesDroppedUnknownKeysIgnored() async throws {
        let url = try install("v1-notebook-two-pages")
        try Data("x".utf8).write(to: url.appendingPathComponent("extra.txt"))
        try editJSON(url.appendingPathComponent("manifest.json")) { $0["futureKey"] = ["nested": true] }

        let store = makeStore()
        let loaded = try await store.load(id: Self.notebookId)
        #expect(loaded.issues.isEmpty)
        try await store.save(loaded.document, expectedRevision: 12)
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("extra.txt").path))
    }

    @Test func invalidTitleAndAssetAreRejected() async throws {
        try install("v1-notebook-two-pages")
        let store = makeStore()
        var document = try await store.load(id: Self.notebookId).document
        document.manifest.title = "   "
        await #expect(throws: DocumentStoreError.invalidTitle) { try await store.save(document, expectedRevision: 12) }

        document.manifest.title = "Fine"
        document.pendingAssets[Self.pngName] = Data("different bytes".utf8)
        await #expect(throws: DocumentStoreError.invalidAsset(Self.pngName)) {
            try await store.save(document, expectedRevision: 12)
        }
    }

    // MARK: Create, list, delete

    @Test func createListDelete() async throws {
        let store = makeStore()
        let canvas = try await store.create(type: .canvas)
        let notebook = try await store.create(type: .notebook, title: "Homework")
        #expect(canvas.manifest.revision == 0 && canvas.manifest.title == "Untitled Canvas")
        #expect(canvas.pages.map(\.size) == [DocumentSchema.newCanvasSize])
        #expect(notebook.pages.map(\.size) == [DocumentSchema.a4])

        let listed = await store.list()
        #expect(listed.map(\.documentId) == [notebook.id, canvas.id])
        #expect(listed.allSatisfy { $0.state == .ok })
        #expect(try await store.load(id: notebook.id).document.manifest.title == "Homework")

        try await store.delete(id: canvas.id)
        #expect(await store.list().map(\.documentId) == [notebook.id])
        await #expect(throws: DocumentStoreError.notFound(canvas.id)) { try await store.delete(id: canvas.id) }
    }

    // MARK: Migration

    @Test func identityMigration() throws {
        let raw = RawPackage(files: ["manifest.json": ["schemaVersion": 1]])
        let migrated = try DocumentMigrator.standard.migrate(raw, from: 1, to: 1)
        #expect(migrated.files["manifest.json"]?["schemaVersion"] as? Int == 1)
        #expect(throws: DocumentMigrator.MigrationError.noPath(from: 0, to: 1)) {
            try DocumentMigrator.standard.migrate(raw, from: 0, to: 1)
        }
    }

    @Test func migrationRunsBeforeDecodingAndKeepsOriginal() async throws {
        let url = try install("v1-canvas-empty")
        // A fake "v0" that stored the title under another key.
        try editJSON(url.appendingPathComponent("manifest.json")) { json in
            json["schemaVersion"] = 0
            json["name"] = json.removeValue(forKey: "title")
        }
        let original = try snapshot(url)
        let migrator = DocumentMigrator(steps: [0: { raw in
            var raw = raw
            var manifest = raw.files["manifest.json"]!
            manifest["title"] = manifest.removeValue(forKey: "name")
            manifest["schemaVersion"] = 1
            raw.files["manifest.json"] = manifest
            return raw
        }])
        let store = makeStore(migrator: migrator)

        let loaded = try await store.load(id: Self.canvasId)
        #expect(loaded.document.migratedFrom == 0 && loaded.document.manifest.title == "Untitled Canvas")
        #expect(try snapshot(url) == original)

        try await store.save(loaded.document, expectedRevision: 0)
        let copy = preMigration.appendingPathComponent("\(Self.canvasId.uuidString).pencilecho-v0")
        #expect(try snapshot(copy) == original)
        #expect(try await makeStore().load(id: Self.canvasId).document.manifest.schemaVersion == 1)
    }

    @Test func migrationStepMustUpgrade() throws {
        let migrator = DocumentMigrator(steps: [0: { $0 }])
        #expect(throws: DocumentMigrator.MigrationError.stepDidNotUpgrade(from: 0)) {
            try migrator.migrate(RawPackage(files: ["manifest.json": ["schemaVersion": 0]]), from: 0, to: 1)
        }
    }
}
