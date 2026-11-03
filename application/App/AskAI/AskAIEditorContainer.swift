import SwiftUI

extension EditorSession: AskAIDocument {
    var documentId: UUID { manifest.id }
}

/// Holds the editor controller so Ask AI can read its capture region.
@MainActor
final class AskAIRegionSource {
    weak var controller: DocumentEditorController?
    var region: CGRect { controller?.askAIRegion ?? .zero }
    var selection: CGRect? { controller?.askAISelection }
}

/// The editor with the Ask AI overlay at the bottom (ticket 010).
struct AskAIEditorContainer: View {
    let session: EditorSession
    let assetsURL: URL?
    @State private var source: AskAIRegionSource
    @State private var ask: AskAIController

    init(session: EditorSession, assetsURL: URL?) {
        self.session = session
        self.assetsURL = assetsURL
        let source = AskAIRegionSource()
        _source = State(initialValue: source)
        _ask = State(initialValue: AskAIController(document: session, region: { source.region },
                                                   selection: { source.selection }))
    }

    var body: some View {
        DocumentEditorRepresentable(session: session, assetsURL: assetsURL) { [ask] editor in
            source.controller = editor
            // Auto Ask (ticket 014): the pause after the last stroke asks about the newest ink.
            editor.onToolBegan = { [weak ask] in ask?.toolBegan() }
            editor.onToolEnded = { [weak ask] inked in ask?.toolEnded(inked: inked) }
        }
            // Top, below the editor's tool row: the system tool picker floats over the bottom.
            .overlay(alignment: .top) {
                if !session.isReadOnly { AskAIOverlay(controller: ask).padding(.top, 56) }
            }
            .onDisappear { ask.cancel() }
    }
}
