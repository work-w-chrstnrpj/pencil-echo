import SwiftUI
import UIKit

/// Popover from the AI toolbar: share this document with Claude Code and pair the Mac (ticket 023).
struct MCPShareView: View {
    let target: MCPShareTarget
    @State private var center = MCPShareCenter.shared
    @State private var confirmReset = false
    @State private var copied: String?
    /// `nil` follows the connection: open while setting up, collapsed once connected.
    @State private var setupOverride: Bool?

    private var sharing: Binding<Bool> {
        Binding(get: { center.isSharing(target) }, set: { $0 ? center.share(target) : center.stopSharing(target) })
    }

    private var setupExpanded: Binding<Bool> {
        Binding(get: { setupOverride ?? (center.state != .connected) }, set: { setupOverride = $0 })
    }

    var body: some View {
        let code = center.pairing?.code ?? ""
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    statusRow
                    if center.isSharing(target), let activity = center.lastActivity {
                        Text(activity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("share-activity")
                    }
                }
                Toggle("Share this document", isOn: sharing)
                    .accessibilityHint("Lets Claude Code on your paired Mac see this document and add drafts while Pencil Echo is open")
                    .accessibilityIdentifier("share-toggle")
            } footer: {
                Text("Sharing stops when Pencil Echo goes to the background or the iPad locks.")
            }

            Section {
                DisclosureGroup(isExpanded: setupExpanded) {
                    VStack(alignment: .leading, spacing: 16) {
                        step(1, "Pair this iPad", command: "pencilecho-mcp pair \(code)", copyLabel: "Copy pair command", id: "pair")
                        step(2, "Add to Claude Code", command: "claude mcp add pencil-echo --scope user -- pencilecho-mcp serve", copyLabel: "Copy add-to-Claude-Code command", id: "add")
                        step(3, "Ask Claude Code about your page", command: nil, copyLabel: nil, id: "ask")
                        if !code.isEmpty, let qr = MCPShareCenter.qrImage(for: code) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 140, height: 140)
                                .padding(.leading, 36)
                                .accessibilityLabel("Pairing code as a QR code")
                                .accessibilityIdentifier("share-qr")
                        }
                        Text("The code is a secret: anyone with it can see shared documents on your network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Set up your Mac", systemImage: "laptopcomputer")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("share-setup")
            }

            Section {
                Button("Reset pairing…", role: .destructive) { confirmReset = true }
                    .accessibilityIdentifier("share-reset")
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 420)
        // Fits the content (about 520 pt with setup open); scrolls only beyond 560.
        .frame(minHeight: 280, idealHeight: 520, maxHeight: 560)
        .onAppear { _ = center.ensurePairing() }
        .confirmationDialog("Reset pairing?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { center.resetPairing(); copied = nil }
        } message: {
            Text("Your Mac stops connecting until you pair it again with the new code.")
        }
    }

    // MARK: Status

    private struct Status {
        let text: String
        let symbol: String
        let tint: AnyShapeStyle
        let isSecondaryText: Bool
    }

    private var status: Status {
        switch center.state {
        case .off:
            Status(text: "Not shared", symbol: "laptopcomputer", tint: AnyShapeStyle(.secondary), isSecondaryText: true)
        case .starting, .waiting:
            Status(text: "Waiting for your Mac", symbol: "antenna.radiowaves.left.and.right", tint: AnyShapeStyle(.orange), isSecondaryText: false)
        case .connected:
            Status(text: "Connected", symbol: "checkmark.circle.fill", tint: AnyShapeStyle(.green), isSecondaryText: false)
        case .paused:
            Status(text: "Paused while Pencil Echo is in the background", symbol: "pause.circle", tint: AnyShapeStyle(.secondary), isSecondaryText: true)
        case .failed:
            Status(text: center.statusText, symbol: "exclamationmark.triangle.fill", tint: AnyShapeStyle(.red), isSecondaryText: false)
        }
    }

    private var statusRow: some View {
        let status = status
        return Label {
            Text(status.text)
                .foregroundStyle(status.isSecondaryText ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
        }
        .symbolRenderingMode(.hierarchical)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("share-status")
    }

    // MARK: Steps

    @ViewBuilder
    private func step(_ number: Int, _ title: String, command: String?, copyLabel: String?, id: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.tint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("share-step-\(id)")
                if let command {
                    HStack(alignment: .center, spacing: 8) {
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let copyLabel {
                            copyButton(command, label: copyLabel, id: id)
                        }
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private func copyButton(_ command: String, label: String, id: String) -> some View {
        let isCopied = copied == id
        return Button {
            copy(command, id: id)
        } label: {
            Label {
                Text(isCopied ? "Copied" : "Copy")
            } icon: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .symbolEffect(.bounce, value: isCopied)
            }
            .font(.caption.weight(.medium))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(isCopied ? "Copied" : label)
        .accessibilityIdentifier("share-copy-\(id)")
    }

    @MainActor
    private func copy(_ command: String, id: String) {
        UIPasteboard.general.string = command
        copied = id
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard copied == id else { return }
            copied = nil
        }
    }
}

/// Small banner while Claude Code is connected or working.
struct MCPShareBanner: View {
    @State private var center = MCPShareCenter.shared

    var body: some View {
        if center.isSharing, center.state == .connected || center.lastActivity != nil {
            HStack(spacing: 6) {
                Circle()
                    .fill(center.state == .connected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Label(center.lastActivity ?? center.statusText, systemImage: "laptopcomputer")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Claude Code: \(center.lastActivity ?? center.statusText)")
            .accessibilityIdentifier("share-banner")
        }
    }
}
