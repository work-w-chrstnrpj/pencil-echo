import SwiftUI

/// Agent chat panel (tickets 021, 026): message bubbles, a pinned input bar with the
/// context chip and Send, a drafts bar and inline errors. Layout only; every action
/// goes to `AgentChatController` as before. Rules: docs/design/ui-style-guide.md.
struct AgentChatView: View {
    @Bindable var controller: AgentChatController
    let onClose: () -> Void

    private var messages: [ConversationMessage] { controller.session.chatHistory.messages }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubble(text: message.text, fromUser: message.role == .user)
                        }
                        if controller.isPending { pendingBubbles }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .padding(16)
                }
                .overlay {
                    if messages.isEmpty && !controller.isPending {
                        ContentUnavailableView("Ask about your page", systemImage: "bubble.left.and.text.bubble.right",
                                               description: Text("Answers appear here and as editable drafts on the page."))
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: controller.streamingReply) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                .onChange(of: messages.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                .onChange(of: controller.isPending) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle("Agent chat").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New chat") { controller.newChat() }
                        .disabled(controller.session.isReadOnly)
                        .accessibilityHint("Clears text history; keeps existing drafts and canvas work")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onClose).accessibilityHint("Closes the panel and keeps this conversation")
                }
            }
        }
    }

    // MARK: - Pending

    @ViewBuilder private var pendingBubbles: some View {
        ChatBubble(text: controller.pendingInstruction, fromUser: true)
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Working…").foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("Cancel") { controller.cancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if !controller.streamingReply.isEmpty {
                    Text(controller.streamingReply).textSelection(.enabled)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Assistant is working")
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = controller.error {
                Label {
                    Text(error).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("chat-error")
            }
            if controller.session.hasDrafts { draftsBar }
            HStack(alignment: .bottom, spacing: 8) {
                scopeChip
                TextField("Ask about this page", text: $controller.input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("chat-input")
                    .accessibilityHint("Type or use the keyboard microphone to dictate a request")
                Button("Send", systemImage: "arrow.up") { controller.send() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .disabled(!controller.canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityHint("Sends this image and recent chat to the selected AI provider")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }

    private var scopeChip: some View {
        Menu {
            Picker("Context", selection: $controller.scope) {
                Label("Selection", systemImage: "lasso").tag(AgentChatController.Scope.selection)
                Label("Visible page", systemImage: "viewfinder").tag(AgentChatController.Scope.visiblePage)
            }
        } label: {
            Label(controller.effectiveScope.rawValue, systemImage: controller.effectiveScope == .selection ? "lasso" : "viewfinder")
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("Chat context")
        .accessibilityValue(controller.effectiveScope.rawValue)
        .accessibilityHint("Chooses between the current selection and the visible page")
    }

    private var draftsBar: some View {
        let count = controller.session.objects.filter { $0.isDraft == true }.count + controller.session.draftInk.count
        return HStack(spacing: 8) {
            Label(count == 1 ? "1 draft on the page" : "\(count) drafts on the page", systemImage: "square.dashed")
                .font(.callout)
            Spacer(minLength: 8)
            Button("Discard all", role: .destructive) { controller.session.discardAllDrafts() }
                .buttonStyle(.bordered)
                .accessibilityHint("Removes all drafts; can be undone")
            Button("Accept all") { controller.session.acceptAllDrafts() }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Keeps all drafts as normal editable content; can be undone")
        }
        .controlSize(.small)
        .disabled(controller.session.isReadOnly)
    }
}

/// One message: the user's on the trailing side in the tint color, the assistant's leading.
private struct ChatBubble: View {
    let text: String
    let fromUser: Bool

    var body: some View {
        HStack {
            // The minimum spacer keeps a bubble to about 85 % of the panel width.
            if fromUser { Spacer(minLength: 48) }
            Text(text)
                .textSelection(.enabled)
                .foregroundStyle(fromUser ? Color.white : Color.primary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(fromUser ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            if !fromUser { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((fromUser ? "You: " : "Assistant: ") + text)
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
