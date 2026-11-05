import SwiftUI
import Observation
import UIKit

extension EditorSession: AskAIDocument, MCPDraftDocument {
    var documentId: UUID { manifest.id }
    var title: String { manifest.title }
    var captureAssetsURL: URL? { store.rootURL.appendingPathComponent(manifest.id.uuidString + ".pencilecho").appendingPathComponent(DocumentStore.FileName.assets) }
}

@MainActor
@Observable
final class AskAIRegionSource {
    weak var controller: DocumentEditorController?
    var pickerAtTop = false
    var pickerClearance: CGFloat = 100
    var region: CGRect { controller?.askAIRegion ?? .zero }
    var selectionRegion: CGRect?
    var selection: CGRect? { selectionRegion }
}

/// The open editor as an MCP share target (ticket 023).
@MainActor
final class MCPEditorTarget: MCPShareTarget {
    let session: EditorSession
    let source: AskAIRegionSource
    init(session: EditorSession, source: AskAIRegionSource) { self.session = session; self.source = source }
    var shareDocument: any MCPDraftDocument { session }
    func visibleRegion() -> CGRect { source.controller?.visiblePageRegion ?? .zero }
    func selectionRegion() -> CGRect? { source.selection }
}

/// One editor shell owns both trailing panels; PencilKit remains the drawing picker.
struct AskAIEditorContainer: View {
    let session: EditorSession
    let assetsURL: URL?
    var onClose: () -> Void = {}
    var onCreate: (DocumentType) -> Void = { _ in }
    @State private var source: AskAIRegionSource
    @State private var ask: AskAIController
    @State private var chat: AgentChatController
    @State private var autoAsk = AutoAskSettings.load()
    @State private var canvasSettings = CanvasAISettings.load()
    @State private var providerSettings = AISettings.load()
    @State private var fullscreen = false
    @State private var bottomToolbar = false
    @State private var handMode = false
    @State private var panel: String?
    @State private var rename = false
    @State private var title = ""
    @State private var showsDelay = false
    @State private var export: ExportPNG?
    @State private var mcpTarget: MCPEditorTarget
    @State private var showsShare = false
    @State private var shareCenter = MCPShareCenter.shared
    @State private var error: String?
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(session: EditorSession, assetsURL: URL?, onClose: @escaping () -> Void = {}, onCreate: @escaping (DocumentType) -> Void = { _ in }) {
        self.session = session; self.assetsURL = assetsURL; self.onClose = onClose; self.onCreate = onCreate
        let source = AskAIRegionSource()
        _source = State(initialValue: source)
        _chat = State(initialValue: AgentChatController(session: session, region: { source.controller?.visiblePageRegion ?? .zero }, selection: { source.selection }))
        _panel = State(initialValue: session.manifest.chatPanelOpen == true ? "chat" : nil)
        _ask = State(initialValue: AskAIController(document: session, region: { source.region }, selection: { source.selection }))
        _mcpTarget = State(initialValue: MCPEditorTarget(session: session, source: source))
    }

    var body: some View {
        HStack(spacing: 0) {
            editor
            if sizeClass == .regular, panel != nil {
                Divider()
                trailingPanel.frame(width: 360)
            }
        }
        .toolbar(fullscreen ? .hidden : .visible, for: .navigationBar)
        .toolbar { topBar }
        .sheet(isPresented: Binding(get: { sizeClass != .regular && panel != nil }, set: { if !$0 { panel = nil } })) { trailingPanel }
        .sheet(item: $export) { item in PNGShareSheet(data: item.data) }
        .alert("Rename document", isPresented: $rename) {
            TextField("Document name", text: $title)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if !session.rename(to: title) { error = "Enter a title of 1–200 characters." } }
        }
        .alert("Editor", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: autoAsk) { _, value in value.save(); if !value.enabled { ask.toolBegan() } }
        .onChange(of: canvasSettings) { _, value in value.save() }
        .onChange(of: providerSettings) { _, value in value.save() }
        .onChange(of: panel) { _, value in
            session.setChatPanelOpen(value == "chat")
            ask.suspendAutoAsk(value == "chat" || chat.isPending)
            if value == "chat" { ask.cancel() }
            autoAsk = AutoAskSettings.load(); canvasSettings = CanvasAISettings.load(); providerSettings = AISettings.load()
        }
        .task {
            ask.suspendAutoAsk(panel == "chat")
#if DEBUG
            // End-to-end checks (ticket 023): `-MCPAutoShare YES` shares the opened document.
            if UserDefaults.standard.bool(forKey: "MCPAutoShare") { MCPShareCenter.shared.share(mcpTarget) }
#endif
        }
        .onDisappear { ask.cancel(); chat.cancel(); MCPShareCenter.shared.stopSharing(mcpTarget) }
    }

    private var editor: some View {
        DocumentEditorRepresentable(session: session, assetsURL: assetsURL) { [ask] editor in
            source.controller = editor
            editor.onSelectionChanged = { region in Task { @MainActor in if source.selectionRegion != region { source.selectionRegion = region } } }
            editor.onPickerPosition = { top, clearance in
                Task { @MainActor in
                    if source.pickerAtTop != top { source.pickerAtTop = top }; if source.pickerClearance != clearance { source.pickerClearance = clearance }
                }
            }
            editor.onToolBegan = { [weak ask] in ask?.toolBegan() }
            editor.onToolEnded = { [weak ask, chat] inked in
                if !chat.isPending { ask?.toolEnded(inked: inked) }
            }
        }
        .safeAreaInset(edge: (bottomToolbar || source.pickerAtTop) ? .bottom : .top, spacing: 0) {
            if !fullscreen && !session.isReadOnly { aiToolbar.padding(.bottom, bottomToolbar && !source.pickerAtTop ? source.pickerClearance + 8 : 0) }
        }
        .overlay(alignment: .topTrailing) {
            if fullscreen { control("Show controls", "arrow.down.right.and.arrow.up.left") { setFullscreen(false) }.padding().background(.regularMaterial, in: Capsule()) }
        }
        .overlay(alignment: .top) {
            if case .review = ask.phase { AskAIOverlay(controller: ask) }
        }
        .overlay(alignment: .bottomLeading) {
            if shareCenter.isSharing(mcpTarget) { MCPShareBanner().padding(12) }
        }
        .onChange(of: ask.phase) { _, phase in
            chat.isOtherRequestPending = ask.isPending
            if !chat.isPending { updateThinking(phase) }
        }
        .onChange(of: chat.isPending) { _, pending in
            ask.suspendAutoAsk(pending || panel == "chat")
            if pending { ask.cancel() }
            source.controller?.setThinkingRegion(canvasSettings.thinkingIndicator ? chat.pendingRegion : nil)
        }
        .onChange(of: canvasSettings.thinkingIndicator) { _, _ in
            if chat.isPending { source.controller?.setThinkingRegion(canvasSettings.thinkingIndicator ? chat.pendingRegion : nil) }
            else { updateThinking(ask.phase) }
        }
    }

    @ToolbarContentBuilder private var topBar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done", systemImage: "chevron.left", action: onClose).keyboardShortcut(.escape, modifiers: [])
                .accessibilityHint("Saves and returns to the library")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Button(session.manifest.title) { title = session.manifest.title; rename = true }
                    .disabled(session.isReadOnly).accessibilityIdentifier("editor-rename")
                    .accessibilityHint("Rename this document")
                HStack {
                    Text(saveText)
                    Text(chat.isPending ? "Asking…" : (session.hasDrafts ? "Placed" : ask.status)).lineLimit(1)
                }.font(.caption).accessibilityElement(children: .combine)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if session.hasDrafts {
                Menu("Drafts") {
                    Button("Accept all") { session.acceptAllDrafts() }
                    Button("Discard all", role: .destructive) { session.discardAllDrafts() }
                }.disabled(session.isReadOnly)
            }
            if ask.isPending || chat.isPending { Button("Cancel") { ask.cancel(); chat.cancel() } }
            if case .failed = ask.phase { Button("Retry") { ask.retry() } }
            Menu {
                Button("New canvas") { onCreate(.canvas) }
                Button("New notebook") { onCreate(.notebook) }
                Button("Export current page PNG") { if let data = source.controller?.exportCurrentPage() { export = ExportPNG(data: data) } }
            } label: { Label("Document actions", systemImage: "doc.badge.plus") }
                .accessibilityHint("Create a document or share this page as PNG")
            Button("Settings", systemImage: "gearshape") { panel = panel == "settings" ? nil : "settings" }
                .accessibilityHint("Opens AI connections and canvas preferences")
        }
    }

    private var saveText: String {
        switch session.saveState {
        case .saved: "Saved"
        case .pending, .saving: "Saving…"
        case .failed: "Not saved"
        case .readOnly: "Read-only"
        }
    }

    private var aiToolbar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                control("Run AI", "sparkles") { ask.ask() }.disabled(!ask.canAsk || chat.isPending).keyboardShortcut(.return, modifiers: .command)
                Button(autoAsk.enabled ? "Auto" : "Manual") { autoAsk.enabled.toggle() }
                    .frame(minWidth: 60, minHeight: 44).accessibilityLabel("Auto Ask")
                    .accessibilityValue(autoAsk.enabled ? "Auto" : "Manual").accessibilityHint("Switches automatic solving on or off")
                control("Agent chat", "bubble.left.and.bubble.right") { panel = panel == "chat" ? nil : "chat" }
                control("Claude Code", shareCenter.isSharing(mcpTarget) ? "laptopcomputer.and.arrow.down" : "laptopcomputer") { showsShare.toggle() }
                    .accessibilityValue(shareCenter.isSharing(mcpTarget) ? "Sharing" : "Not sharing")
                    .popover(isPresented: $showsShare) { MCPShareView(target: mcpTarget) }
                control("Pause delay", "chevron.down") { showsDelay.toggle() }
                    .popover(isPresented: $showsDelay) {
                        Stepper("Pause: \(autoAsk.delaySeconds.formatted()) seconds", value: $autoAsk.delaySeconds, in: 1...10, step: 0.5).padding().frame(minWidth: 280)
                    }
                if ReasoningLevel.supports(preset: providerSettings.selectedPresetID, model: providerSettings.settings(for: providerSettings.selectedPresetID).model) {
                    Menu {
                        ForEach(ReasoningLevel.allCases, id: \.self) { effort in
                            Button(effort.rawValue.capitalized) {
                                var current = providerSettings.settings(for: providerSettings.selectedPresetID)
                                current.reasoning = effort
                                providerSettings.providers[providerSettings.selectedPresetID] = current
                            }
                        }
                    } label: { Label("Reasoning", systemImage: "brain").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityHint("Sets reasoning for the next request")
                }
                Menu {
                    ForEach(AIAnswerAppearance.Ink.allCases, id: \.self) { ink in
                        Button { canvasSettings.appearance.ink = ink } label: {
                            Label(ink.rawValue.capitalized, systemImage: canvasSettings.appearance.ink == ink ? "checkmark.circle.fill" : "circle.fill")
                        }.tint(Color(uiColor: RichTextRenderer.ink(AIAnswerAppearance(ink: ink))))
                    }
                } label: { Image(systemName: "paintpalette.fill").foregroundStyle(Color(uiColor: RichTextRenderer.ink(canvasSettings.appearance))).frame(width: 44, height: 44) }
                .accessibilityLabel("AI ink color").accessibilityHint("Sets the color of new AI answers")
                control(handMode ? "Resume drawing" : "Hand mode", "hand.draw") {
                    source.controller?.setHandMode(!handMode); handMode = source.controller?.handMode ?? handMode
                }.accessibilityValue(handMode ? "On" : "Off")
                control("Undo", "arrow.uturn.backward") { source.controller?.undoAction() }
                control("Redo", "arrow.uturn.forward") { source.controller?.redoAction() }
                control("Toggle grid", "square.grid.3x3") { session.setGridVisible(!(session.manifest.gridVisible ?? true)) }
                    .accessibilityValue((session.manifest.gridVisible ?? true) ? "On" : "Off")
                control("Fullscreen", "arrow.up.left.and.arrow.down.right") { setFullscreen(true) }
                control(bottomToolbar ? "Move toolbar to top" : "Move toolbar to bottom", "arrow.up.arrow.down") { bottomToolbar.toggle() }
                    .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
                        if abs(value.translation.height) > abs(value.translation.width) { bottomToolbar = value.translation.height > 0 }
                    })
            }.padding(.horizontal, 8)
        }
        .scrollIndicators(.hidden)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12).padding(.vertical, 4)
    }

    private func control(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 44, height: 44) }
            .accessibilityLabel(label).accessibilityHint(label).help(label)
    }
    private func updateThinking(_ phase: AskAIController.Phase) {
        guard canvasSettings.thinkingIndicator, case .pending(let capture) = phase,
              let index = session.layout.pageIndex(of: capture.context.pageId) else { source.controller?.setThinkingRegion(nil); return }
        let origin = session.layout.pageRect(index).origin
        source.controller?.setThinkingRegion(AskAIController.rect(capture.context.scopeFrame).offsetBy(dx: origin.x, dy: origin.y))
    }
    private func setFullscreen(_ enabled: Bool) { fullscreen = enabled; source.controller?.setFullscreen(enabled) }
    @ViewBuilder private var trailingPanel: some View {
        if panel == "chat" { AgentChatView(controller: chat, onClose: { panel = nil }) }
        else { AISettingsView(onDone: { panel = nil }) }
    }
}

private struct ExportPNG: Identifiable { let id = UUID(); let data: Data }
private struct PNGShareSheet: UIViewControllerRepresentable {
    let data: Data
    final class Coordinator { var directory: URL? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PageExport-" + UUID().uuidString)
        let file = directory.appendingPathComponent("Page.png")
        let items: [Any]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            context.coordinator.directory = directory
            items = [file]
        } catch { items = [data as NSData] }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: directory) }
        return controller
    }
    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) {
        if let directory = coordinator.directory { try? FileManager.default.removeItem(at: directory) }
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
