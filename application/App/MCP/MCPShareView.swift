import SwiftUI
import UIKit

/// Popover from the AI toolbar: share this document with Claude Code and pair the Mac (ticket 023).
struct MCPShareView: View {
    let target: MCPShareTarget
    @State private var center = MCPShareCenter.shared
    @State private var confirmReset = false
    @State private var copied = false

    private var sharing: Binding<Bool> {
        Binding(get: { center.isSharing(target) }, set: { $0 ? center.share(target) : center.stopSharing(target) })
    }

    var body: some View {
        let code = center.pairing?.code ?? ""
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Share this document with Claude Code", isOn: sharing)
                    .accessibilityHint("Lets Claude Code on your paired Mac see this document and add drafts while Pencil Echo is open")
                if center.isSharing(target) {
                    Label(center.statusText, systemImage: center.state == .connected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                        .foregroundStyle(center.state == .connected ? .green : .secondary)
                    if let activity = center.lastActivity { Text(activity).font(.caption).foregroundStyle(.secondary) }
                }
                Divider()
                Text("Pair your Mac").font(.headline)
                Text("Run these on your Mac once. The code is a secret: anyone with it can see shared documents on your network.")
                    .font(.callout).foregroundStyle(.secondary)
                step("1. Pair", "pencilecho-mcp pair \(code)")
                step("2. Add to Claude Code", "claude mcp add pencil-echo --scope user -- pencilecho-mcp serve")
                Text("3. Turn on sharing here, then ask Claude Code about your Pencil Echo page.")
                    .font(.callout)
                HStack(alignment: .top, spacing: 16) {
                    if !code.isEmpty, let qr = MCPShareCenter.qrImage(for: code) {
                        Image(uiImage: qr).interpolation(.none).resizable().frame(width: 140, height: 140)
                            .accessibilityLabel("Pairing code as a QR code")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Button(copied ? "Copied" : "Copy pair command", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = "pencilecho-mcp pair \(code)"
                            copied = true
                        }
                        Button("Reset pairing", systemImage: "arrow.counterclockwise", role: .destructive) { confirmReset = true }
                        Text("Sharing stops when Pencil Echo goes to the background or the iPad locks.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 380, idealWidth: 460, minHeight: 420)
        .onAppear { _ = center.ensurePairing() }
        .confirmationDialog("Reset pairing?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { center.resetPairing(); copied = false }
        } message: {
            Text("Your Mac stops connecting until you pair it again with the new code.")
        }
    }

    private func step(_ title: String, _ command: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Small banner while Claude Code is connected or working.
struct MCPShareBanner: View {
    @State private var center = MCPShareCenter.shared

    var body: some View {
        if center.isSharing, center.state == .connected || center.lastActivity != nil {
            Label(center.lastActivity ?? center.statusText, systemImage: "laptopcomputer")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .accessibilityLabel("Claude Code: \(center.lastActivity ?? center.statusText)")
        }
    }
}
