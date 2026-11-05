// Shared by the iPad app and the Mac bridge (tools/mcp-bridge links this file).
// Foundation, Network and CryptoKit only: no UIKit, no app types.
import CryptoKit
import Foundation
import Network

/// Ticket 023: the LAN link between the Mac bridge and Pencil Echo on the iPad.
/// Both ends are Network.framework, so the link is TLS 1.2 with a pre-shared key
/// from pairing (no certificates), carrying newline-delimited JSON-RPC.
enum MCPWire {
    static let serviceType = "_pencilecho-mcp._tcp"
    static let protocolVersion = "2025-06-18"
    /// One JSON-RPC message per line. Images are base64, so lines can be a few MB.
    static let maxLineBytes = 8 * 1024 * 1024
    static let serverName = "pencil-echo"

    /// TLS-PSK parameters. The key is the 32-byte pairing secret; the identity names the host.
    static func parameters(pairing: MCPPairing) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        let key = pairing.key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data(pairing.pskIdentity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, identity as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(options, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    /// Bonjour instance name. The host ID lets a bridge pick its paired iPad.
    static func serviceName(hostId: String) -> String { "Pencil Echo " + hostId }

    static func hostId(fromServiceName name: String) -> String? {
        let prefix = "Pencil Echo "
        guard name.hasPrefix(prefix) else { return nil }
        let id = String(name.dropFirst(prefix.count))
        return MCPPairing.isValidHostId(id) ? id : nil
    }

    static func encode(_ object: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return nil }
        data.append(0x0A)
        return data
    }

    static func decode(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    static func error(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    static func result(id: Any?, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    /// A tool result the model reads as a failure it can act on.
    static func toolError(_ message: String) -> [String: Any] {
        ["content": [["type": "text", "text": message]], "isError": true]
    }
}

/// What the iPad shows and the Mac stores: a host ID and a 256-bit key.
/// Code format: `pe1-<8 hex host id>-<43 base64url key characters>`.
struct MCPPairing: Codable, Equatable, Sendable {
    var hostId: String
    var key: Data

    var pskIdentity: String { "pencilecho-" + hostId }

    static func generate() -> MCPPairing {
        let host = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }.prefix(4)
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return MCPPairing(hostId: host.map { String(format: "%02x", $0) }.joined(), key: key)
    }

    static func isValidHostId(_ id: String) -> Bool {
        id.count == 8 && id.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    var code: String { "pe1-" + hostId + "-" + Self.base64URL(key) }

    init(hostId: String, key: Data) {
        self.hostId = hostId
        self.key = key
    }

    init?(code: String) {
        let parts = code.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "pe1", Self.isValidHostId(parts[1]),
              let key = Self.data(base64URL: parts[2]), key.count == 32 else { return nil }
        self.init(hostId: parts[1], key: key)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "_")
            .replacingOccurrences(of: "/", with: "~").replacingOccurrences(of: "=", with: "")
    }

    static func data(base64URL text: String) -> Data? {
        guard text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "~" }) else { return nil }
        var base64 = text.replacingOccurrences(of: "_", with: "+").replacingOccurrences(of: "~", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }
}

/// Splits a byte stream into lines, refusing any line over the limit.
struct MCPLineBuffer: Sendable {
    private var buffer = Data()
    let limit: Int

    init(limit: Int = MCPWire.maxLineBytes) { self.limit = limit }

    enum Failure: Error { case lineTooLong }

    /// Appends bytes and returns every complete non-empty line.
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = Data(buffer[buffer.index(after: newline)...])
            let trimmed = line.last == 0x0D ? line.dropLast() : line
            if !trimmed.isEmpty { lines.append(Data(trimmed)) }
        }
        if buffer.count > limit { buffer = Data(); throw Failure.lineTooLong }
        return lines
    }
}

/// Tool names, descriptions and argument schemas. The iPad adds the full answer
/// schema; the bridge serves this list when the iPad isn't reachable yet.
enum MCPCatalog {
    static let status = "pencil_echo_status"
    static let instructions = "pencil_echo_instructions"
    static let capture = "pencil_echo_capture"
    static let place = "pencil_echo_place"

    static let serverInstructions = """
    Pencil Echo is a handwriting notebook on the user's iPad. Call pencil_echo_instructions once to learn \
    the answer format, then pencil_echo_capture to see the user's page, then pencil_echo_place with the \
    capture's captureId and one answer object. Answers arrive on the iPad as drafts the user accepts or \
    discards. If placing fails, read the error, fix the answer and place again with the same captureId. \
    If the page changed, capture again.
    """

    static func tools(answerSchema: [String: Any]? = nil) -> [[String: Any]] {
        [
            [
                "name": status,
                "description": "Shows whether a Pencil Echo document is shared from the iPad: title, type, pages and revision.",
                "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            ],
            [
                "name": instructions,
                "description": "Returns the rules and JSON format for Pencil Echo answers: object types, plots, native ink drawings, diagram strokes, labels, page-coordinate overlays and placement. Read once before placing.",
                "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            ],
            [
                "name": capture,
                "description": "Captures part of the shared page as a PNG plus geometry JSON (captureId, captureFrame, focusFrame, imageScale, pageBounds). target newest is the ink written since the last capture with the work around it; visible is what the iPad shows; selection is the lasso selection; page is a whole page. Page points: pageX = captureFrame.x + imageX / imageScale.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "target": ["type": "string", "enum": ["newest", "visible", "selection", "page"],
                                   "description": "Default newest. Falls back to visible when there is no new ink."],
                        "page": ["type": "integer", "minimum": 0, "description": "Page index for target page. Default the page in view."],
                    ],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": place,
                "description": "Places one answer on the captured page as drafts. answer is one JSON object in the Pencil Echo answer format (version 3), checked by the app's validator. Existing work is never edited or deleted.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "captureId": ["type": "string", "description": "From pencil_echo_capture."],
                        "answer": answerSchema ?? ["type": "object", "description": "The answer object; see pencil_echo_instructions."],
                    ],
                    "required": ["captureId", "answer"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }

    static func initializeResult(version: String) -> [String: Any] {
        [
            "protocolVersion": protocolVersion(for: version),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": MCPWire.serverName, "title": "Pencil Echo", "version": "1.0"],
            "instructions": serverInstructions,
        ]
    }

    /// Answer with the client's version when it is one we know, else ours.
    static func protocolVersion(for requested: String) -> String {
        ["2025-06-18", "2025-03-26", "2024-11-05"].contains(requested) ? requested : MCPWire.protocolVersion
    }
}
