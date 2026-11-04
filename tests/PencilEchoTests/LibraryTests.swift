import Foundation
import PencilKit
import Testing
import UIKit
@testable import PencilEcho

// Ticket 009: library listing, rename and delete through DocumentStore and LibraryModel,
// plus the thumbnail renderer that ticket 008 calls before saving.
@MainActor
final class LibraryTests {
    let base: URL
    let root: URL
    let store: DocumentStore

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryTests-\(UUID().uuidString)")
        root = base.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = DocumentStore(rootURL: root, preMigrationURL: base.appendingPathComponent("PreMigration"),
                              appVersion: "test")
    }

    deinit { try? FileManager.default.removeItem(at: base) }

    func installFixture(_ name: String) throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/documents/\(name)", isDirectory: true)
        let package = try #require(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == DocumentSchema.packageExtension })
        try FileManager.default.copyItem(at: package, to: root.appendingPathComponent(package.lastPathComponent))
    }

    /// Writes a manifest-only package with controlled dates for section/search/sort tests.
    @discardableResult
    private func writePackage(title: String, type: DocumentType = .canvas, createdAt: Date,
                              updatedAt: Date, lastOpenedAt: Date? = nil,
                              isFavorite: Bool = false) throws -> UUID {
        let id = UUID()
        let package = root.appendingPathComponent(id.uuidString + ".pencilecho", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let manifest = DocumentManifest(schemaVersion: 1, id: id, type: type, title: title, revision: 0,
                                        createdAt: createdAt, updatedAt: updatedAt, appVersion: "test",
                                        isFavorite: isFavorite, lastOpenedAt: lastOpenedAt)
        try DocumentCoding.encoder().encode(manifest)
            .write(to: package.appendingPathComponent(DocumentStore.FileName.manifest))
        return id
    }

    // MARK: Store

    @Test func renameKeepsRevisionAndContent() async throws {
        let created = try await store.create(type: .notebook)
        let receipt = try await store.rename(id: created.id, to: "  Physics  ")
        let loaded = try await store.load(id: created.id).document
        #expect(loaded.manifest.title == "Physics")
        #expect(loaded.manifest.revision == created.manifest.revision && receipt.revision == 0)
        #expect(loaded.pages == created.pages)
        #expect(loaded.manifest.updatedAt >= created.manifest.updatedAt)
    }

    @Test func renameRejectsInvalidTitles() async throws {
        let created = try await store.create(type: .canvas)
        await #expect(throws: DocumentStoreError.invalidTitle) { try await store.rename(id: created.id, to: " ") }
        await #expect(throws: DocumentStoreError.invalidTitle) {
            try await store.rename(id: created.id, to: String(repeating: "x", count: DocumentLimits.maxTitleLength + 1))
        }
        #expect(try await store.load(id: created.id).document.manifest.title == "Untitled Canvas")
    }

    @Test func deletePackageRemovesDamagedAndRefusesOutsideRoot() async throws {
        try installFixture("damaged-manifest")
        let damaged = try #require(await store.list().first)
        #expect(damaged.state == .damaged)
        try await store.deletePackage(at: damaged.packageURL)
        #expect(await store.list().isEmpty)

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pencilecho")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        await #expect(throws: DocumentStoreError.self) { try await store.deletePackage(at: outside) }
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func listingIgnoresNonPackagesAndSortsNewestFirst() async throws {
        try Data("x".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("folder"), withIntermediateDirectories: true)
        let first = try await store.create(type: .canvas)
        let second = try await store.create(type: .notebook)
        try await store.rename(id: first.id, to: "Renamed later")
        #expect(await store.list().map(\.documentId) == [first.id, second.id])
    }

    // MARK: Model

    @Test func modelCreatesRenamesAndDeletes() async throws {
        let model = LibraryModel(store: store)
        await model.refresh()
        #expect(model.hasLoaded && model.items.isEmpty)
        let previewGeneration = model.previewGeneration
        await model.refresh()
        #expect(model.previewGeneration > previewGeneration)

        let canvas = try #require(await model.create(.canvas))
        #expect(canvas.title == "Untitled Canvas" && canvas.type == .canvas)
        await model.create(.notebook)
        #expect(model.items.count == 2)

        await model.rename(canvas, to: "Sketches")
        #expect(model.items.first { $0.documentId == canvas.documentId }?.title == "Sketches")

        let renamed = try #require(model.items.first { $0.documentId == canvas.documentId })
        await model.delete(renamed)
        #expect(model.items.count == 1 && model.items[0].type == .notebook)
        #expect(model.errorMessage == nil)
    }

    @Test func modelShowsDamagedAndReportsErrors() async throws {
        try installFixture("damaged-manifest")
        try installFixture("v99-future")
        let model = LibraryModel(store: store)
        await model.refresh()
        #expect(Set(model.items.compactMap(\.unavailableReason)) == ["Can't open", "Needs a newer Pencil Echo"])

        let damaged = try #require(model.items.first { $0.state == .damaged })
        await model.rename(damaged, to: "Nope")
        #expect(model.errorMessage == nil)

        let created = try #require(await model.create(.canvas))
        await model.rename(created, to: String(repeating: "x", count: DocumentLimits.maxTitleLength + 1))
        #expect(model.errorMessage == "Titles can be up to 200 characters.")
    }

    @Test func modelWithoutStoreReportsOnce() async {
        let model = LibraryModel(store: nil)
        await model.refresh()
        #expect(model.errorMessage != nil && model.items.isEmpty && !model.hasLoaded)
    }

    // MARK: Thumbnail

    @Test func thumbnailIsBoundedPNGWithInk() throws {
        let page = Page(id: UUID(), size: DocumentSchema.a4, background: .blank)
        let point = { (x: CGFloat, y: CGFloat) in
            PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: 0, size: CGSize(width: 8, height: 8),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .black),
                              path: PKStrokePath(controlPoints: [point(100, 400), point(500, 400)], creationDate: Date()))
        let now = Date()
        let document = Document(
            manifest: DocumentManifest(schemaVersion: 1, id: UUID(), type: .notebook, title: "T", revision: 1,
                                       createdAt: now, updatedAt: now, appVersion: "test"),
            pages: [page],
            objects: [DocumentObject(id: UUID(), pageId: page.id, type: .markdown,
                                     frame: PageRect(x: 40, y: 40, width: 300, height: 80), zIndex: 0,
                                     source: "**Answer:** $x = 4$", assetRefs: [], createdBy: .user,
                                     createdAt: now, updatedAt: now)],
            ink: [page.id: PKDrawing(strokes: [stroke]).dataRepresentation()])

        let data = try #require(ThumbnailRenderer.render(document))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let image = try #require(UIImage(data: data))
        #expect(max(image.size.width, image.size.height) <= ThumbnailRenderer.maxPixelSide)
        #expect(abs(image.size.width / image.size.height - 595.0 / 842.0) < 0.01)
    }

    @Test func thumbnailOfEmptyCanvasAndNoPages() throws {
        var canvas = Document(
            manifest: DocumentManifest(schemaVersion: 1, id: UUID(), type: .canvas, title: "C", revision: 0,
                                       createdAt: Date(), updatedAt: Date(), appVersion: "test"),
            pages: [Page(id: UUID(), size: DocumentSchema.newCanvasSize, background: .blank)], objects: [])
        let image = try #require(ThumbnailRenderer.render(canvas).flatMap(UIImage.init(data:)))
        #expect(max(image.size.width, image.size.height) <= ThumbnailRenderer.maxPixelSide)
        canvas.pages = []
        #expect(ThumbnailRenderer.render(canvas) == nil)
    }

    @Test func libraryRebuildsAfterStoreAndModelRelaunch() async throws {
        let first = LibraryModel(store: store)
        let canvas = try #require(await first.create(.canvas))
        let notebook = try #require(await first.create(.notebook))
        await first.rename(canvas, to: "Retained work")
        await first.delete(notebook)
        let reloadedStore = DocumentStore(rootURL: root, preMigrationURL: root.deletingLastPathComponent().appendingPathComponent("PreMigration"))
        let second = LibraryModel(store: reloadedStore)
        await second.refresh()
        #expect(second.items.count == 1)
        #expect(second.items.first?.title == "Retained work")
        let retained = try #require(second.items.first)
        #expect(await second.prepareToOpen(retained))
        let canvasID = try #require(canvas.documentId)
        #expect(try await reloadedStore.load(id: canvasID).document.manifest.type == .canvas)
    }

    @Test func damagedRequiredFileIsMarkedWhenOpening() async throws {
        let created = try await store.create(type: .canvas)
        let model = LibraryModel(store: store)
        await model.refresh()
        let item = try #require(model.items.first)
        let package = await store.packageURL(for: created.id)
        try Data("{broken".utf8).write(to: package.appendingPathComponent("objects.json"))
        #expect(await !model.prepareToOpen(item))
        #expect(model.items.first?.unavailableReason == "Can't open")
        #expect(FileManager.default.fileExists(atPath: package.path))
    }

    @Test func mismatchedManifestIdentityNeverOpensAnotherDocument() async throws {
        let first = try await store.create(type: .canvas)
        let second = try await store.create(type: .notebook)
        let url = await store.packageURL(for: first.id)
        var manifest = first.manifest
        manifest.id = second.id
        try DocumentCoding.encoder().encode(manifest).write(to: url.appendingPathComponent("manifest.json"))
        let listed = await store.list()
        #expect(listed.first { $0.packageURL == url }?.state == .damaged)
        #expect(try await store.load(id: second.id).document.manifest.type == .notebook)
    }

    @Test func renamePreservesUnreadableAndUnknownContentBytes() async throws {
        let created = try await store.create(type: .canvas)
        let package = await store.packageURL(for: created.id)
        let inkURL = package.appendingPathComponent("ink", isDirectory: true)
        try FileManager.default.createDirectory(at: inkURL, withIntermediateDirectories: true)
        let paths = [package.appendingPathComponent("future.bin"), package.appendingPathComponent("conversation.json"),
                     inkURL.appendingPathComponent(created.pages[0].id.uuidString + ".drawing")]
        let bytes = [Data([1, 2, 3]), Data("{broken".utf8), Data([7, 8, 9])]
        for (path, data) in zip(paths, bytes) { try data.write(to: path) }
        try await store.rename(id: created.id, to: "Preserve originals")
        for (path, data) in zip(paths, bytes) { #expect(try Data(contentsOf: path) == data) }
        #expect(try await store.load(id: created.id).document.manifest.title == "Preserve originals")
    }

    @Test func failedRenameLeavesOriginalLoadable() async throws {
        let created = try await store.create(type: .canvas)
        let failing = DocumentStore(rootURL: root, preMigrationURL: root.deletingLastPathComponent().appendingPathComponent("PreMigration"),
                                    writer: PackageFileWriter { _, _ in throw CocoaError(.fileWriteUnknown) })
        await #expect(throws: CocoaError.self) { try await failing.rename(id: created.id, to: "Not committed") }
        #expect(try await store.load(id: created.id).document.manifest.title == created.manifest.title)
        if let staging = await failing.lastStagingRoot { #expect(!FileManager.default.fileExists(atPath: staging.path)) }
    }

    @Test func openDocumentCannotBeRenamedOrDeletedFromAnotherLibrary() async throws {
        let model = LibraryModel(store: store)
        let item = try #require(await model.create(.canvas))
        let id = try #require(item.documentId)
        #expect(OpenDocuments.shared.claim(id))
        defer { OpenDocuments.shared.release(id) }
        await model.rename(item, to: "Must not change")
        #expect(model.errorMessage?.contains("before renaming") == true)
        await model.delete(item)
        #expect(model.errorMessage?.contains("before deleting") == true)
        #expect(try await store.load(id: id).document.manifest.title == item.title)
    }

    @Test func listingFiveHundredPackagesIsDeterministic() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<500 {
            let id = UUID()
            let package = root.appendingPathComponent(id.uuidString + ".pencilecho", isDirectory: true)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let manifest = DocumentManifest(schemaVersion: 1, id: id, type: .canvas, title: "Document \(index)", revision: 0,
                                            createdAt: date, updatedAt: date.addingTimeInterval(Double(index / 2)), appVersion: "test")
            try DocumentCoding.encoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        }
        let first = await store.list()
        #expect(first.count == 500)
        #expect(first.allSatisfy { $0.state == .ok })
        #expect(first.map(\.id) == (await store.list()).map(\.id))
        #expect(zip(first, first.dropFirst()).allSatisfy { ($0.updatedAt ?? .distantPast) >= ($1.updatedAt ?? .distantPast) })
    }

    @Test func imageThumbnailUsesPendingAndSavedAssetBytes() async throws {
        var document = try await store.create(type: .notebook)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let png = renderer.pngData { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32)) }
        let name = AssetName.make(for: png, extension: "png")
        document.pendingAssets[name] = png
        document.objects = [DocumentObject(id: UUID(), pageId: document.pages[0].id, type: .image,
                                            frame: PageRect(x: 0, y: 0, width: 595, height: 842), zIndex: 0,
                                            source: "Red test image", assetRefs: [name], createdBy: .user,
                                            createdAt: Date(), updatedAt: Date())]
        let preview = try #require(ThumbnailRenderer.render(document))
        document.thumbnail = preview
        document.manifest.revision += 1
        try await store.save(document, expectedRevision: 0)
        let loaded = try await store.load(id: document.id).document
        let assets = await store.packageURL(for: document.id).appendingPathComponent("assets", isDirectory: true)
        let regenerated = try #require(ThumbnailRenderer.render(loaded, assetsURL: assets))
        #expect(regenerated == preview)
        #expect(loaded.thumbnail == preview)
        let missing = try #require(ThumbnailRenderer.render(loaded))
        #expect(missing != preview)
    }

    @Test func invalidThumbnailGeometryDoesNotCrash() async throws {
        var document = try await store.create(type: .canvas)
        document.pages[0].size.width = .infinity
        #expect(ThumbnailRenderer.render(document) == nil)
    }


    @Test func editorSaveProducesThumbnailAndRefreshesLibrary() async throws {
        let model = LibraryModel(store: store)
        let item = try #require(await model.create(.canvas))
        let id = try #require(item.documentId)
        let session = EditorSession(loaded: try await store.load(id: id), store: store)
        session.addTextObject(at: CGPoint(x: 300, y: 300), source: "Saved preview")
        #expect(await session.saveNow())
        await model.refresh()
        let loaded = try await store.load(id: id).document
        let preview = try #require(loaded.thumbnail)
        #expect(UIImage(data: preview) != nil)
        #expect(loaded.objects.first?.source == "Saved preview")
        #expect(model.items.first?.updatedAt == loaded.manifest.updatedAt)
        #expect(loaded.manifest.revision == 1)
    }

    // MARK: Library metadata, sections, search and sort (ticket 022)

    @Test func favoriteAndLastOpenedPersistWithoutChangingContent() async throws {
        let created = try await store.create(type: .canvas)
        let original = try await store.load(id: created.id).document
        let openedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try await store.setFavorite(id: created.id, isFavorite: true)
        try await store.recordOpened(id: created.id, at: openedAt)

        let updated = try await store.load(id: created.id).document
        #expect(updated.manifest.isFavorite == true)
        #expect(updated.manifest.lastOpenedAt == openedAt)
        #expect(updated.manifest.revision == original.manifest.revision)
        #expect(updated.manifest.updatedAt == original.manifest.updatedAt)
        #expect(updated.pages == original.pages && updated.objects == original.objects)

        let listed = try #require(await store.list().first)
        #expect(listed.isFavorite && listed.lastOpenedAt == openedAt)
        #expect(listed.createdAt == original.manifest.createdAt)

        try await store.setFavorite(id: created.id, isFavorite: false)
        #expect(try await store.load(id: created.id).document.manifest.isFavorite == false)
    }

    @Test func favoriteWritePreservesUnknownFilesAndFailedWriteKeepsMetadata() async throws {
        let created = try await store.create(type: .canvas)
        let package = await store.packageURL(for: created.id)
        let unknown = package.appendingPathComponent("future.bin")
        try Data([1, 2, 3]).write(to: unknown)

        try await store.setFavorite(id: created.id, isFavorite: true)
        #expect(try Data(contentsOf: unknown) == Data([1, 2, 3]))

        let failing = DocumentStore(rootURL: root,
                                    preMigrationURL: root.deletingLastPathComponent().appendingPathComponent("PreMigration"),
                                    writer: PackageFileWriter { _, _ in throw CocoaError(.fileWriteUnknown) })
        await #expect(throws: CocoaError.self) { try await failing.setFavorite(id: created.id, isFavorite: false) }
        #expect(try await store.load(id: created.id).document.manifest.isFavorite == true)
    }

    @Test func packagesWithoutLibraryMetadataAppearInAllDocuments() async throws {
        try installFixture("v1-canvas-empty")
        let listed = try #require(await store.list().first)
        #expect(listed.state == .ok)
        #expect(listed.isFavorite == false && listed.lastOpenedAt == nil)
        #expect(listed.createdAt != nil)

        let model = LibraryModel(store: store)
        await model.refresh()
        #expect(model.displayedItems(in: .all).count == 1)
        #expect(model.displayedItems(in: .favorites).isEmpty)
        #expect(model.displayedItems(in: .recent).isEmpty)
    }

    @Test func recentWindowAndEverySortKey() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try writePackage(title: "Alpha", createdAt: now.addingTimeInterval(-5 * 86_400),
                         updatedAt: now.addingTimeInterval(-2 * 86_400),
                         lastOpenedAt: now.addingTimeInterval(-1 * 86_400), isFavorite: true)
        try writePackage(title: "bravo", type: .notebook, createdAt: now,
                         updatedAt: now.addingTimeInterval(-3 * 86_400),
                         lastOpenedAt: now.addingTimeInterval(-31 * 86_400))
        try writePackage(title: "Charlie", createdAt: now.addingTimeInterval(-10 * 86_400),
                         updatedAt: now, isFavorite: true)
        try writePackage(title: "Old", createdAt: now.addingTimeInterval(-40 * 86_400),
                         updatedAt: now.addingTimeInterval(-40 * 86_400),
                         lastOpenedAt: now.addingTimeInterval(-40 * 86_400))

        let model = LibraryModel(store: store, now: { now })
        await model.refresh()

        // Recent is the last 30 days, newest opened first.
        #expect(model.displayedItems(in: .recent).map(\.title) == ["Alpha"])
        #expect(model.displayedItems(in: .favorites).map(\.title) == ["Charlie", "Alpha"])
        #expect(model.displayedItems(in: .canvases).map(\.title) == ["Charlie", "Alpha", "Old"])
        #expect(model.displayedItems(in: .notebooks).map(\.title) == ["bravo"])
        #expect(model.displayedItems(in: .all, sort: .title).map(\.title) == ["Alpha", "bravo", "Charlie", "Old"])
        #expect(model.displayedItems(in: .all, sort: .created).map(\.title) == ["bravo", "Alpha", "Charlie", "Old"])
        #expect(model.displayedItems(in: .all, sort: .lastOpened).map(\.title) == ["Alpha", "bravo", "Old", "Charlie"])
        #expect(model.displayedItems(in: .all, sort: .lastModified).map(\.title) == ["Charlie", "Alpha", "bravo", "Old"])
    }

    @Test func searchFiltersTitlesAsTyped() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try writePackage(title: "Calculus homework", createdAt: now, updatedAt: now)
        try writePackage(title: "Physics", type: .notebook, createdAt: now, updatedAt: now)
        try writePackage(title: "Calculus notes", createdAt: now, updatedAt: now)

        let model = LibraryModel(store: store, now: { now })
        await model.refresh()
        #expect(model.displayedItems(in: .all, search: "CALC").count == 2)
        #expect(model.displayedItems(in: .all, search: "homework").map(\.title) == ["Calculus homework"])
        #expect(model.displayedItems(in: .all, search: "   ").count == 3)
        #expect(model.displayedItems(in: .all, search: "missing").isEmpty)
        #expect(model.displayedItems(in: .notebooks, search: "calc").isEmpty)
    }

    @Test func preferencesRememberSortAndLayoutAcrossRelaunch() throws {
        let suite = "LibraryPreferencesTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var preferences = LibraryPreferences(defaults: defaults)
        #expect(preferences.sort == .lastModified && preferences.layout == .grid)
        preferences.sort = .lastOpened
        preferences.layout = .list

        let relaunched = LibraryPreferences(defaults: defaults)
        #expect(relaunched.sort == .lastOpened && relaunched.layout == .list)

        defaults.set("not-a-sort", forKey: LibraryPreferences.sortKey)
        defaults.set("not-a-layout", forKey: LibraryPreferences.layoutKey)
        let invalid = LibraryPreferences(defaults: defaults)
        #expect(invalid.sort == .lastModified && invalid.layout == .grid)
    }

    @Test func modelTogglesFavoriteAndRecordsOpen() async throws {
        let model = LibraryModel(store: store)
        let item = try #require(await model.create(.canvas))
        let id = try #require(item.documentId)
        #expect(model.displayedItems(in: .recent).count == 1)

        await model.setFavorite(item, isFavorite: true)
        let favorited = try #require(model.items.first { $0.documentId == id })
        #expect(favorited.isFavorite)
        #expect(model.displayedItems(in: .favorites).map(\.documentId) == [id])

        await model.setFavorite(favorited, isFavorite: false)
        #expect(model.displayedItems(in: .favorites).isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func openingRecordsLastOpenedForRecent() async throws {
        let created = try await store.create(type: .notebook)
        let model = LibraryModel(store: store)
        await model.refresh()
        let item = try #require(model.items.first)
        #expect(model.displayedItems(in: .recent).isEmpty)

        #expect(await model.prepareToOpen(item))
        #expect(model.displayedItems(in: .recent).map(\.documentId) == [created.id])
        #expect(try await store.load(id: created.id).document.manifest.lastOpenedAt != nil)
    }

    @Test func favoriteIsRefusedWhileAnotherWindowEdits() async throws {
        let model = LibraryModel(store: store)
        let item = try #require(await model.create(.canvas))
        let id = try #require(item.documentId)
        #expect(OpenDocuments.shared.claim(id))
        defer { OpenDocuments.shared.release(id) }

        await model.setFavorite(item, isFavorite: true)
        #expect(model.errorMessage?.contains("before changing favorites") == true)
        #expect(try await store.load(id: id).document.manifest.isFavorite != true)
    }

}
