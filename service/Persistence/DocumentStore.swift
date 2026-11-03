import Foundation
import PencilKit

// Document packages on disk. Contract: docs/database/document-schema-v1.md
// (Save, Load, List, Create and delete, Migration).

enum DocumentStoreError: Error, Equatable, Sendable {
    case notFound(UUID)
    /// The package cannot be opened. The reason names a file or rule, never content.
    case damaged(String)
    case unsupportedVersion(found: Int, supported: Int)
    case conflict(onDisk: Int)
    case invalidTitle
    case invalidAsset(String)
}

enum LoadIssue: Equatable, Sendable {
    /// The bytes are kept and re-saved unchanged; the editor opens the page read-only.
    case inkUnreadable(UUID)
    case assetMissing(String)
    case objectOutOfBounds(UUID)
    case objectTooLarge(UUID)
    case optionalFileUnreadable(String)
}

struct LoadedDocument: Equatable, Sendable {
    var document: Document
    var issues: [LoadIssue]
}

struct SaveReceipt: Equatable, Sendable {
    var revision: Int
    var updatedAt: Date
    var packageURL: URL
}

struct DocumentSummary: Equatable, Identifiable, Sendable {
    enum State: Equatable, Sendable {
        case ok
        case damaged
        case unsupported(version: Int)
    }

    var packageURL: URL
    /// From the manifest, or parsed from the folder name when the manifest is unreadable.
    var documentId: UUID?
    var type: DocumentType?
    /// The document title, or the folder name for a package that can't be read.
    var title: String
    var updatedAt: Date?
    var state: State

    var id: URL { packageURL }
}

/// Every file write in a save goes through this, so tests can interrupt a save.
struct PackageFileWriter: Sendable {
    var write: @Sendable (Data, URL) throws -> Void

    static let standard = PackageFileWriter { data, url in try data.write(to: url) }
}

actor DocumentStore {
    enum FileName {
        static let manifest = "manifest.json"
        static let pages = "pages.json"
        static let objects = "objects.json"
        static let conversation = "conversation.json"
        static let thumbnail = "thumbnail.png"
        static let ink = "ink"
        static let assets = "assets"
    }

    let rootURL: URL
    let preMigrationURL: URL
    private let migrator: DocumentMigrator
    private let writer: PackageFileWriter
    private let appVersion: String
    /// The replacement directory used by the most recent save; tests check it is gone.
    private(set) var lastStagingRoot: URL?

    init(rootURL: URL, preMigrationURL: URL, migrator: DocumentMigrator = .standard,
         writer: PackageFileWriter = .standard, appVersion: String = DocumentStore.bundleVersion) {
        self.rootURL = rootURL
        self.preMigrationURL = preMigrationURL
        self.migrator = migrator
        self.writer = writer
        self.appVersion = appVersion
    }

    /// `Documents/Documents/` for packages and `Application Support/PreMigration/` for migration copies.
    static func standard() throws -> DocumentStore {
        let fileManager = FileManager.default
        let documents = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return DocumentStore(rootURL: documents.appendingPathComponent("Documents", isDirectory: true),
                             preMigrationURL: support.appendingPathComponent("PreMigration", isDirectory: true))
    }

    static var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    func packageURL(for id: UUID) -> URL {
        rootURL.appendingPathComponent("\(id.uuidString).\(DocumentSchema.packageExtension)", isDirectory: true)
    }

    // MARK: - Create and delete

    func create(type: DocumentType, title: String? = nil) throws -> Document {
        let now = Date()
        let size = type == .canvas ? DocumentSchema.newCanvasSize : DocumentSchema.a4
        var document = Document(
            manifest: DocumentManifest(schemaVersion: DocumentSchema.currentVersion, id: UUID(), type: type,
                                       title: title ?? type.defaultTitle, revision: 0,
                                       createdAt: now, updatedAt: now, appVersion: appVersion),
            pages: [Page(id: UUID(), size: size, background: .blank)],
            objects: [])
        let receipt = try save(document, expectedRevision: nil)
        document.manifest.updatedAt = receipt.updatedAt
        return document
    }

    /// Permanent delete; there is no trash until PE-004.
    func delete(id: UUID) throws {
        let url = packageURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw DocumentStoreError.notFound(id) }
        try FileManager.default.removeItem(at: url)
    }

    /// Deletes a listed package by URL, including damaged ones whose folder name is not a UUID.
    /// Only direct children of the store root with the package extension are accepted.
    func deletePackage(at url: URL) throws {
        guard url.pathExtension == DocumentSchema.packageExtension,
              url.deletingLastPathComponent().standardizedFileURL.path == rootURL.standardizedFileURL.path,
              FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentStoreError.damaged("not a package in this library")
        }
        try FileManager.default.removeItem(at: url)
    }

    /// Changes only the title. The title is not content, so `revision` stays the same.
    @discardableResult
    func rename(id: UUID, to title: String) throws -> SaveReceipt {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= DocumentLimits.maxTitleLength else { throw DocumentStoreError.invalidTitle }
        var manifest = try load(id: id).document.manifest
        let live = packageURL(for: id)
        if manifest.title == title {
            return SaveReceipt(revision: manifest.revision, updatedAt: manifest.updatedAt, packageURL: live)
        }
        manifest.title = title
        manifest.updatedAt = Date()
        // Rename is metadata-only. Clone the original package so unreadable optional
        // files, ink, assets and unknown files are preserved byte-for-byte.
        let fm = FileManager.default
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: rootURL, create: true)
        lastStagingRoot = staging
        defer { try? fm.removeItem(at: staging) }
        let replacement = staging.appendingPathComponent(live.lastPathComponent, isDirectory: true)
        try fm.copyItem(at: live, to: replacement)
        try writer.write(DocumentCoding.encoder().encode(manifest), replacement.appendingPathComponent(FileName.manifest))
        _ = try fm.replaceItemAt(live, withItemAt: replacement)
        return SaveReceipt(revision: manifest.revision, updatedAt: manifest.updatedAt, packageURL: live)
    }

    // MARK: - Save

    /// Writes a complete new package beside the live one, then swaps it in.
    /// A failure before the swap leaves the live package untouched.
    @discardableResult
    func save(_ document: Document, expectedRevision: Int?) throws -> SaveReceipt {
        let fileManager = FileManager.default
        let title = document.manifest.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= DocumentLimits.maxTitleLength else { throw DocumentStoreError.invalidTitle }
        for (name, data) in document.pendingAssets {
            let ext = String(name.split(separator: ".").last ?? "")
            guard AssetName.isValid(name), AssetName.make(for: data, extension: ext) == name else {
                throw DocumentStoreError.invalidAsset(name)
            }
        }

        let liveURL = packageURL(for: document.id)
        let exists = fileManager.fileExists(atPath: liveURL.path)
        // Read only version-independent fields: the live package may predate a migration.
        var onDisk: (schemaVersion: Int, revision: Int, title: String?, updatedAt: Date?)?
        if exists {
            guard let json = Self.readJSONObject(liveURL.appendingPathComponent(FileName.manifest)),
                  let schemaVersion = json["schemaVersion"] as? Int, let revision = json["revision"] as? Int else {
                throw DocumentStoreError.damaged(FileName.manifest)
            }
            let updatedAt = (json["updatedAt"] as? String).flatMap(DocumentCoding.date(from:))
            onDisk = (schemaVersion, revision, json["title"] as? String, updatedAt)
        }
        if let expectedRevision, let onDisk, onDisk.revision != expectedRevision {
            throw DocumentStoreError.conflict(onDisk: onDisk.revision)
        }
        if let from = document.migratedFrom, let onDisk, onDisk.schemaVersion < DocumentSchema.currentVersion {
            try keepPreMigrationCopy(of: liveURL, id: document.id, version: from)
        }

        var manifest = document.manifest
        manifest.schemaVersion = DocumentSchema.currentVersion
        manifest.title = title
        manifest.appVersion = appVersion
        if let onDisk, onDisk.revision == manifest.revision, onDisk.title == title, let kept = onDisk.updatedAt {
            manifest.updatedAt = kept
        } else {
            manifest.updatedAt = Date()
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let stagingRoot = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                              appropriateFor: rootURL, create: true)
        lastStagingRoot = stagingRoot
        defer { try? fileManager.removeItem(at: stagingRoot) }
        let staged = stagingRoot.appendingPathComponent(liveURL.lastPathComponent, isDirectory: true)
        try fileManager.createDirectory(at: staged, withIntermediateDirectories: true)

        let encoder = DocumentCoding.encoder()
        try writer.write(encoder.encode(PagesFile(pages: document.pages)), staged.appendingPathComponent(FileName.pages))
        try writer.write(encoder.encode(ObjectsFile(objects: document.objects)), staged.appendingPathComponent(FileName.objects))
        if let conversation = document.conversation {
            try writer.write(encoder.encode(conversation), staged.appendingPathComponent(FileName.conversation))
        }
        if let thumbnail = document.thumbnail {
            try writer.write(thumbnail, staged.appendingPathComponent(FileName.thumbnail))
        }

        let pageIds = Set(document.pages.map(\.id))
        let ink = document.ink.filter { pageIds.contains($0.key) }
        if !ink.isEmpty {
            let inkURL = staged.appendingPathComponent(FileName.ink, isDirectory: true)
            try fileManager.createDirectory(at: inkURL, withIntermediateDirectories: true)
            for (pageId, data) in ink {
                try writer.write(data, inkURL.appendingPathComponent("\(pageId.uuidString).drawing"))
            }
        }

        // Only referenced assets survive a save; unchanged ones are cloned (APFS copy-on-write).
        let referenced = document.referencedAssets
        if !referenced.isEmpty {
            let assetsURL = staged.appendingPathComponent(FileName.assets, isDirectory: true)
            try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
            for name in referenced.sorted() where AssetName.isValid(name) {
                let target = assetsURL.appendingPathComponent(name)
                let live = liveURL.appendingPathComponent(FileName.assets).appendingPathComponent(name)
                if let data = document.pendingAssets[name] {
                    try writer.write(data, target)
                } else if fileManager.fileExists(atPath: live.path) {
                    try fileManager.copyItem(at: live, to: target)
                }
            }
        }

        // The manifest is written last.
        try writer.write(encoder.encode(manifest), staged.appendingPathComponent(FileName.manifest))

        if exists {
            _ = try fileManager.replaceItemAt(liveURL, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: liveURL)
        }
        return SaveReceipt(revision: manifest.revision, updatedAt: manifest.updatedAt, packageURL: liveURL)
    }

    private func keepPreMigrationCopy(of liveURL: URL, id: UUID, version: Int) throws {
        let fileManager = FileManager.default
        let copy = preMigrationURL.appendingPathComponent("\(id.uuidString).\(DocumentSchema.packageExtension)-v\(version)",
                                                          isDirectory: true)
        guard !fileManager.fileExists(atPath: copy.path) else { return }
        try fileManager.createDirectory(at: preMigrationURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: liveURL, to: copy)
    }

    // MARK: - Load

    func load(id: UUID) throws -> LoadedDocument {
        let url = packageURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { throw DocumentStoreError.notFound(id) }
        return try load(packageURL: url)
    }

    /// Read-only: never repairs, migrates on disk or rewrites the package.
    func load(packageURL url: URL) throws -> LoadedDocument {
        let fileManager = FileManager.default
        var issues: [LoadIssue] = []

        guard let manifestJSON = Self.readJSONObject(url.appendingPathComponent(FileName.manifest)),
              let version = manifestJSON["schemaVersion"] as? Int else {
            throw DocumentStoreError.damaged(FileName.manifest)
        }
        guard version <= DocumentSchema.currentVersion else {
            throw DocumentStoreError.unsupportedVersion(found: version, supported: DocumentSchema.currentVersion)
        }
        var raw = RawPackage(files: [FileName.manifest: manifestJSON])
        for name in [FileName.pages, FileName.objects] {
            guard let json = Self.readJSONObject(url.appendingPathComponent(name)) else {
                throw DocumentStoreError.damaged(name)
            }
            raw.files[name] = json
        }
        let conversationURL = url.appendingPathComponent(FileName.conversation)
        if fileManager.fileExists(atPath: conversationURL.path) {
            if let json = Self.readJSONObject(conversationURL) {
                raw.files[FileName.conversation] = json
            } else {
                issues.append(.optionalFileUnreadable(FileName.conversation))
            }
        }

        var migratedFrom: Int?
        if version < DocumentSchema.currentVersion {
            do {
                raw = try migrator.migrate(raw, from: version, to: DocumentSchema.currentVersion)
            } catch {
                throw DocumentStoreError.damaged("migration from v\(version)")
            }
            migratedFrom = version
        }

        let manifest: DocumentManifest = try Self.decode(raw, FileName.manifest)
        let pages = (try Self.decode(raw, FileName.pages) as PagesFile).pages
        let objects = (try Self.decode(raw, FileName.objects) as ObjectsFile).objects
        var conversation: Conversation?
        if raw.files[FileName.conversation] != nil {
            if let decoded: Conversation = try? Self.decode(raw, FileName.conversation) {
                conversation = decoded
            } else {
                issues.append(.optionalFileUnreadable(FileName.conversation))
            }
        }

        try Self.checkStructure(manifest: manifest, pages: pages, objects: objects, packageURL: url)

        var ink: [UUID: Data] = [:]
        for page in pages {
            let inkURL = url.appendingPathComponent(FileName.ink).appendingPathComponent("\(page.id.uuidString).drawing")
            guard fileManager.fileExists(atPath: inkURL.path) else { continue }
            guard let data = try? Data(contentsOf: inkURL) else {
                issues.append(.inkUnreadable(page.id))
                continue
            }
            if (try? PKDrawing(data: data)) == nil { issues.append(.inkUnreadable(page.id)) }
            ink[page.id] = data
        }

        let pagesById = Dictionary(uniqueKeysWithValues: pages.map { ($0.id, $0) })
        for object in objects {
            let frame = object.frame, page = pagesById[object.pageId]!.size
            let finite = [frame.x, frame.y, frame.width, frame.height].allSatisfy(\.isFinite)
            if !finite || frame.x < 0 || frame.y < 0 || frame.x + frame.width > page.width ||
                frame.y + frame.height > page.height ||
                frame.width < DocumentLimits.minObjectSide || frame.height < DocumentLimits.minObjectSide {
                issues.append(.objectOutOfBounds(object.id))
            }
            if object.source.utf8.count > DocumentLimits.maxSourceBytes { issues.append(.objectTooLarge(object.id)) }
        }

        let assetsURL = url.appendingPathComponent(FileName.assets)
        for name in Set(objects.flatMap(\.assetRefs)).sorted() {
            let path = assetsURL.appendingPathComponent(name).path
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int) ?? nil
            if !AssetName.isValid(name) || size == nil || size! > DocumentLimits.maxAssetBytes {
                issues.append(.assetMissing(name))
            }
        }

        var thumbnail: Data?
        let thumbnailURL = url.appendingPathComponent(FileName.thumbnail)
        if fileManager.fileExists(atPath: thumbnailURL.path) {
            let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            if let data = try? Data(contentsOf: thumbnailURL), data.starts(with: pngSignature) {
                thumbnail = data
            } else {
                issues.append(.optionalFileUnreadable(FileName.thumbnail))
            }
        }

        let document = Document(manifest: manifest, pages: pages, objects: objects, ink: ink,
                                conversation: conversation, thumbnail: thumbnail, migratedFrom: migratedFrom)
        return LoadedDocument(document: document, issues: issues)
    }

    private static func checkStructure(manifest: DocumentManifest, pages: [Page], objects: [DocumentObject],
                                       packageURL: URL) throws {
        let folderId = UUID(uuidString: packageURL.deletingPathExtension().lastPathComponent)
        guard folderId == manifest.id else { throw DocumentStoreError.damaged("manifest id does not match package name") }
        switch manifest.type {
        case .canvas:
            guard pages.count == 1 else { throw DocumentStoreError.damaged("canvas must have exactly one page") }
        case .notebook:
            guard (1...DocumentLimits.maxNotebookPages).contains(pages.count) else {
                throw DocumentStoreError.damaged("notebook page count out of range")
            }
        }
        let pageIds = Set(pages.map(\.id))
        guard pageIds.count == pages.count else { throw DocumentStoreError.damaged("duplicate page id") }
        guard Set(objects.map(\.id)).count == objects.count else { throw DocumentStoreError.damaged("duplicate object id") }
        guard objects.allSatisfy({ pageIds.contains($0.pageId) }) else {
            throw DocumentStoreError.damaged("object on a missing page")
        }
    }

    // MARK: - List

    /// Reads only manifests. Unreadable packages are listed as damaged, never skipped.
    func list() -> [DocumentSummary] {
        let fileManager = FileManager.default
        let urls = (try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey],
                                                         options: [.skipsHiddenFiles])) ?? []
        let summaries = urls.filter { $0.pathExtension == DocumentSchema.packageExtension }.map { url -> DocumentSummary in
            let folderName = url.deletingPathExtension().lastPathComponent
            var summary = DocumentSummary(packageURL: url, documentId: UUID(uuidString: folderName), type: nil,
                                          title: folderName, updatedAt: nil, state: .damaged)
            let manifestURL = url.appendingPathComponent(FileName.manifest)
            guard let json = Self.readJSONObject(manifestURL), let version = json["schemaVersion"] as? Int else {
                return summary
            }
            guard version <= DocumentSchema.currentVersion else {
                summary.state = .unsupported(version: version)
                return summary
            }
            guard let manifest = try? Self.decode(DocumentManifest.self, at: manifestURL),
                  UUID(uuidString: folderName) == manifest.id else { return summary }
            summary.documentId = manifest.id
            summary.type = manifest.type
            summary.title = manifest.title
            summary.updatedAt = manifest.updatedAt
            summary.state = .ok
            return summary
        }
        // Newest first; packages that can't be opened sort last by folder name.
        return summaries.sorted { lhs, rhs in
            switch (lhs.updatedAt, rhs.updatedAt) {
            case let (l?, r?) where l != r: return l > r
            case (_?, _?): return lhs.packageURL.lastPathComponent < rhs.packageURL.lastPathComponent
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.title < rhs.title
            }
        }
    }

    // MARK: - JSON helpers

    private static func readJSONObject(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try DocumentCoding.decoder().decode(type, from: Data(contentsOf: url))
    }

    private static func decode<T: Decodable>(_ raw: RawPackage, _ name: String) throws -> T {
        do {
            let data = try JSONSerialization.data(withJSONObject: raw.files[name] ?? [:])
            return try DocumentCoding.decoder().decode(T.self, from: data)
        } catch {
            throw DocumentStoreError.damaged(name)
        }
    }
}
