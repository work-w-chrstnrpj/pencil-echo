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

/// The editor shell (ticket 024): one navigation bar, a selection bar, inspectors and
/// short glass cards. Apple's tool picker stays the only place for pens, eraser, lasso,
/// colors, undo and redo. Rules: docs/design/ui-style-guide.md.
struct AskAIEditorContainer: View {
    let session: EditorSession
    let assetsURL: URL?
    var onClose: () -> Void = {}
    var onCreate: (DocumentType) -> Void = { _ in }

    enum Inspector: String { case chat, settings }

    @State private var source: AskAIRegionSource
    @State private var chrome = EditorChromeState()
    @State private var ask: AskAIController
    @State private var chat: AgentChatController
    @State private var autoAsk = AutoAskSettings.load()
    @State private var canvasSettings = CanvasAISettings.load()
    @State private var providerSettings = AISettings.load()
    @State private var fullscreen = false
    @State private var pencilPans = false
    @State private var inspector: Inspector?
    @State private var rename = false
    @State private var title = ""
    @State private var export: ExportPNG?
    @State private var mcpTarget: MCPEditorTarget
    @State private var showsShare = false
    @State private var shareCenter = MCPShareCenter.shared
    @State private var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(session: EditorSession, assetsURL: URL?, onClose: @escaping () -> Void = {}, onCreate: @escaping (DocumentType) -> Void = { _ in }) {
        self.session = session; self.assetsURL = assetsURL; self.onClose = onClose; self.onCreate = onCreate
        let source = AskAIRegionSource()
        _source = State(initialValue: source)
        _chat = State(initialValue: AgentChatController(session: session, region: { source.controller?.visiblePageRegion ?? .zero }, selection: { source.selection }))
        _inspector = State(initialValue: session.manifest.chatPanelOpen == true ? .chat : nil)
        _ask = State(initialValue: AskAIController(document: session, region: { source.region }, selection: { source.selection }))
        _mcpTarget = State(initialValue: MCPEditorTarget(session: session, source: source))
    }

    var body: some View {
        editor
            .navigationTitle(session.manifest.title)
            .navigationSubtitle(subtitle)
            .toolbarTitleMenu { titleMenu }
            .toolbar(fullscreen ? .hidden : .visible, for: .navigationBar)
            .toolbar { bar }
            .inspector(isPresented: inspectorShown) {
                inspectorContent.inspectorColumnWidth(min: 320, ideal: 360, max: 400)
            }
            .sheet(item: $export) { item in PNGShareSheet(data: item.data) }
            .alert("Rename document", isPresented: $rename) {
                TextField("Document name", text: $title)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { if !session.rename(to: title) { error = "Enter a title of 1–200 characters." } }
            }
            .alert("Couldn't rename", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .background { shortcuts }
            .onChange(of: autoAsk) { _, value in value.save(); if !value.enabled { ask.toolBegan() } }
            .onChange(of: canvasSettings) { _, value in value.save() }
            .onChange(of: providerSettings) { _, value in value.save() }
            .onChange(of: inspector) { _, value in
                session.setChatPanelOpen(value == .chat)
                ask.suspendAutoAsk(value == .chat || chat.isPending)
                if value == .chat { ask.cancel() }
                // Settings may have changed in the inspector.
                autoAsk = AutoAskSettings.load(); canvasSettings = CanvasAISettings.load(); providerSettings = AISettings.load()
            }
            .task {
                ask.suspendAutoAsk(inspector == .chat)
#if DEBUG
                // End-to-end checks (ticket 023): `-MCPAutoShare YES` shares the opened document.
                if UserDefaults.standard.bool(forKey: "MCPAutoShare") { MCPShareCenter.shared.share(mcpTarget) }
#endif
            }
            .onDisappear { ask.cancel(); chat.cancel(); MCPShareCenter.shared.stopSharing(mcpTarget) }
    }

    // MARK: - Canvas and overlays

    private var editor: some View {
        DocumentEditorRepresentable(session: session, assetsURL: assetsURL) { [ask, chrome] editor in
            editor.chrome = chrome
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
        .overlay {
            if !session.isReadOnly {
                EditorSelectionBar(chrome: chrome, bottomClearance: source.pickerAtTop ? 0 : source.pickerClearance,
                                   canAsk: ask.canAsk && !chat.isPending,
                                   onEdit: { source.controller?.editSelectedText() },
                                   onAsk: { ask.ask() },
                                   onDelete: { source.controller?.deleteSelection() })
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                AskAIOverlay(controller: ask)
                if let notice = chrome.notice { noticeCard(notice) }
            }
            .padding(.top, 12)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: chrome.notice)
        }
        .overlay(alignment: .bottom) {
            if session.hasDrafts && inspector != .chat && !fullscreen {
                draftsBar.padding(.bottom, (source.pickerAtTop ? 0 : source.pickerClearance) + 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            if fullscreen {
                Button("Exit full screen", systemImage: "arrow.down.right.and.arrow.up.left") { setFullscreen(false) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .padding(16)
                    .accessibilityIdentifier("editor-exit-fullscreen")
            }
        }
        .onChange(of: ask.phase) { _, phase in
            chat.isOtherRequestPending = ask.isPending
            if !chat.isPending { updateThinking(phase) }
        }
        .onChange(of: chat.isPending) { _, pending in
            ask.suspendAutoAsk(pending || inspector == .chat)
            if pending { ask.cancel() }
            source.controller?.setThinkingRegion(canvasSettings.thinkingIndicator ? chat.pendingRegion : nil)
        }
        .onChange(of: canvasSettings.thinkingIndicator) { _, _ in
            if chat.isPending { source.controller?.setThinkingRegion(canvasSettings.thinkingIndicator ? chat.pendingRegion : nil) }
            else { updateThinking(ask.phase) }
        }
        .task(id: chrome.notice) {
            // Notices are short; they leave on their own.
            guard chrome.notice != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { chrome.notice = nil }
        }
    }

    private func noticeCard(_ text: String) -> some View {
        HStack(spacing: 12) {
            Label(text, systemImage: "info.circle")
                .font(.callout)
                .symbolRenderingMode(.hierarchical)
            Button("Dismiss", systemImage: "xmark") { chrome.notice = nil }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 520)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("editor-notice")
    }

    private var draftsBar: some View {
        let count = session.objects.filter { $0.isDraft == true }.count + session.draftInk.count
        return GlassEffectContainer {
            HStack(spacing: 12) {
                Label(count == 1 ? "1 draft on the page" : "\(count) drafts on the page", systemImage: "square.dashed")
                    .font(.callout.weight(.medium))
                    .padding(.leading, 8)
                Button("Discard all", role: .destructive) { session.discardAllDrafts() }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("drafts-discard")
                Button("Accept all") { session.acceptAllDrafts() }
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("drafts-accept")
            }
            .padding(6)
            .glassEffect(.regular, in: .capsule)
        }
        .disabled(session.isReadOnly)
    }

    // MARK: - Navigation bar

    private var subtitle: String {
        var parts = [saveText, aiStatus]
        if session.type == .notebook { parts.append("Page \(chrome.pageIndex + 1) of \(chrome.pageCount)") }
        return parts.joined(separator: " · ")
    }

    private var saveText: String {
        switch session.saveState {
        case .saved: "Saved"
        case .pending, .saving: "Saving…"
        case .failed: "Not saved"
        case .readOnly: "Read-only"
        }
    }

    private var aiStatus: String {
        if chat.isPending { return "Asking…" }
        switch ask.phase {
        case .idle: return ask.hasPlacedAnswer || session.hasDrafts ? "Answer placed" : (autoAsk.enabled ? "Auto answer on" : "Ready")
        case .pending: return "Asking…"
        case .review: return "Check answer"
        case .failed: return "Answer failed"
        }
    }

    @ViewBuilder private var titleMenu: some View {
        Button("Rename…", systemImage: "pencil") { title = session.manifest.title; rename = true }
            .disabled(session.isReadOnly)
            .accessibilityIdentifier("editor-rename")
        Button("Export page as PNG", systemImage: "square.and.arrow.up") {
            if let data = source.controller?.exportCurrentPage() { export = ExportPNG(data: data) }
        }
        Divider()
        Button("New canvas", systemImage: "square.and.pencil") { onCreate(.canvas) }
        Button("New notebook", systemImage: "book.closed") { onCreate(.notebook) }
    }

    @ToolbarContentBuilder private var bar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // Labeled with the destination; "Done" stays the identifier ticket 025's tests use.
            Button("Library", systemImage: "chevron.left", action: onClose)
                .keyboardShortcut("w", modifiers: .command)
                .accessibilityHint("Saves and returns to the library")
                .accessibilityIdentifier("Done")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Toggle(isOn: Binding(get: { chrome.selectMode }, set: { _ in source.controller?.toggleSelectMode() })) {
                Label("Select", systemImage: "lasso")
            }
            .toggleStyle(.button)
            .disabled(!chrome.isEditable && !chrome.selectMode)
            .accessibilityValue(chrome.selectMode ? "On" : "Off")
            .accessibilityHint("Select ink and objects to move, edit, ask about or delete them")
            .accessibilityIdentifier("editor-select")
            insertMenu
            viewMenu
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItemGroup(placement: .topBarTrailing) {
            if ask.isPending || chat.isPending {
                Button("Stop", systemImage: "stop.fill") { ask.cancel(); chat.cancel() }
                    .buttonStyle(.glassProminent)
                    .accessibilityHint("Stops the request; nothing is placed")
                    .accessibilityIdentifier("editor-stop")
            } else {
                Button("Ask AI", systemImage: "sparkles") { ask.ask() }
                    .buttonStyle(.glassProminent)
                    .disabled(!ask.canAsk || chat.isPending)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityHint(ask.blockedReason ?? "Answers your newest writing, your selection or the visible page")
                    .accessibilityIdentifier("editor-ask")
            }
            answerMenu
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Chat", systemImage: "bubble.left.and.bubble.right") { toggle(.chat) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .accessibilityValue(inspector == .chat ? "Open" : "Closed")
                .accessibilityIdentifier("editor-chat")
            claudeCodeButton
            Button("Settings", systemImage: "gearshape") { toggle(.settings) }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityValue(inspector == .settings ? "Open" : "Closed")
                .accessibilityIdentifier("editor-settings")
        }
    }

    private var insertMenu: some View {
        Menu {
            Button("Text", systemImage: "textformat") { source.controller?.addText(type: .text) }
            Button("Markdown", systemImage: "text.alignleft") { source.controller?.addText(type: .markdown) }
            Button("Formula", systemImage: "function") { source.controller?.addText(type: .latex) }
            Button("Graph", systemImage: "chart.xyaxis.line") { source.controller?.addText(type: .plot) }
            if session.type == .notebook {
                Divider()
                Button("Add page after this one", systemImage: "plus.rectangle.on.rectangle") { source.controller?.addPage() }
                Button("Delete page \(chrome.pageIndex + 1)", systemImage: "minus.rectangle", role: .destructive) { source.controller?.confirmDeletePage() }
                    .disabled(chrome.pageCount < 2)
            }
        } label: {
            Label("Insert", systemImage: "plus")
        }
        .disabled(!chrome.isEditable)
        .accessibilityIdentifier("editor-insert-menu")
    }

    private var viewMenu: some View {
        Menu {
            Picker("Page style", selection: Binding(get: { chrome.pageStyle }, set: { source.controller?.setPageStyle($0) })) {
                Label("Blank", systemImage: "square").tag(BackgroundStyle.blank)
                Label("Lined", systemImage: "line.3.horizontal").tag(BackgroundStyle.lined)
                Label("Dotted", systemImage: "circle.grid.3x3").tag(BackgroundStyle.dotted)
                Label("Grid", systemImage: "squareshape.split.3x3").tag(BackgroundStyle.grid)
            }
            .pickerStyle(.menu)
            .disabled(!chrome.isEditable)
            Toggle("Show page pattern", systemImage: "square.grid.3x3",
                   isOn: Binding(get: { session.manifest.gridVisible ?? true }, set: { session.setGridVisible($0) }))
            Toggle("Pan with Apple Pencil", systemImage: "hand.draw",
                   isOn: Binding(get: { pencilPans }, set: { source.controller?.setHandMode($0); pencilPans = source.controller?.handMode ?? $0 }))
            Divider()
            Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { setFullscreen(true) }
        } label: {
            Label("View", systemImage: "eye")
        }
        .accessibilityIdentifier("editor-view-menu")
    }

    private var answerMenu: some View {
        Menu {
            Toggle("Answer automatically when I pause", isOn: $autoAsk.enabled)
            Picker("Pause before answering", selection: $autoAsk.delaySeconds) {
                ForEach(delayChoices, id: \.self) { seconds in
                    Text(seconds.formatted(.number.precision(.fractionLength(0...1))) + " s").tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .disabled(!autoAsk.enabled)
            Divider()
            if ReasoningLevel.supports(preset: providerSettings.selectedPresetID, model: providerSettings.settings(for: providerSettings.selectedPresetID).model) {
                Picker("Reasoning", selection: reasoning) {
                    ForEach(ReasoningLevel.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.menu)
            }
            Picker("AI ink color", selection: $canvasSettings.appearance.ink) {
                ForEach(AIAnswerAppearance.Ink.allCases, id: \.self) { ink in
                    Text(ink.rawValue.capitalized).tag(ink)
                }
            }
            .pickerStyle(.menu)
        } label: {
            Label(autoAsk.enabled ? "Auto" : "On request", systemImage: autoAsk.enabled ? "timer" : "hand.tap")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityLabel("Answer mode")
        .accessibilityValue(autoAsk.enabled ? "Automatic after \(autoAsk.delaySeconds.formatted()) seconds" : "Only when you ask")
        .accessibilityIdentifier("editor-answer-menu")
    }

    private var delayChoices: [Double] {
        Array(Set([1, 2, 3, 5, 10, autoAsk.delaySeconds])).sorted()
    }

    private var reasoning: Binding<ReasoningLevel> {
        Binding(get: { providerSettings.settings(for: providerSettings.selectedPresetID).reasoning ?? .off },
                set: { level in
                    var current = providerSettings.settings(for: providerSettings.selectedPresetID)
                    current.reasoning = level
                    providerSettings.providers[providerSettings.selectedPresetID] = current
                })
    }

    private var claudeCodeButton: some View {
        let sharing = shareCenter.isSharing(mcpTarget)
        return Button { showsShare.toggle() } label: {
            if sharing {
                Label {
                    Text("Claude Code")
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(shareCenter.state == .connected ? .green : .orange)
                        .imageScale(.small)
                }
                .labelStyle(.titleAndIcon)
            } else {
                Label("Claude Code", systemImage: "laptopcomputer")
            }
        }
        .accessibilityLabel("Claude Code")
        .accessibilityValue(sharing ? shareCenter.statusText : "Not shared")
        .accessibilityHint("Shares this document with Claude Code on your paired Mac")
        .accessibilityIdentifier("editor-claude-code")
        .popover(isPresented: $showsShare) { MCPShareView(target: mcpTarget) }
    }

    /// Esc stops a request or leaves full screen; ⌘⇧F enters full screen.
    private var shortcuts: some View {
        Group {
            Button("Stop or exit") {
                if ask.isPending || chat.isPending { ask.cancel(); chat.cancel() } else if fullscreen { setFullscreen(false) }
            }
            .keyboardShortcut(.escape, modifiers: [])
            Button("Full screen") { setFullscreen(!fullscreen) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: - Inspectors

    private var inspectorShown: Binding<Bool> {
        Binding(get: { inspector != nil }, set: { if !$0 { inspector = nil } })
    }

    private func toggle(_ panel: Inspector) { inspector = inspector == panel ? nil : panel }

    @ViewBuilder private var inspectorContent: some View {
        switch inspector {
        case .chat: AgentChatView(controller: chat, onClose: { inspector = nil })
        case .settings, nil: AISettingsView(onDone: { inspector = nil })
        }
    }

    private func updateThinking(_ phase: AskAIController.Phase) {
        guard canvasSettings.thinkingIndicator, case .pending(let capture) = phase,
              let index = session.layout.pageIndex(of: capture.context.pageId) else { source.controller?.setThinkingRegion(nil); return }
        let origin = session.layout.pageRect(index).origin
        source.controller?.setThinkingRegion(AskAIController.rect(capture.context.scopeFrame).offsetBy(dx: origin.x, dy: origin.y))
    }

    private func setFullscreen(_ enabled: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { fullscreen = enabled }
        if enabled { inspector = nil }
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
