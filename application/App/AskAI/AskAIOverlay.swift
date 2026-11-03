import SwiftUI

/// Ask AI controls for the editor (ticket 010): instruction + Ask, a non-blocking
/// pending indicator with Cancel, the stale-answer review card and the error banner
/// with manual Retry. Drawing stays responsive; nothing here blocks the canvas.
struct AskAIOverlay: View {
    @Bindable var controller: AskAIController

    var body: some View {
        VStack(spacing: 12) {
            switch controller.phase {
            case .idle:
                askBar
            case .pending:
                card {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Asking AI…")
                        Spacer(minLength: 16)
                        Button("Cancel", role: .cancel) { controller.cancel() }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Asking AI. Drawing still works.")
            case .review:
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your problem changed. Place answer anyway?", systemImage: "exclamationmark.bubble")
                            .font(.headline)
                        HStack {
                            Button("Discard", role: .destructive) { controller.dismiss() }
                            Spacer()
                            Button("Place") { controller.placeAnyway() }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            case .failed(_, let message):
                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(message, systemImage: "exclamationmark.triangle")
                        HStack {
                            Button("Dismiss") { controller.dismiss() }
                            Spacer()
                            Button("Retry") { controller.retry() }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 520)
        .padding()
        .animation(.default, value: controller.phase)
    }

    private var askBar: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    TextField("Instruction", text: $controller.instruction)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.send)
                        .onSubmit { controller.ask() }
                    Button("Ask AI", systemImage: "sparkles") { controller.ask() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.canAsk)
                }
                if let reason = controller.blockedReason {
                    Label(reason, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityHint("Sends the selected work, the ink you just wrote, or the visible area to the AI provider. With Auto Ask on, pausing your writing sends it too.")
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 4, y: 2)
    }
}
