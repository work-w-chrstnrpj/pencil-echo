import Foundation
import Observation

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

    init(store: DocumentStore?) {
        self.store = store
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

    /// Listing stays manifest-only; required-content damage is detected on open.
    /// The editor does its own load too, guarding changes between these two steps.
    func prepareToOpen(_ item: DocumentSummary) async -> Bool {
        guard let store, item.state == .ok, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await store.load(packageURL: item.packageURL)
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
