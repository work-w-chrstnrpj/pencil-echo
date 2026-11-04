import SwiftUI
import ImageIO

/// Document library (tickets 009 and 022): a sidebar with Recent, Favorites and
/// filters, plus search, sort, list/grid layout, create, open, rename and delete.
struct LibraryView: View {
    @State private var model = LibraryModel.standard()
    @State private var selectedSection: LibrarySection? = .all
    @State private var searchText = ""
    // Remembered across launches (ticket 022); tests use the same keys directly.
    @AppStorage(LibraryPreferences.sortKey) private var sortRawValue = LibrarySort.lastModified.rawValue
    @AppStorage(LibraryPreferences.layoutKey) private var layoutRawValue = LibraryLayout.grid.rawValue
    @State private var opened: DocumentSummary?
    @State private var renaming: DocumentSummary?
    @State private var deleting: DocumentSummary?
    @State private var unavailable: DocumentSummary?
    @State private var showsAISettings = false
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var cellWidth = 200.0

    private var section: LibrarySection { selectedSection ?? .all }
    private var sort: LibrarySort { LibrarySort(rawValue: sortRawValue) ?? .lastModified }
    private var layout: LibraryLayout { LibraryLayout(rawValue: layoutRawValue) ?? .grid }
    private var displayedItems: [DocumentSummary] {
        model.displayedItems(in: section, search: searchText, sort: sort)
    }

    var body: some View {
        // Each alert or dialog sits on its own view: SwiftUI presents only one per view reliably.
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationTitle("Pencil Echo")
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Search documents")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        sortMenu
                        layoutButton
                        Button("New Canvas", systemImage: "square.and.pencil") { create(.canvas) }
                            .disabled(model.isWorking)
                        Button("New Notebook", systemImage: "book.closed") { create(.notebook) }
                            .disabled(model.isWorking)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        // An alert, not a confirmationDialog: a dialog opened from a closing context menu is dropped.
        .alert("Delete “\(deleting?.title ?? "")”?", isPresented: isPresented($deleting), presenting: deleting) { item in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await model.delete(item) }
            }
        } message: { _ in
            Text("This deletes it permanently. It can't be recovered.")
        }
        // Its own view: the split view already presents the rename sheet.
        .sheet(isPresented: $showsAISettings) { AISettingsView() }
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

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedSection) {
            Section("Library") {
                sidebarRow(.recent)
                sidebarRow(.favorites)
                sidebarRow(.all)
            }
            Section("Types") {
                sidebarRow(.canvases)
                sidebarRow(.notebooks)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Library")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button { showsAISettings = true } label: {
                    Label("AI Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library-ai-settings")
            }
            .background(.bar)
        }
    }

    private func sidebarRow(_ item: LibrarySection) -> some View {
        Label(item.title, systemImage: item.symbolName)
            .tag(item)
            .accessibilityIdentifier("library-sidebar-" + item.rawValue)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if model.store == nil {
            ContentUnavailableView("Documents unavailable", systemImage: "exclamationmark.triangle",
                                   description: Text("Pencil Echo can't reach its documents folder."))
        } else if !model.hasLoaded {
            ProgressView("Loading documents…")
        } else if displayedItems.isEmpty {
            emptyState
        } else if layout == .grid {
            grid
        } else {
            list
        }
    }

    private var grid: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: min(cellWidth, max(1, geometry.size.width - 40))),
                                            spacing: 20, alignment: .top)], spacing: 24) {
                    ForEach(displayedItems) { item in
                        Button { open(item) } label: {
                            LibraryCell(item: item, refreshToken: model.previewGeneration)
                        }
                        .accessibilityIdentifier(cellIdentifier(item))
                        .disabled(model.isWorking)
                        .buttonStyle(.plain)
                        .contextMenu { contextMenu(for: item) }
                        .accessibilityActions { accessibilityActions(for: item) }
                    }
                }
                .padding(20)
            }
            .refreshable { await model.refresh() }
            .accessibilityIdentifier("library-grid")
        }
    }

    private var list: some View {
        List {
            ForEach(displayedItems) { item in
                Button { open(item) } label: { LibraryRow(item: item, refreshToken: model.previewGeneration) }
                    .accessibilityIdentifier(cellIdentifier(item))
                    .disabled(model.isWorking)
                    .buttonStyle(.plain)
                    .contextMenu { contextMenu(for: item) }
                    .accessibilityActions { accessibilityActions(for: item) }
            }
        }
        .listStyle(.plain)
        .refreshable { await model.refresh() }
        .accessibilityIdentifier("library-list")
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if section == .all {
            ContentUnavailableView {
                Label(section.emptyTitle, systemImage: section.symbolName)
            } description: {
                Text(section.emptyDescription)
            } actions: {
                Button("New Canvas") { create(.canvas) }.disabled(model.isWorking)
                Button("New Notebook") { create(.notebook) }.disabled(model.isWorking)
            }
        } else {
            ContentUnavailableView {
                Label(section.emptyTitle, systemImage: section.symbolName)
            } description: {
                Text(section.emptyDescription)
            } actions: {
                if section == .canvases || section == .notebooks {
                    Button(section == .canvases ? "New Canvas" : "New Notebook") {
                        create(section == .canvases ? .canvas : .notebook)
                    }
                    .disabled(model.isWorking)
                }
                Button("Show All Documents") { selectedSection = .all }
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortRawValue) {
                ForEach(LibrarySort.allCases) { option in
                    Label(option.title, systemImage: option.symbolName).tag(option.rawValue)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .disabled(section == .recent)
        .help(section == .recent ? "Recent is newest opened first" : "Sort documents")
        .accessibilityIdentifier("library-sort")
    }

    private var layoutButton: some View {
        Button(layout == .grid ? "List" : "Grid",
               systemImage: layout == .grid ? "list.bullet" : "square.grid.2x2") {
            layoutRawValue = (layout == .grid ? LibraryLayout.list : .grid).rawValue
        }
        .accessibilityIdentifier("library-layout-toggle")
        .help(layout == .grid ? "Show as list" : "Show as grid")
    }

    @ViewBuilder
    private func contextMenu(for item: DocumentSummary) -> some View {
        Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites",
               systemImage: item.isFavorite ? "star.slash" : "star") {
            Task { await model.setFavorite(item, isFavorite: !item.isFavorite) }
        }
        .disabled(item.state != .ok)
        Button("Rename", systemImage: "pencil") { renaming = item }
            .disabled(item.state != .ok)
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
    }

    @ViewBuilder
    private func accessibilityActions(for item: DocumentSummary) -> some View {
        if item.state == .ok {
            Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                Task { await model.setFavorite(item, isFavorite: !item.isFavorite) }
            }
            Button("Rename") { renaming = item }
        }
        Button("Delete") { deleting = item }
    }

    private func cellIdentifier(_ item: DocumentSummary) -> String {
        "library-document-" + (item.documentId?.uuidString ?? item.packageURL.lastPathComponent)
    }

    // MARK: - Actions

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

/// Loads a package thumbnail off the main thread and downsamples it for display.
private struct LibraryThumbnail: View {
    let item: DocumentSummary
    let refreshToken: Int
    var padding: CGFloat = 8

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFit().padding(padding)
            } else {
                Image(systemName: item.symbolName)
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: refreshToken) {
            let loaded = await Self.load(item.thumbnailURL)
            guard !Task.isCancelled else { return }
            thumbnail = loaded
        }
    }

    private static func load(_ url: URL) async -> UIImage? {
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

private struct LibraryCell: View {
    let item: DocumentSummary
    let refreshToken: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryThumbnail(item: item, refreshToken: refreshToken)
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }
            }
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
    }

    private var accessibilityText: String { libraryAccessibilityText(item) }
}

/// A library list row: small thumbnail, title, type, modified date and favorite state.
private struct LibraryRow: View {
    let item: DocumentSummary
    let refreshToken: Int

    var body: some View {
        HStack(spacing: 12) {
            LibraryThumbnail(item: item, refreshToken: refreshToken, padding: 2)
                .frame(width: 72, height: 54)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.subheadline)
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(item.state == .ok ? .secondary : Color.red)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(libraryAccessibilityText(item))
        .accessibilityHint(item.state == .ok ? "Opens the document" : "")
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        if let reason = item.unavailableReason {
            return item.typeName + " · " + reason
        }
        guard let date = item.updatedAt else { return item.typeName }
        return item.typeName + " · Edited " + date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Shared accessible description: title, type, favorite state and availability.
private func libraryAccessibilityText(_ item: DocumentSummary) -> String {
    var parts = [item.title, item.typeName]
    if item.isFavorite { parts.append("Favorite") }
    if let reason = item.unavailableReason {
        parts.append(reason)
    } else if let date = item.updatedAt {
        parts.append("edited " + date.formatted(date: .abbreviated, time: .shortened))
    }
    return parts.joined(separator: ", ")
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
