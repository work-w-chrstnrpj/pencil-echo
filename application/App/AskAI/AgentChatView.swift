import SwiftUI

struct AgentChatView: View {
    @Bindable var controller: AgentChatController
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if controller.session.chatHistory.messages.isEmpty && !controller.isPending {
                                Text("Ask about your drawing. Answers appear here and as editable drafts beside your work.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(controller.session.chatHistory.messages) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.role == .user ? "You" : "Assistant").font(.caption.bold())
                                    Text(message.text).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if controller.isPending {
                                Text(controller.pendingInstruction).font(.callout)
                                HStack { ProgressView(); Text("Working…"); Spacer(); Button("Cancel") { controller.cancel() } }
                                if !controller.streamingReply.isEmpty { Text(controller.streamingReply).textSelection(.enabled) }
                            }
                            Color.clear.frame(height: 1).id("latest")
                        }.padding()
                    }
                    .onChange(of: controller.streamingReply) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                    .onChange(of: controller.session.chatHistory.messages.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                }
                if let error = controller.error { Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal).accessibilityIdentifier("chat-error") }
                if controller.session.hasDrafts { draftActions }
                VStack(alignment: .leading, spacing: 8) {
                    Button(controller.effectiveScope.rawValue, systemImage: controller.effectiveScope == .selection ? "lasso" : "viewfinder") {
                        controller.scope = controller.scope == .selection ? .visiblePage : .selection
                    }.accessibilityLabel("Chat context").accessibilityValue(controller.effectiveScope.rawValue)
                        .accessibilityHint("Switches between the current selection and visible page")
                        .frame(minHeight: 44)
                    HStack(alignment: .bottom) {
                        TextField("Ask about this page", text: $controller.input, axis: .vertical)
                            .lineLimit(1...5).textFieldStyle(.roundedBorder).accessibilityIdentifier("chat-input")
                            .accessibilityHint("Type or use the keyboard microphone to dictate a request")
                        Button("Send", systemImage: "arrow.up.circle.fill") { controller.send() }
                            .labelStyle(.iconOnly).font(.title2).frame(width: 44, height: 44)
                            .accessibilityHint("Sends this image and recent chat to the selected AI provider")
                            .disabled(!controller.canSend).keyboardShortcut(.return, modifiers: .command)
                    }
                }.padding(.horizontal).padding(.bottom)
            }
            .navigationTitle("Agent chat").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("New chat") { controller.newChat() }.disabled(controller.session.isReadOnly).accessibilityHint("Clears text history; keeps existing drafts and canvas work") }
                ToolbarItem(placement: .topBarTrailing) { Button("Close", action: onClose).accessibilityHint("Closes the panel and keeps this conversation") }
            }
        }
    }

    private var draftActions: some View {
        HStack {
            Button("Accept all") { controller.session.acceptAllDrafts() }.buttonStyle(.borderedProminent)
                .accessibilityHint("Keeps all drafts as normal editable content; can be undone")
            Button("Discard all", role: .destructive) { controller.session.discardAllDrafts() }.buttonStyle(.bordered)
                .accessibilityHint("Removes all drafts; can be undone")
        }.frame(minHeight: 44).disabled(controller.session.isReadOnly)
    }
}

#if DEBUG
/// Local-only UI fixture. Only enabled with a valid isolated test library argument.
struct AgentChatFixtureProvider: AIProvider {
    func capabilities(model: String) -> ModelCapabilities? { ProviderCatalog.unverifiedCapabilities(vision: true) }
    func send(_ request: AIRequest) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let reply = #"{"version":2,"message":"The time follows from conservation of energy. These editable steps are drafts.","operations":[{"op":"add_object","type":"markdown","source":"**Energy:** $mgh = mv^2/2$. Solve along each path using its height.","placement":"right_of_scope","frame":null}]}"#
                for chunk in stride(from: 0, to: reply.count, by: 24) {
                    do { try await Task.sleep(for: .milliseconds(40)); try Task.checkCancellation() }
                    catch { continuation.finish(throwing: AIError.cancelled); return }
                    let start = reply.index(reply.startIndex, offsetBy: chunk)
                    let end = reply.index(start, offsetBy: min(24, reply.count - chunk))
                    continuation.yield(.textDelta(String(reply[start..<end])))
                }
                continuation.yield(.completed(reply)); continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-chatFixture"), let i = args.firstIndex(of: "-libraryTestRoot"), args.indices.contains(i + 1) else { return false }
        return UUID(uuidString: args[i + 1]) != nil
    }
}
#endif
