import CoreImage.CIFilterBuiltins
import Foundation
import Observation
import Security
import UIKit

/// The pairing secret lives in this device's Keychain only (ticket 023).
enum MCPPairingStore {
    private static let service = "com.chrixcrusher.pencilecho.mcp"
    private static let account = "pairing"

    static func load() -> MCPPairing? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(MCPPairing.self, from: data)
    }

    @discardableResult
    static func save(_ pairing: MCPPairing) -> Bool {
        guard let data = try? JSONEncoder().encode(pairing) else { return false }
        delete()
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account, kSecValueData as String: data,
                                   kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

/// Owns sharing with Claude Code: the pairing, the server and the shared document.
/// The server runs only while sharing is on and the app is active.
@MainActor
@Observable
final class MCPShareCenter {
    static let shared = MCPShareCenter()

    enum State: Equatable {
        case off
        case starting
        /// Listening; no bridge connected yet.
        case waiting
        case connected
        /// The app is in the background; the server is stopped until it returns.
        case paused
        case failed(String)
    }

    private(set) var state = State.off
    private(set) var pairing: MCPPairing?
    private(set) var sharedTitle: String?
    private(set) var lastActivity: String?
    var isSharing: Bool { sharedTitle != nil }

    @ObservationIgnored let tools: MCPCanvasTools
    @ObservationIgnored private let dispatcher: MCPDispatcher
    @ObservationIgnored private var server: MCPServer?
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let tools = MCPCanvasTools()
        self.tools = tools
        dispatcher = MCPDispatcher(tools: tools)
        pairing = MCPPairingStore.load()
#if DEBUG
        // End-to-end checks: `-MCPPairingCode pe1-…` sets a known pairing (Debug builds only).
        if let code = UserDefaults.standard.string(forKey: "MCPPairingCode"), let preset = MCPPairing(code: code) {
            MCPPairingStore.save(preset)
            pairing = preset
        }
#endif
        tools.onActivity = { [weak self] line in self?.lastActivity = line }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive(false) }
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setActive(true) }
        })
    }

    /// The pairing, created on first use.
    func ensurePairing() -> MCPPairing {
        if let pairing { return pairing }
        let made = MCPPairing.generate()
        MCPPairingStore.save(made)
        pairing = made
        return made
    }

    func share(_ target: MCPShareTarget) {
        tools.target = target
        sharedTitle = target.shareDocument.title
        lastActivity = nil
        UIApplication.shared.isIdleTimerDisabled = true
        restartServer()
    }

    /// Stops sharing. With `target`, only if that editor is the one being shared.
    func stopSharing(_ target: MCPShareTarget? = nil) {
        if let target, tools.target !== target { return }
        tools.target = nil
        sharedTitle = nil
        lastActivity = nil
        UIApplication.shared.isIdleTimerDisabled = false
        server?.stop()
        server = nil
        state = .off
    }

    /// A new key: the Mac must pair again.
    func resetPairing() {
        MCPPairingStore.delete()
        pairing = nil
        _ = ensurePairing()
        if isSharing { restartServer() }
    }

    func isSharing(_ target: MCPShareTarget) -> Bool { tools.target === target }

    private func setActive(_ active: Bool) {
        isActive = active
        guard isSharing else { return }
        if active { restartServer() } else {
            server?.stop()
            server = nil
            state = .paused
        }
    }

    private func restartServer() {
        server?.stop()
        server = nil
        guard isActive else { state = .paused; return }
        let pairing = ensurePairing()
        state = .starting
        let dispatcher = dispatcher
        let server = MCPServer(pairing: pairing, handler: { line in
            await dispatcher.handle(line: line)
        }, onEvent: { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        })
        self.server = server
        server.start()
    }

    private func handle(_ event: MCPServer.Event) {
        guard isSharing else { return }
        switch event {
        case .listening: if state != .connected { state = .waiting }
        case .clientConnected: state = .connected; lastActivity = "Claude Code connected"
        case .clientDisconnected: if state == .connected { state = .waiting }
        case .failed(let message): state = .failed(message)
        }
    }

    var statusText: String {
        switch state {
        case .off: "Not shared"
        case .starting: "Starting…"
        case .waiting: "Waiting for Claude Code on your Mac"
        case .connected: "Claude Code connected"
        case .paused: "Paused while Pencil Echo is in the background"
        case .failed(let message): "Couldn't share: \(message)"
        }
    }

    /// QR code of the pairing code, for scanning on another device.
    static func qrImage(for code: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
