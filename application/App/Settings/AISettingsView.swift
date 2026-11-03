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

    init(defaults: UserDefaults = .standard, keys: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keys = keys
        settings = AISettings.load(defaults)
        refreshKeyState()
    }

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

/// AI provider settings (ticket 012): provider, endpoint, model, key and a connection test.
struct AISettingsView: View {
    @State private var model = AISettingsModel()
    @State private var autoAsk = AutoAskSettings.load()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: Binding(get: { model.presetID }, set: { model.select($0) })) {
                        ForEach(ProviderCatalog.all) { Text($0.displayName).tag($0.id) }
                    }
                } footer: {
                    Text("Ask AI uses only this provider. If a request fails, it is never sent to another one.")
                }

                Section("Endpoint") {
                    TextField(model.presetID == ProviderCatalog.customID ? "https://example.com/v1" : model.preset?.baseURL.absoluteString ?? "",
                              text: Binding(get: { model.current.baseURLOverride ?? "" }, set: { model.setBaseURL($0) }))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if model.effectiveBaseURL == nil {
                        Label("Enter an HTTPS base URL, such as https://example.com/v1.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else {
                        LabeledContent("Requests go to", value: model.effectiveBaseURL?.absoluteString ?? "")
                    }
                }

                Section {
                    TextField("Model ID", text: Binding(get: { model.model }, set: { model.setModel($0) }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle(isOn: Binding(get: { model.modelHasVision }, set: { model.setVision($0) })) {
                        Label("Reads images (vision)", systemImage: "eye")
                    }
                    if let preset = model.preset, !preset.defaultModels.isEmpty {
                        Menu("Suggested models") {
                            ForEach(preset.defaultModels) { suggestion in
                                Button { model.setModel(suggestion.id) } label: {
                                    Label(suggestion.id, systemImage: suggestion.capabilities.vision ? "eye" : "text.alignleft")
                                }
                            }
                        }
                    }
                    if model.preset?.authStyle == .bearer {
                        Button("Fetch models from provider") { model.fetchModels() }
                            .disabled(model.isBusy || model.effectiveBaseURL == nil)
                    } else {
                        Text("Uses the suggested model list. You can also enter a model ID and set its vision support.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(model.discovered.prefix(200)) { found in
                        Button { model.choose(found) } label: {
                            HStack {
                                Text(found.id).foregroundStyle(.primary)
                                Spacer()
                                if found.vision == true { Image(systemName: "eye").accessibilityLabel("Vision") }
                                if found.id == model.model { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                            }
                        }
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text(model.isKnownModel
                         ? "Vision support for this model comes from the provider's documentation."
                         : "Turn on vision only if the provider says this model accepts images. Handwriting is sent as an image.")
                }

                Section {
                    SecureField(ProviderCatalog.keyName(model.presetID), text: $model.keyInput)
                        .textContentType(.password)
                        .privacySensitive()
                    HStack {
                        Button("Save key") { model.saveKey() }
                            .disabled(model.keyInput.trimmingCharacters(in: .whitespaces).isEmpty || model.effectiveBaseURL == nil)
                        Spacer()
                        if model.hasKey {
                            Button("Remove key", role: .destructive) { model.removeKey() }
                        }
                    }
                    .buttonStyle(.borderless)
                    LabeledContent("Saved key", value: model.hasKey ? "On this iPad" : "None")
                } header: {
                    Text("Key")
                } footer: {
                    Text("The key stays in this iPad's Keychain and is used only for this provider and endpoint. Changing the endpoint needs the key again.")
                }

                Section {
                    Button {
                        model.testConnection()
                    } label: {
                        HStack {
                            Text("Test connection")
                            if model.isBusy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(model.isBusy || !model.hasKey)
                    if let status = model.status {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Sends one short text message to the selected model.")
                }

                Section {
                    Toggle("Ask when I pause writing", isOn: $autoAsk.enabled)
                    Stepper(value: $autoAsk.delaySeconds, in: AutoAskSettings.delayRange, step: 0.5) {
                        LabeledContent("Pause", value: "\(autoAsk.delaySeconds.formatted(.number.precision(.fractionLength(0...1)))) s")
                    }
                    .disabled(!autoAsk.enabled)
                } header: {
                    Text("Auto Ask")
                } footer: {
                    Text("After you stop writing for this long, Pencil Echo asks about the ink you just wrote and writes the answer beside it. The Ask AI button still works.")
                }
                .onChange(of: autoAsk) { _, settings in settings.save() }

                Section("What is sent") {
                    Text("When Ask AI runs, Pencil Echo sends an image of your selection (or the ink you just wrote, or the visible area) and your instruction to \(model.preset?.displayName ?? "the provider") at \(model.effectiveBaseURL?.host() ?? "the endpoint above"). Nothing else from your documents is sent. The provider's own terms apply to what you send.")
                        .font(.callout)
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onDisappear { model.cancel() }
        }
    }
}
