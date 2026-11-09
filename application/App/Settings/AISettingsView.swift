import Observation
import SwiftUI

/// State for the AI settings screen (ticket 012). Every edit saves immediately;
/// keys go straight to Keychain and are never read back into the UI.
@MainActor
@Observable
final class AISettingsModel {
    private(set) var settings: AISettings
    var keyInput = ""
    private(set) var hasKey = false
    private(set) var discovered: [DiscoveredModel] = []
    private(set) var status: String?
    private(set) var isBusy = false
    private var task: Task<Void, Never>?

    private let defaults: UserDefaults
    private let keys: KeychainStore
    private let freeQuota: QwenFreeQuotaLedger
    private(set) var freeQuotaState: QwenFreeQuotaState

    init(defaults: UserDefaults = .standard, keys: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keys = keys
        freeQuota = QwenFreeQuotaLedger(defaults: defaults)
        freeQuotaState = freeQuota.state
        settings = AISettings.load(defaults)
        refreshKeyState()
    }

    // MARK: Free quota (Qwen · Singapore)

    var offersFreeQuota: Bool { presetID == QwenPresets.freeQuotaPresetID }
    var freeQuotaRemainingModels: Int {
        QwenPresets.freeQuotaVisionModels.filter { freeQuotaState.exhausted[$0] == nil }.count
    }

    func setFreeQuotaFallback(_ on: Bool) {
        freeQuota.update { $0.enabled = on }
        freeQuotaState = freeQuota.state
    }

    func resetFreeQuotaList() {
        freeQuota.update { $0.exhausted = [:] }
        freeQuotaState = freeQuota.state
    }

    func refreshFreeQuota() { freeQuotaState = freeQuota.state }

    var presetID: String { settings.selectedPresetID }
    var preset: ProviderPreset? { ProviderCatalog.preset(presetID) }
    var current: ProviderSettings { settings.settings(for: presetID) }
    var effectiveBaseURL: URL? { settings.baseURL(for: presetID) }
    var model: String { current.model }
    var modelHasVision: Bool { settings.capabilities(for: presetID, model: model).vision }
    var isKnownModel: Bool { preset?.defaultModels.contains { $0.id == model } == true }

    // MARK: Edits

    func select(_ id: String) {
        guard id != presetID, ProviderCatalog.preset(id) != nil else { return }
        cancel()
        settings.selectedPresetID = id
        discovered = []
        status = nil
        keyInput = ""
        persist()
    }

    func setBaseURL(_ text: String) {
        update { $0.baseURLOverride = text.isEmpty ? nil : text }
        discovered = []
    }

    func setModel(_ id: String) { update { $0.model = id } }

    func setVision(_ on: Bool) { update { $0.visionOverrides[$0.model] = on } }

    func choose(_ discovered: DiscoveredModel) {
        update {
            $0.model = discovered.id
            if let vision = discovered.vision { $0.visionOverrides[discovered.id] = vision }
        }
    }

    private func update(_ change: (inout ProviderSettings) -> Void) {
        var value = current
        change(&value)
        settings.providers[presetID] = value
        persist()
    }

    private func persist() {
        settings.save(defaults)
        refreshKeyState()
    }

    // MARK: Keys

    func saveKey() {
        guard let identity = settings.identity(for: presetID) else {
            status = "Set a valid HTTPS endpoint before saving a key."
            return
        }
        do {
            try keys.save(keyInput, for: identity)
            status = "Key saved on this iPad for \(identity.baseURL.host() ?? "this endpoint")."
        } catch {
            status = AIError.normalized(error).localizedDescription
        }
        keyInput = ""
        refreshKeyState()
    }

    func removeKey() {
        guard let identity = settings.identity(for: presetID) else { return }
        do {
            try keys.delete(for: identity)
            status = "Key removed."
        } catch {
            status = AIError.normalized(error).localizedDescription
        }
        refreshKeyState()
    }

    private func refreshKeyState() {
        hasKey = settings.identity(for: settings.selectedPresetID).flatMap { try? keys.read(for: $0) } != nil
    }

    // MARK: Network actions

    func fetchModels() {
        guard let preset = try? settings.resolvedPreset(for: presetID) else {
            status = "Set a valid HTTPS endpoint first."
            return
        }
        run { [keys] in
            let models = try await ModelDiscovery.fetch(preset, credentials: keys)
            return (models, models.isEmpty ? "The provider listed no models. Enter a model ID instead." : "Found \(models.count) models.")
        }
    }

    func testConnection() {
        guard let preset = try? settings.resolvedPreset(for: presetID), !model.isEmpty else {
            status = "Set an endpoint and a model first."
            return
        }
        let model = model
        let discovered = discovered
        run { [keys] in
            if let error = await ConnectionTest.run(ProviderFactory.make(preset, credentials: keys), model: model) {
                throw error
            }
            return (discovered, "Connected. \(model) replied.")
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isBusy = false
    }

    private func run(_ work: @escaping @Sendable () async throws -> ([DiscoveredModel], String)) {
        cancel()
        isBusy = true
        status = nil
        let presetAtStart = presetID
        task = Task {
            let result: Result<([DiscoveredModel], String), AIError>
            do { result = .success(try await work()) } catch { result = .failure(AIError.normalized(error)) }
            guard !Task.isCancelled, presetAtStart == presetID else { return }
            isBusy = false
            switch result {
            case .success(let (models, message)):
                discovered = models
                status = message
            case .failure(let error):
                status = error.localizedDescription
            }
        }
    }
}

/// AI settings (tickets 012, 026): provider, endpoint, saved connections, answers,
/// appearance, privacy and about. Layout follows docs/design/ui-style-guide.md; every
/// control keeps its stored setting and behavior from before.
struct AISettingsView: View {
    private static var notices: String {
        guard let root = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: nil),
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return "See the bundled third-party notices for SwiftMath and its dependencies." }
        return files.compactMap { ($0 as? URL).flatMap { try? String(contentsOf: $0, encoding: .utf8) } }.joined(separator: "\n\n")
    }

    var onDone: (() -> Void)? = nil
    @State private var canvasSettings = CanvasAISettings.load()
    @State private var model = AISettingsModel()
    @State private var autoAsk = AutoAskSettings.load()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                if model.offersFreeQuota { freeQuotaSection }
                keySection
                endpointSection
                savedConnectionsSection
                answersSection
                appearanceSection
                privacySection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { if let onDone { onDone() } else { dismiss() } } }
            }
            .onChange(of: canvasSettings) { _, value in value.save() }
            .onChange(of: autoAsk) { _, settings in settings.save() }
            .onDisappear { model.cancel() }
        }
    }

    // MARK: - AI provider

    private var providerSection: some View {
        Section {
            Picker("Provider", selection: Binding(get: { model.presetID }, set: { model.select($0) })) {
                ForEach(ProviderCatalog.all) { Text($0.displayName).tag($0.id) }
            }
            TextField("Model ID", text: Binding(get: { model.model }, set: { model.setModel($0) }))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let preset = model.preset, !preset.defaultModels.isEmpty {
                Menu {
                    ForEach(preset.defaultModels) { suggestion in
                        Button { model.setModel(suggestion.id) } label: {
                            Label(suggestion.id, systemImage: suggestion.capabilities.vision ? "eye" : "text.alignleft")
                        }
                    }
                } label: {
                    Label("Suggested models", systemImage: "list.bullet")
                }
            }
            if model.preset?.authStyle == .bearer {
                Button {
                    model.fetchModels()
                } label: {
                    Label("Fetch models from provider", systemImage: "arrow.down.circle")
                }
                .disabled(model.isBusy || model.effectiveBaseURL == nil)
            }
            ForEach(model.discovered.prefix(200)) { found in
                Button { model.choose(found) } label: {
                    HStack {
                        Text(found.id).foregroundStyle(.primary)
                        Spacer()
                        if found.vision == true { Image(systemName: "eye").accessibilityLabel("Vision") }
                        if found.id == model.model { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Selected") }
                    }
                }
            }
            Toggle(isOn: Binding(get: { model.modelHasVision }, set: { model.setVision($0) })) {
                Label("Reads images", systemImage: "eye")
            }
        } header: {
            Text("AI provider")
        } footer: {
            Text(model.isKnownModel
                 ? "Ask AI uses only this provider and never retries with another. Image support for this model comes from the provider's documentation."
                 : "Ask AI uses only this provider and never retries with another. Turn on Reads images only if the provider says this model accepts images: handwriting is sent as an image.")
        }
    }

    private var freeQuotaSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.freeQuotaState.enabled }, set: { model.setFreeQuotaFallback($0) })) {
                Label("Use free quota across vision models", systemImage: "gift")
            }
            LabeledContent("Models with quota left",
                           value: "\(model.freeQuotaRemainingModels) of \(QwenPresets.freeQuotaVisionModels.count)")
            if !model.freeQuotaState.exhausted.isEmpty {
                Button("Reset used-up list") { model.resetFreeQuotaList() }
            }
        } header: {
            Text("Free quota")
        } footer: {
            Text("Turn on Free Quota Only for all models in the Model Studio console first (Free Quota, Batch Enable). When Alibaba says a model's free quota is used up, Ask AI marks it and sends the same request to the next vision model on this key. Without Free Quota Only, Alibaba bills instead and the next model is never tried.")
        }
        .onAppear { model.refreshFreeQuota() }
    }

    private var keySection: some View {
        Section {
            SecureField(ProviderCatalog.keyName(model.presetID), text: $model.keyInput)
                .textContentType(.password)
                .privacySensitive()
            LabeledContent("Saved key", value: model.hasKey ? "On this iPad" : "None")
            HStack {
                Button("Save key") { model.saveKey() }
                    .disabled(model.keyInput.trimmingCharacters(in: .whitespaces).isEmpty || model.effectiveBaseURL == nil)
                Spacer()
                if model.hasKey {
                    Button("Remove key", role: .destructive) { model.removeKey() }
                }
            }
            .buttonStyle(.borderless)
            Button {
                model.testConnection()
            } label: {
                HStack {
                    Label("Test connection", systemImage: "bolt.horizontal")
                    if model.isBusy { Spacer(); ProgressView() }
                }
            }
            .disabled(model.isBusy || !model.hasKey)
            if let status = model.status { statusLabel(status) }
        } header: {
            Text("API key")
        } footer: {
            Text("Keys stay in this iPad's Keychain, for this provider and endpoint only. Test connection sends one short text message to the model.")
        }
    }

    /// The model's status line as symbol + text: connected, information, or a problem.
    private func statusLabel(_ status: String) -> some View {
        let lower = status.lowercased()
        let symbol: String, color: Color
        if lower.hasPrefix("connected") {
            (symbol, color) = ("checkmark.circle.fill", .green)
        } else if lower.hasPrefix("key saved") || lower.hasPrefix("key removed") || lower.hasPrefix("found") {
            (symbol, color) = ("info.circle.fill", .secondary)
        } else {
            (symbol, color) = ("exclamationmark.triangle.fill", .orange)
        }
        return Label {
            Text(status).foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color).symbolRenderingMode(.hierarchical)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private var endpointSection: some View {
        Section {
            TextField(model.presetID == ProviderCatalog.customID ? "https://example.com/v1" : model.preset?.baseURL.absoluteString ?? "",
                      text: Binding(get: { model.current.baseURLOverride ?? "" }, set: { model.setBaseURL($0) }))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if model.effectiveBaseURL == nil {
                Label {
                    Text("Enter an HTTPS base URL, such as https://example.com/v1.").foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            } else {
                LabeledContent("Requests go to", value: model.effectiveBaseURL?.absoluteString ?? "")
            }
        } header: {
            Text("Endpoint")
        } footer: {
            Text("Leave empty to use the provider's standard address. A new endpoint needs its key saved again.")
        }
    }

    private var savedConnectionsSection: some View {
        Section("Saved connections") {
            ForEach(ProviderCatalog.all.filter { model.settings.providers[$0.id] != nil || $0.id == model.presetID }) { preset in
                Button { model.select(preset.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.displayName).foregroundStyle(.primary)
                            let saved = model.settings.settings(for: preset.id).model
                            Text(saved.isEmpty ? "No model" : saved).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if preset.id == model.presetID {
                            Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityValue(preset.id == model.presetID ? "Selected" : "")
                .accessibilityHint("Switch to this saved provider and model")
            }
        }
    }

    // MARK: - Answers, appearance, privacy, about

    private var answersSection: some View {
        Section {
            Toggle("Answer automatically when I pause", isOn: $autoAsk.enabled)
            Stepper(value: $autoAsk.delaySeconds, in: AutoAskSettings.delayRange, step: 0.5) {
                LabeledContent("Pause before answering", value: "\(autoAsk.delaySeconds.formatted(.number.precision(.fractionLength(0...1)))) s")
            }
            .disabled(!autoAsk.enabled)
        } header: {
            Text("Answers")
        } footer: {
            Text("Pencil Echo asks the AI after you stop writing for this long, and writes the answer beside your ink. Ask AI still works any time.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("AI font", selection: $canvasSettings.appearance.font) {
                ForEach(AIAnswerAppearance.Font.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Toggle("Thinking indicator", isOn: $canvasSettings.thinkingIndicator)
        }
    }

    private var privacySection: some View {
        Section {
            Label("Only the part of the page you ask about is sent", systemImage: "lock")
        } header: {
            Text("Privacy")
        } footer: {
            Text("When Ask AI runs, Pencil Echo sends an image of your selection (or the ink you just wrote, or the visible area) and your instruction to \(model.preset?.displayName ?? "the provider") at \(model.effectiveBaseURL?.host() ?? "the endpoint above"). Chat sends your selection or visible page plus up to 10 recent text turns. Earlier images are never resent. The provider's own terms apply to what you send.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            NavigationLink("Third-party notices") {
                ScrollView { Text(Self.notices).font(.footnote).padding() }.navigationTitle("Third-party notices")
            }
        }
    }
}
