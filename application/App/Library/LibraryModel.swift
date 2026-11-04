import Foundation
import Observation

/// Sidebar destinations for the library (ticket 022).
enum LibrarySection: String, CaseIterable, Identifiable, Sendable {
    case recent, favorites, all, canvases, notebooks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .favorites: "Favorites"
        case .all: "All Documents"
        case .canvases: "Canvases"
        case .notebooks: "Notebooks"
        }
    }

    var symbolName: String {
        switch self {
        case .recent: "clock"
        case .favorites: "star"
        case .all: "doc.on.doc"
        case .canvases: "square.and.pencil"
        case .notebooks: "book.closed"
        }
    }

    var emptyTitle: String {
        switch self {
        case .recent: "No Recent Documents"
        case .favorites: "No Favorites Yet"
        case .all: "No Documents"
        case .canvases: "No Canvases"
        case .notebooks: "No Notebooks"
        }
    }

    var emptyDescription: String {
        switch self {
        case .recent: "Documents you open in the last 30 days appear here."
        case .favorites: "Star a document to keep it here."
        case .all: "Create a canvas for free-form work or a notebook with A4 pages."
        case .canvases: "Create a canvas for free-form work."
        case .notebooks: "Create a notebook with A4 pages."
        }
    }
}

/// Remembered sort keys (ticket 022).
enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case lastModified, lastOpened, title, created

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastModified: "Last Modified"
        case .lastOpened: "Last Opened"
        case .title: "Title"
        case .created: "Created"
        }
    }

    var symbolName: String {
        switch self {
        case .lastModified: "clock"
        case .lastOpened: "clock.arrow.circlepath"
        case .title: "textformat"
        case .created: "calendar"
        }
    }
}

enum LibraryLayout: String, CaseIterable, Identifiable, Sendable {
    case grid, list

    var id: String { rawValue }
}

/// Sort and layout choices survive relaunch through UserDefaults (ticket 022).
struct LibraryPreferences {
    static let sortKey = "library.sort"
    static let layoutKey = "library.layout"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var sort: LibrarySort {
        get { LibrarySort(rawValue: defaults.string(forKey: Self.sortKey) ?? "") ?? .lastModified }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.sortKey) }
    }

    var layout: LibraryLayout {
        get { LibraryLayout(rawValue: defaults.string(forKey: Self.layoutKey) ?? "") ?? .grid }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.layoutKey) }
    }
}

/// State for the document library (ticket 009). The list is always rebuilt from
/// the packages on disk; there is no separate database.
@MainActor
@Observable
final class LibraryModel {
    private(set) var items: [DocumentSummary] = []
    private(set) var hasLoaded = false
    /// User-facing failure text. Never includes document content.
    var errorMessage: String?

    let store: DocumentStore?
    private(set) var isWorking = false
    private var refreshGeneration = 0
    private(set) var previewGeneration = 0
    /// Recent includes documents opened in this many days (ticket 022).
    let recentWindowDays = 30
    private let now: () -> Date

    init(store: DocumentStore?, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        if store == nil { errorMessage = "Pencil Echo can't reach its documents folder." }
    }

    static func standard() -> LibraryModel {
        LibraryModel(store: AppDocuments.store)
    }

    func refresh() async {
        guard let store else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        let listed = await store.list()
        guard generation == refreshGeneration else { return }
        items = listed
        previewGeneration += 1
        hasLoaded = true
    }

    /// Creates and lists a new document; returns its summary so the caller can open it.
    @discardableResult
    func create(_ type: DocumentType) async -> DocumentSummary? {
        guard let store, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            let document = try await store.create(type: type)
            try? await store.recordOpened(id: document.id, at: now())
            await refresh()
            return items.first { $0.documentId == document.id }
        } catch {
            errorMessage = "Couldn't create the \(type == .canvas ? "canvas" : "notebook")."
            return nil
        }
    }

    func rename(_ item: DocumentSummary, to title: String) async {
        guard let store, let id = item.documentId, item.state == .ok, !isWorking else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        guard OpenDocuments.shared.claim(id) else {
            errorMessage = "Close this document in its other window before renaming it."
            return
        }
        isWorking = true
        defer { OpenDocuments.shared.release(id); isWorking = false }
        do {
            try await store.rename(id: id, to: trimmed)
        } catch DocumentStoreError.invalidTitle {
            errorMessage = "Titles can be up to \(DocumentLimits.maxTitleLength) characters."
        } catch {
            errorMessage = "Couldn't rename the document."
        }
        await refresh()
    }

    /// Permanent: there is no trash until PE-004.
    func delete(_ item: DocumentSummary) async {
        guard let store, !isWorking else { return }
        if let id = item.documentId, !OpenDocuments.shared.claim(id) {
            errorMessage = "Close this document in its other window before deleting it."
            return
        }
        isWorking = true
        defer {
            if let id = item.documentId { OpenDocuments.shared.release(id) }
            isWorking = false
        }
        do {
            try await store.deletePackage(at: item.packageURL)
        } catch {
            errorMessage = "Couldn't delete the document."
        }
        await refresh()
    }

    /// Favorites are library metadata (ticket 022). Like rename, the package is
    /// cloned and only `manifest.json` changes, so content and revision stay intact.
    func setFavorite(_ item: DocumentSummary, isFavorite: Bool) async {
        guard let store, let id = item.documentId, item.state == .ok, item.isFavorite != isFavorite,
              !isWorking else { return }
        guard OpenDocuments.shared.claim(id) else {
            errorMessage = "Close this document in its other window before changing favorites."
            return
        }
        isWorking = true
        defer { OpenDocuments.shared.release(id); isWorking = false }
        do {
            try await store.setFavorite(id: id, isFavorite: isFavorite)
        } catch {
            errorMessage = "Couldn't update the favorite."
        }
        await refresh()
    }

    func toggleFavorite(_ item: DocumentSummary) async {
        await setFavorite(item, isFavorite: !item.isFavorite)
    }

    /// Listing stays manifest-only; required-content damage is detected on open.
    /// The editor does its own load too, guarding changes between these two steps.
    func prepareToOpen(_ item: DocumentSummary) async -> Bool {
        guard let store, item.state == .ok, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await store.load(packageURL: item.packageURL)
            await recordOpen(of: item)
            return !Task.isCancelled
        } catch {
            var failed = item
            if case DocumentStoreError.unsupportedVersion(let version, _) = error {
                failed.state = .unsupported(version: version)
            } else { failed.state = .damaged }
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = failed }
            return false
        }
    }

    /// Best effort: Recent stays correct even if the metadata write fails, and a
    /// document already open in another window keeps its existing last-opened date.
    private func recordOpen(of item: DocumentSummary) async {
        guard let store, let id = item.documentId, OpenDocuments.shared.claim(id) else { return }
        defer { OpenDocuments.shared.release(id) }
        let openedAt = now()
        try? await store.recordOpened(id: id, at: openedAt)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].lastOpenedAt = openedAt
        }
    }

    // MARK: - Sections, search and sort (ticket 022)

    /// Documents for one sidebar section after search and sort. Recent is always
    /// newest opened first so opening a document moves it to the top of that list.
    func displayedItems(in section: LibrarySection, search: String = "",
                        sort: LibrarySort = .lastModified) -> [DocumentSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = items.filter { item in
            contains(item, in: section) && (query.isEmpty || item.title.localizedStandardContains(query))
        }
        return selected.sorted { isOrderedBefore($0, $1, by: section == .recent ? .lastOpened : sort) }
    }

    private func contains(_ item: DocumentSummary, in section: LibrarySection) -> Bool {
        switch section {
        case .recent:
            guard let lastOpenedAt = item.lastOpenedAt,
                  let cutoff = Calendar.current.date(byAdding: .day, value: -recentWindowDays, to: now()) else {
                return false
            }
            return lastOpenedAt >= cutoff
        case .favorites: return item.isFavorite
        case .all: return true
        case .canvases: return item.type == .canvas
        case .notebooks: return item.type == .notebook
        }
    }

    private func isOrderedBefore(_ lhs: DocumentSummary, _ rhs: DocumentSummary, by sort: LibrarySort) -> Bool {
        switch sort {
        case .lastModified:
            if let order = dateOrder(lhs.updatedAt, rhs.updatedAt, newestFirst: true) { return order }
        case .lastOpened:
            if let order = dateOrder(lhs.lastOpenedAt, rhs.lastOpenedAt, newestFirst: true) { return order }
        case .created:
            if let order = dateOrder(lhs.createdAt, rhs.createdAt, newestFirst: true) { return order }
        case .title:
            break
        }
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.packageURL.lastPathComponent < rhs.packageURL.lastPathComponent
    }

    /// `true` when `lhs` sorts first. Missing dates always sort last.
    private func dateOrder(_ lhs: Date?, _ rhs: Date?, newestFirst: Bool) -> Bool? {
        switch (lhs, rhs) {
        case let (l?, r?):
            guard l != r else { return nil }
            return newestFirst ? l > r : l < r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return nil
        }
    }

}

extension DocumentSummary {
    var thumbnailURL: URL { packageURL.appendingPathComponent(DocumentStore.FileName.thumbnail) }

    var typeName: String {
        switch type {
        case .canvas: "Canvas"
        case .notebook: "Notebook"
        case nil: "Document"
        }
    }

    var symbolName: String {
        switch (state, type) {
        case (.ok, .canvas): "square.and.pencil"
        case (.ok, .notebook): "book.closed"
        default: "exclamationmark.triangle"
        }
    }

    /// Why the document can't be opened, or nil when it can.
    var unavailableReason: String? {
        switch state {
        case .ok: nil
        case .damaged: "Can't open"
        case .unsupported: "Needs a newer Pencil Echo"
        }
    }
}
