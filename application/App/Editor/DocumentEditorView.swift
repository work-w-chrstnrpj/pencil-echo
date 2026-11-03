import SwiftUI
import UIKit

/// Shared by every window so saves to one document are serialised by one actor.
enum AppDocuments {
    static let store: DocumentStore? = {
#if DEBUG
        // UI tests get a unique, temporary library. Invalid test arguments fail
        // closed instead of exposing the owner's normal Documents directory.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-libraryTestRoot") {
            guard arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]) else { return nil }
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("LibraryUITests/" + id.uuidString, isDirectory: true)
            let root = base.appendingPathComponent("Documents", isDirectory: true)
            if arguments.contains("-libraryTestDamaged") {
                let damaged = root.appendingPathComponent("00000000-0000-0000-0000-000000000009.pencilecho", isDirectory: true)
                try? FileManager.default.createDirectory(at: damaged, withIntermediateDirectories: true)
                try? Data("{broken".utf8).write(to: damaged.appendingPathComponent("manifest.json"))
            }
            return DocumentStore(rootURL: root, preMigrationURL: base.appendingPathComponent("PreMigration"))
        }
#endif
        return try? DocumentStore.standard()
    }()
}

struct DocumentEditorRepresentable: UIViewControllerRepresentable {
    let session: EditorSession
    let assetsURL: URL?
    /// Lets Ask AI (ticket 010) read the controller's capture region.
    var onMake: ((DocumentEditorController) -> Void)? = nil

    func makeUIViewController(context: Context) -> DocumentEditorController {
        let controller = DocumentEditorController(session: session, assetsURL: assetsURL)
        onMake?(controller)
        return controller
    }

    func updateUIViewController(_ controller: DocumentEditorController, context: Context) {}
}

/// Loads one document, edits it, and saves on close and when the scene leaves the
/// foreground. A document already open in another window opens read-only.
struct DocumentEditorScreen: View {
    let documentId: UUID
    let store: DocumentStore
    let onClose: () -> Void

    private enum Phase {
        case loading
        case ready(EditorSession, assetsURL: URL)
        case failed(String)
    }

    @State private var phase: Phase = .loading
    @State private var ownsEditing = false
    @State private var showsUnsavedAlert = false
    @State private var title = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { Task { await close() } }
                    }
                }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveInBackground() }
        }
        .onDisappear {
            if ownsEditing { OpenDocuments.shared.release(documentId) }
            ownsEditing = false
        }
        .alert("Changes not saved", isPresented: $showsUnsavedAlert) {
            Button("Keep Editing", role: .cancel) {}
            Button("Close Without Saving", role: .destructive) { onClose() }
        } message: {
            Text("The latest changes couldn't be saved. Closing now loses them.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Opening…")
        case .ready(let session, let assetsURL):
            AskAIEditorContainer(session: session, assetsURL: assetsURL)
                .ignoresSafeArea(.container, edges: .bottom)
        case .failed(let message):
            ContentUnavailableView("Can't open this document", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }

    private func load() async {
        guard case .loading = phase else { return }
        ownsEditing = OpenDocuments.shared.claim(documentId)
        do {
            let loaded = try await store.load(id: documentId)
            let session = EditorSession(loaded: loaded, store: store,
                                        readOnlyReason: ownsEditing ? nil : "This document is open in another window, so it opened read-only here.")
            title = loaded.document.manifest.title
            let packageURL = await store.packageURL(for: documentId)
            phase = .ready(session, assetsURL: packageURL.appendingPathComponent(DocumentStore.FileName.assets, isDirectory: true))
        } catch DocumentStoreError.unsupportedVersion {
            releaseEditingClaim()
            phase = .failed("It was saved by a newer version of Pencil Echo.")
        } catch {
            releaseEditingClaim()
            phase = .failed("The document is damaged or missing.")
        }
    }

    private func releaseEditingClaim() {
        if ownsEditing { OpenDocuments.shared.release(documentId) }
        ownsEditing = false
    }

    private func close() async {
        if case .ready(let session, _) = phase, !(await session.saveNow()) {
            showsUnsavedAlert = true
            return
        }
        onClose()
    }

    /// Backgrounding: ask for time to finish the save so a quick app switch loses nothing.
    private func saveInBackground() {
        guard case .ready(let session, _) = phase, session.hasUnsavedChanges else { return }
        let application = UIApplication.shared
        var taskId = UIBackgroundTaskIdentifier.invalid
        taskId = application.beginBackgroundTask(withName: "Save document") {
            application.endBackgroundTask(taskId)
        }
        Task {
            await session.saveNow()
            application.endBackgroundTask(taskId)
        }
    }
}
