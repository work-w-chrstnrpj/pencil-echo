import SwiftUI

/// Ask AI cards for the editor (tickets 010, 024): the stale-answer review and the
/// failure with manual Retry. Asking and pending live in the navigation bar (Ask AI /
/// Stop and the subtitle), so idle and pending show nothing here.
struct AskAIOverlay: View {
    @Bindable var controller: AskAIController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch controller.phase {
            case .idle, .pending:
                EmptyView()
            case .review:
                card(title: "Your page changed while the AI was answering",
                     detail: "Place the answer anyway, or discard it and ask again.",
                     symbol: "exclamationmark.bubble") {
                    Button("Discard", role: .destructive) { controller.dismiss() }
                        .buttonStyle(.glass)
                    Button("Place answer") { controller.placeAnyway() }
                        .buttonStyle(.glassProminent)
                }
                .accessibilityIdentifier("ask-review")
            case .failed(_, let message):
                card(title: "Couldn't answer", detail: message, symbol: "exclamationmark.triangle") {
                    Button("Dismiss") { controller.dismiss() }
                        .buttonStyle(.glass)
                    Button("Try again") { controller.retry() }
                        .buttonStyle(.glassProminent)
                }
                .accessibilityIdentifier("ask-failed")
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: controller.phase)
    }

    private func card(title: String, detail: String, symbol: String,
                      @ViewBuilder actions: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout)
                }
            } icon: {
                Image(systemName: symbol).symbolRenderingMode(.hierarchical).foregroundStyle(.orange)
            }
            GlassEffectContainer {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    actions()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
    }
}
