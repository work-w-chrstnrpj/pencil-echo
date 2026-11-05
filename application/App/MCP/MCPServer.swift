import Foundation
import Network

/// The iPad end of the LAN link (ticket 023): a TLS-PSK listener advertised with
/// Bonjour. One client at a time; a new connection from the paired bridge replaces
/// a stale one. All mutable state lives on `queue`.
final class MCPServer: @unchecked Sendable {
    enum Event: Sendable {
        case listening(port: UInt16)
        case clientConnected
        case clientDisconnected
        case failed(String)
    }

    /// One JSON-RPC line in, at most one line out.
    typealias Handler = @Sendable (Data) async -> Data?

    private let queue = DispatchQueue(label: "com.chrixcrusher.pencilecho.mcp")
    private let pairing: MCPPairing
    private let advertise: Bool
    private let port: NWEndpoint.Port
    private let handler: Handler
    private let onEvent: @Sendable (Event) -> Void
    private var listener: NWListener?
    private var connection: NWConnection?

    init(pairing: MCPPairing, advertise: Bool = true, port: NWEndpoint.Port = .any,
         handler: @escaping Handler, onEvent: @escaping @Sendable (Event) -> Void) {
        self.pairing = pairing
        self.advertise = advertise
        self.port = port
        self.handler = handler
        self.onEvent = onEvent
    }

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            do {
                let listener = try NWListener(using: MCPWire.parameters(pairing: pairing), on: port)
                if advertise {
                    listener.service = NWListener.Service(name: MCPWire.serviceName(hostId: pairing.hostId),
                                                          type: MCPWire.serviceType)
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }
                    switch state {
                    case .ready: onEvent(.listening(port: listener?.port?.rawValue ?? 0))
                    case .failed(let error):
                        onEvent(.failed(error.localizedDescription))
                        queue.async { self.stopOnQueue() }
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: queue)
                self.listener = listener
            } catch {
                onEvent(.failed(error.localizedDescription))
            }
        }
    }

    func stop() { queue.async { [self] in stopOnQueue() } }

    private func stopOnQueue() {
        listener?.cancel()
        listener = nil
        if connection != nil { onEvent(.clientDisconnected) }
        connection?.cancel()
        connection = nil
    }

    private func accept(_ new: NWConnection) {
        if let old = connection { old.cancel() }
        connection = new
        new.stateUpdateHandler = { [weak self, weak new] state in
            guard let self, let new else { return }
            switch state {
            case .ready: onEvent(.clientConnected)
            case .failed, .cancelled:
                if connection === new {
                    connection = nil
                    onEvent(.clientDisconnected)
                }
            default: break
            }
        }
        new.start(queue: queue)
        receive(on: new, reader: Reader())
    }

    /// Per-connection line state, only touched on `queue`.
    private final class Reader: @unchecked Sendable { var buffer = MCPLineBuffer() }

    private func receive(on connection: NWConnection, reader: Reader) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for line in try reader.buffer.append(data) { respond(to: line, on: connection) }
                } catch {
                    connection.cancel()
                    return
                }
            }
            if isComplete || error != nil { connection.cancel(); return }
            receive(on: connection, reader: reader)
        }
    }

    private func respond(to line: Data, on connection: NWConnection) {
        let handler = handler
        Task {
            guard let reply = await handler(line) else { return }
            connection.send(content: reply, completion: .contentProcessed { _ in })
        }
    }
}
