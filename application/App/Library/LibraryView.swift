import SwiftUI
import ImageIO

/// Document library (ticket 009): list, create, open, rename and delete.
struct LibraryView: View {
    @State private var model = LibraryModel.standard()
    @State private var opened: DocumentSummary?
    @State private var renaming: DocumentSummary?
    @State private var deleting: DocumentSummary?
    @State private var unavailable: DocumentSummary?
    @State private var showsAISettings = false
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var cellWidth = 200.0

    var body: some View {
        // Each alert or dialog sits on its own view: SwiftUI presents only one per view reliably.
        NavigationStack {
            content
                .navigationTitle("Pencil Echo")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("AI Settings", systemImage: "gearshape") { showsAISettings = true }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("New Canvas", systemImage: "square.and.pencil") { create(.canvas) }.disabled(model.isWorking)
                        Button("New Notebook", systemImage: "book.closed") { create(.notebook) }.disabled(model.isWorking)
                    }
                }
                // An alert, not a confirmationDialog: a dialog opened from a closing context menu is dropped.
                .alert("Delete “\(deleting?.title ?? "")”?", isPresented: isPresented($deleting), presenting: deleting) { item in
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        Task { await model.delete(item) }
                    }
                } message: { _ in
                    Text("This deletes it permanently. It can't be recovered.")
                }
                // Its own view: the outer view already presents the rename sheet.
                .sheet(isPresented: $showsAISettings) { AISettingsView() }
        }
        .alert(unavailable?.unavailableReason ?? "", isPresented: isPresented($unavailable)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unavailable?.state == .damaged
                 ? "This document is damaged. You can delete it from the library."
                 : "This document was saved by a newer version of Pencil Echo.")
        }
        .task { await model.refresh() }
        // Other windows may have changed the library.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .fullScreenCover(item: $opened, onDismiss: { Task { await model.refresh() } }) { item in
            if let id = item.documentId, let store = model.store {
                DocumentEditorScreen(documentId: id, store: store) { opened = nil }
                    .interactiveDismissDisabled()
            }
        }
        .sheet(item: $renaming) { item in
            RenameSheet(title: item.title) { title in Task { await model.rename(item, to: title) } }
        }
        .background {
            // The error alert gets its own host view.
            Color.clear.alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.store == nil {
            ContentUnavailableView("Documents unavailable", systemImage: "exclamationmark.triangle",
                                   description: Text("Pencil Echo can't reach its documents folder."))
        } else if !model.hasLoaded {
            ProgressView("Loading documents…")
        } else if model.hasLoaded && model.items.isEmpty {
            ContentUnavailableView {
                Label("No Documents", systemImage: "square.and.pencil")
            } description: {
                Text("Create a canvas for free-form work or a notebook with A4 pages.")
            } actions: {
                Button("New Canvas") { create(.canvas) }.disabled(model.isWorking)
                Button("New Notebook") { create(.notebook) }.disabled(model.isWorking)
            }
        } else {
            GeometryReader { geometry in
              ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: min(cellWidth, max(1, geometry.size.width - 40))), spacing: 20, alignment: .top)], spacing: 24) {
                    ForEach(model.items) { item in
                        Button { open(item) } label: { LibraryCell(item: item, refreshToken: model.previewGeneration) }
                            .accessibilityIdentifier("library-document-" + (item.documentId?.uuidString ?? item.packageURL.lastPathComponent))
                            .disabled(model.isWorking)
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { renaming = item }
                                .disabled(item.state != .ok)
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
                            }
                            .accessibilityActions {
                                if item.state == .ok {
                                    Button("Rename") { renaming = item }
                                }
                                Button("Delete") { deleting = item }
                            }
                    }
                }
                .padding(20)
              }
              .refreshable { await model.refresh() }
            }
        }
    }

    private func open(_ item: DocumentSummary) {
        guard item.state == .ok else { unavailable = item; return }
        Task {
            if await model.prepareToOpen(item) { opened = item }
            else { unavailable = model.items.first { $0.id == item.id } ?? item }
        }
    }

    private func create(_ type: DocumentType) {
        Task { if let item = await model.create(type) { opened = item } }
    }

    private func isPresented(_ item: Binding<DocumentSummary?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}

private struct LibraryCell: View {
    let item: DocumentSummary
    let refreshToken: Int
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            Label {
                if let reason = item.unavailableReason {
                    Text(reason)
                } else if let date = item.updatedAt {
                    Text(date, format: .dateTime.day().month().year().hour().minute())
                }
            } icon: {
                Image(systemName: item.symbolName)
            }
            .font(.subheadline)
            .foregroundStyle(item.state == .ok ? .secondary : Color.red)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(item.state == .ok ? "Opens the document" : "")
        .accessibilityAddTraits(.isButton)
        .task(id: refreshToken) {
            let loaded = await Self.loadThumbnail(item.thumbnailURL)
            guard !Task.isCancelled else { return }
            thumbnail = loaded
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(uiImage: thumbnail).resizable().scaledToFit().padding(8)
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var accessibilityText: String {
        var parts = [item.title, item.typeName]
        if let reason = item.unavailableReason {
            parts.append(reason)
        } else if let date = item.updatedAt {
            parts.append("edited " + date.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: ", ")
    }

    private static func loadThumbnail(_ url: URL) async -> UIImage? {
        let data = await Task.detached { () -> Data? in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 2 * 1_024 * 1_024 else { return nil }
            return try? Data(contentsOf: url)
        }.value
        guard !Task.isCancelled, let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

private struct RenameSheet: View {
    let onRename: (String) -> Void
    @State private var title: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, onRename: @escaping (String) -> Void) {
        _title = State(initialValue: title)
        self.onRename = onRename
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
                if trimmed.count > DocumentLimits.maxTitleLength {
                    Text("Use at most \(DocumentLimits.maxTitleLength) characters.").foregroundStyle(.red)
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename", action: save).disabled(trimmed.isEmpty || trimmed.count > DocumentLimits.maxTitleLength)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard !trimmed.isEmpty, trimmed.count <= DocumentLimits.maxTitleLength else { return }
        onRename(trimmed)
        dismiss()
    }
}

