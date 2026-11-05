// pencilecho-mcp: the Mac end of ticket 023.
//
//   pencilecho-mcp pair <code>   store the pairing code shown on the iPad
//   pencilecho-mcp serve         stdio MCP server (Claude Code launches this)
//   pencilecho-mcp status        check that the iPad is reachable and sharing
//   pencilecho-mcp selftest      check TLS-PSK on this Mac without an iPad
//
// The bridge answers initialize locally and forwards tool calls to the iPad,
// finding it with Bonjour each time it (re)connects.
import Foundation
import Network

@main
struct PencilEchoMCP {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first {
        case "pair":
            exit(pair(arguments.dropFirst().first) ? 0 : 1)
        case "serve":
            guard let pairing = PairingFile.load() else {
                log("Not paired. Run: pencilecho-mcp pair <code from the iPad>")
                exit(1)
            }
            await Server(pairing: pairing).run()
        case "status":
            exit(await status() ? 0 : 1)
        case "selftest":
            exit(await selftest() ? 0 : 1)
        default:
            print("""
            pencilecho-mcp: lets Claude Code work on Pencil Echo documents on your iPad.

              pencilecho-mcp pair <code>   Store the pairing code from Pencil Echo → Claude Code
              pencilecho-mcp serve         Run as an MCP server (Claude Code starts this)
              pencilecho-mcp status        Check that the iPad is reachable and sharing
              pencilecho-mcp selftest      Check the encrypted link on this Mac

            Add to Claude Code:
              claude mcp add pencil-echo --scope user -- \(CommandLine.arguments[0]) serve
            """)
            exit(arguments.isEmpty ? 0 : 1)
        }
    }

    static func pair(_ code: String?) -> Bool {
        guard let code, let pairing = MCPPairing(code: code) else {
            log("That isn't a Pencil Echo pairing code. Copy it from Pencil Echo → Claude Code on the iPad.")
            return false
        }
        do {
            try PairingFile.save(pairing)
            print("Paired with Pencil Echo \(pairing.hostId). Saved to \(PairingFile.url.path).")
            return true
        } catch {
            log("Couldn't save the pairing: \(error.localizedDescription)")
            return false
        }
    }

    static func status() async -> Bool {
        guard let pairing = PairingFile.load() else { log("Not paired."); return false }
        let link = Link(pairing: pairing) { _ in }
        guard await link.connect(timeout: 8) else {
            log("Couldn't reach Pencil Echo \(pairing.hostId). Open a document on the iPad, turn on Share with Claude Code, and keep both on the same Wi-Fi.")
            return false
        }
        let reply = await link.request(["jsonrpc": "2.0", "id": "status", "method": "tools/call",
                                        "params": ["name": MCPCatalog.status, "arguments": [String: Any]()]], timeout: 10)
        let content = ((reply?["result"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
        print(content.compactMap { $0["text"] as? String }.joined(separator: "\n"))
        link.close()
        return reply != nil
    }

    /// A TLS-PSK echo server and client on localhost, to check this Mac's Network.framework.
    static func selftest() async -> Bool {
        let pairing = MCPPairing.generate()
        guard let port = NWEndpoint.Port(rawValue: UInt16.random(in: 40_000...60_000)),
              let listener = try? NWListener(using: MCPWire.parameters(pairing: pairing), on: port) else {
            log("Couldn't start a test listener."); return false
        }
        let queue = DispatchQueue(label: "selftest")
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                if let data { connection.send(content: data, completion: .contentProcessed { _ in }) }
            }
        }
        let ready = Signal()
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fire() } }
        listener.start(queue: queue)
        guard await ready.wait(timeout: 5) else { log("Test listener didn't start."); return false }
        let link = Link(pairing: pairing, fixedEndpoint: .hostPort(host: "127.0.0.1", port: port)) { _ in }
        defer { link.close(); listener.cancel() }
        guard await link.connect(timeout: 5) else { log("TLS-PSK connection failed."); return false }
        let reply = await link.request(["jsonrpc": "2.0", "id": 7, "method": "ping"], timeout: 5)
        guard reply?["id"] as? Int == 7 else { log("No echo over TLS-PSK."); return false }
        print("Self-test passed: TLS-PSK works on this Mac.")
        return true
    }
}

func log(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// One-shot wake-up for async waits on Network.framework callbacks.
final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func fire() {
        lock.lock()
        guard !fired else { lock.unlock(); return }
        fired = true
        let current = waiters.values
        waiters = [:]
        lock.unlock()
        current.forEach { $0.resume(returning: true) }
    }

    /// True when fired before the timeout.
    func wait(timeout: Double) async -> Bool {
        let token = UUID()
        return await withCheckedContinuation { continuation in
            lock.lock()
            if fired { lock.unlock(); continuation.resume(returning: true); return }
            waiters[token] = continuation
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                lock.lock()
                let waiter = waiters.removeValue(forKey: token)
                lock.unlock()
                waiter?.resume(returning: false)
            }
        }
    }
}

/// Pairing stored in Application Support, readable only by this user.
enum PairingFile {
    /// `PENCILECHO_MCP_PAIRING` overrides the location, for tests.
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["PENCILECHO_MCP_PAIRING"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PencilEchoMCP/pairing.json")
    }

    static func load() -> MCPPairing? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(MCPPairing.self, from: $0) }
    }

    static func save(_ pairing: MCPPairing) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(pairing)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// The encrypted connection to the iPad. Lines from the iPad go to `onLine`
/// unless a `request` is waiting for that ID.
final class Link: @unchecked Sendable {
    private let pairing: MCPPairing
    private let fixedEndpoint: NWEndpoint?
    private let onLine: @Sendable (Data) -> Void
    private let queue = DispatchQueue(label: "pencilecho-mcp.link")
    private var connection: NWConnection?
    private var buffer = MCPLineBuffer()
    private var waiting: [String: CheckedContinuation<[String: Any]?, Never>] = [:]
    var onDisconnect: @Sendable () -> Void = {}

    init(pairing: MCPPairing, fixedEndpoint: NWEndpoint? = nil, onLine: @escaping @Sendable (Data) -> Void) {
        self.pairing = pairing
        self.fixedEndpoint = fixedEndpoint
        self.onLine = onLine
    }

    var isConnected: Bool { queue.sync { connection?.state == .ready } }

    private var inflight: Task<Bool, Never>?

    /// Finds the paired iPad with Bonjour (or uses the fixed endpoint) and connects.
    /// Concurrent callers share one attempt: the iPad keeps only the newest
    /// connection, so two racing attempts could knock each other out.
    func connect(timeout: Double) async -> Bool {
        if isConnected { return true }
        let task = queue.sync { () -> Task<Bool, Never> in
            if let inflight { return inflight }
            let made = Task { await self.connectOnce(timeout: timeout) }
            inflight = made
            return made
        }
        let ok = await task.value
        queue.sync { if inflight == task { inflight = nil } }
        return ok
    }

    private func connectOnce(timeout: Double) async -> Bool {
        if isConnected { return true }
        let endpoint: NWEndpoint?
        if let fixedEndpoint { endpoint = fixedEndpoint } else { endpoint = await discover(timeout: timeout) }
        guard let endpoint else { return false }
        let ready = Signal()
        let failed = Signal()
        let connection = NWConnection(to: endpoint, using: MCPWire.parameters(pairing: pairing))
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: ready.fire()
            case .failed, .cancelled:
                failed.fire()
                self?.dropped(connection)
            case .waiting: connection.cancel()
            default: break
            }
        }
        queue.sync {
            self.connection?.cancel()
            self.connection = connection
            self.buffer = MCPLineBuffer()
        }
        connection.start(queue: queue)
        let ok = await ready.wait(timeout: timeout)
        if !ok { connection.cancel(); return false }
        receive(on: connection)
        return true
    }

    private func discover(timeout: Double) async -> NWEndpoint? {
        let found = Signal()
        let browser = NWBrowser(for: .bonjour(type: MCPWire.serviceType, domain: nil), using: MCPWire.parameters(pairing: pairing))
        let box = EndpointBox()
        let hostId = pairing.hostId
        browser.browseResultsChangedHandler = { results, _ in
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint, MCPWire.hostId(fromServiceName: name) == hostId {
                    box.endpoint = result.endpoint
                    found.fire()
                }
            }
        }
        browser.start(queue: queue)
        _ = await found.wait(timeout: timeout)
        browser.cancel()
        return box.endpoint
    }

    final class EndpointBox: @unchecked Sendable { var endpoint: NWEndpoint? }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                guard let lines = try? buffer.append(data) else { connection.cancel(); return }
                for line in lines { deliver(line) }
            }
            if isComplete || error != nil { connection.cancel(); return }
            receive(on: connection)
        }
    }

    private func deliver(_ line: Data) {
        if let message = MCPWire.decode(line), let id = message["id"].map({ "\($0)" }), let waiter = waiting.removeValue(forKey: id) {
            waiter.resume(returning: message)
        } else {
            onLine(line)
        }
    }

    private func dropped(_ connection: NWConnection) {
        guard self.connection === connection else { return }
        self.connection = nil
        let current = waiting; waiting = [:]
        current.values.forEach { $0.resume(returning: nil) }
        onDisconnect()
    }

    /// Sends a line without waiting; the reply arrives through `onLine`.
    func send(_ line: Data) -> Bool {
        queue.sync {
            guard let connection, connection.state == .ready else { return false }
            connection.send(content: line, completion: .contentProcessed { _ in })
            return true
        }
    }

    /// Sends a request and waits for the reply with the same ID.
    func request(_ message: [String: Any], timeout: Double) async -> [String: Any]? {
        guard let line = MCPWire.encode(message), let id = message["id"].map({ "\($0)" }) else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let connection, connection.state == .ready else { continuation.resume(returning: nil); return }
                waiting[id] = continuation
                connection.send(content: line, completion: .contentProcessed { _ in })
                queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.waiting.removeValue(forKey: id)?.resume(returning: nil)
                }
            }
        }
    }

    func close() { queue.sync { connection?.cancel(); connection = nil } }
}

/// stdio MCP server: answers lifecycle messages itself and forwards the rest.
final class Server: @unchecked Sendable {
    private let pairing: MCPPairing
    private let output = DispatchQueue(label: "pencilecho-mcp.stdout")
    private let state = DispatchQueue(label: "pencilecho-mcp.state")
    private var pending: [String: (id: Any, isTool: Bool)] = [:]
    private var link: Link!

    static let unreachable = "Pencil Echo isn't reachable. Ask the user to open a document on the iPad, turn on Share with Claude Code (the laptop button in the AI toolbar), keep Pencil Echo open, and keep the iPad on the same Wi-Fi as this Mac."

    init(pairing: MCPPairing) {
        self.pairing = pairing
        link = Link(pairing: pairing) { [weak self] line in self?.fromiPad(line) }
        link.onDisconnect = { [weak self] in self?.failPending() }
    }

    func run() async {
        log("pencilecho-mcp: serving Pencil Echo \(pairing.hostId)")
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard !line.isEmpty else { continue }
                await handle(Data(line.utf8))
            }
        } catch {
            log("pencilecho-mcp: stdin closed: \(error.localizedDescription)")
        }
        link.close()
    }

    private func write(_ message: [String: Any]) {
        guard let data = MCPWire.encode(message) else { return }
        output.sync { FileHandle.standardOutput.write(data) }
    }

    private func fromiPad(_ line: Data) {
        if let message = MCPWire.decode(line), let id = message["id"] {
            _ = state.sync { pending.removeValue(forKey: "\(id)") }
        }
        var data = line
        data.append(0x0A)
        output.sync { FileHandle.standardOutput.write(data) }
    }

    private func failPending() {
        let current = state.sync { () -> [(id: Any, isTool: Bool)] in
            let values = Array(pending.values); pending = [:]; return values
        }
        for item in current {
            write(item.isTool ? MCPWire.result(id: item.id, MCPWire.toolError(Self.unreachable))
                              : MCPWire.error(id: item.id, code: -32000, message: Self.unreachable))
        }
    }

    private func handle(_ line: Data) async {
        guard let message = MCPWire.decode(line) else {
            write(MCPWire.error(id: nil, code: -32700, message: "Parse error")); return
        }
        guard let method = message["method"] as? String else { return }
        guard let id = message["id"], !(id is NSNull) else { return } // notifications
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            write(MCPWire.result(id: id, MCPCatalog.initializeResult(version: params["protocolVersion"] as? String ?? "")))
            Task { _ = await link.connect(timeout: 3) }
        case "ping":
            write(MCPWire.result(id: id, [:]))
        case "tools/list":
            if await link.connect(timeout: 4), let reply = await link.request(message, timeout: 5) {
                write(reply)
            } else {
                write(MCPWire.result(id: id, ["tools": MCPCatalog.tools()]))
            }
        default:
            let isTool = method == "tools/call"
            guard await link.connect(timeout: 6) else {
                write(isTool ? MCPWire.result(id: id, MCPWire.toolError(Self.unreachable))
                             : MCPWire.error(id: id, code: -32000, message: Self.unreachable))
                return
            }
            state.sync { pending["\(id)"] = (id, isTool) }
            if !link.send(line + Data([0x0A])) { failPending() }
        }
    }
}
