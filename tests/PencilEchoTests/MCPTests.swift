import Foundation
import Network
import PencilKit
import Testing
import UIKit
@testable import PencilEcho

// Ticket 023: LAN MCP wire format, JSON-RPC dispatch, canvas tools and TLS-PSK transport.

extension FakeAskDocument: MCPDraftDocument {
    var title: String { "Fake page" }
    func applyExternalDrafts(_ next: EditorSnapshot, requestId: UUID) {
        conversation.appliedRequests.append(AppliedRequest(requestId: requestId, appliedAt: Date(timeIntervalSince1970: 1_000)))
        applyAIAnswer(next, conversation: conversation, named: "Claude Code drafts")
    }
}

@MainActor
final class FakeShareTarget: MCPShareTarget {
    let document: FakeAskDocument
    var visible = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    var selection: CGRect?
    init(_ document: FakeAskDocument) { self.document = document }
    var shareDocument: any MCPDraftDocument { document }
    func visibleRegion() -> CGRect { visible }
    func selectionRegion() -> CGRect? { selection }
}

struct MCPWireTests {
    @Test func pairingCodeRoundTripsAndRejectsBadCodes() throws {
        let pairing = MCPPairing.generate()
        #expect(MCPPairing.isValidHostId(pairing.hostId) && pairing.key.count == 32)
        #expect(MCPPairing(code: pairing.code) == pairing)
        #expect(MCPPairing(code: "  \(pairing.code)\n") == pairing)
        #expect(MCPPairing(code: "pe2-" + pairing.code.dropFirst(4)) == nil)
        #expect(MCPPairing(code: "pe1-ABCDEF12-" + MCPPairing.base64URL(pairing.key)) == nil)
        #expect(MCPPairing(code: "pe1-\(pairing.hostId)-" + MCPPairing.base64URL(pairing.key.prefix(16))) == nil)
        #expect(MCPPairing(code: "pe1-\(pairing.hostId)-abc+def") == nil)
        #expect(MCPWire.hostId(fromServiceName: MCPWire.serviceName(hostId: pairing.hostId)) == pairing.hostId)
        #expect(MCPWire.hostId(fromServiceName: "Pencil Echo nothex!!") == nil)
    }

    @Test func lineBufferSplitsAndLimits() throws {
        var buffer = MCPLineBuffer(limit: 32)
        #expect(try buffer.append(Data("{\"a\":1}\n{\"b\"".utf8)) == [Data("{\"a\":1}".utf8)])
        #expect(try buffer.append(Data(":2}\r\n\n".utf8)) == [Data("{\"b\":2}".utf8)])
        #expect(throws: MCPLineBuffer.Failure.self) { try buffer.append(Data(repeating: 0x41, count: 40)) }
        // After an overlong line the buffer starts clean.
        #expect(try buffer.append(Data("x\n".utf8)) == [Data("x".utf8)])
    }

    @Test func messagesEncodeAsOneLine() throws {
        let data = try #require(MCPWire.encode(["jsonrpc": "2.0", "id": 1, "result": ["text": "a\nb/c"]]))
        #expect(data.last == 0x0A && data.dropLast().contains(0x0A) == false)
        #expect(MCPWire.decode(data.dropLast())?["id"] as? Int == 1)
    }
}

@MainActor
struct MCPDispatchTests {
    func dispatcher(_ tools: MCPCanvasTools = MCPCanvasTools(), now: @escaping () -> Date = { Date(timeIntervalSince1970: 0) }) -> MCPDispatcher {
        MCPDispatcher(tools: tools, now: now)
    }

    @Test func initializeListAndErrors() async throws {
        let dispatch = dispatcher()
        let initialize = try #require(await dispatch.handle(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                                             "params": ["protocolVersion": "2025-06-18"]]))
        let result = try #require(initialize["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "pencil-echo")
        #expect(await dispatch.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)

        let list = try #require(await dispatch.handle(["jsonrpc": "2.0", "id": "two", "method": "tools/list"]))
        let tools = try #require((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["pencil_echo_status", "pencil_echo_instructions", "pencil_echo_capture", "pencil_echo_place"])
        #expect(tools.allSatisfy { JSONSerialization.isValidJSONObject($0) })

        let unknown = try #require(await dispatch.handle(["jsonrpc": "2.0", "id": 3, "method": "resources/list"]))
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
        let parse = try #require(await dispatch.handle(line: Data("not json".utf8)))
        #expect(((MCPWire.decode(parse.dropLast())?["error"]) as? [String: Any])?["code"] as? Int == -32700)
    }

    @Test func toolCallsAreRateLimited() async throws {
        let dispatch = dispatcher()
        for index in 0..<MCPDispatcher.maxCallsPerMinute {
            let reply = try #require(await dispatch.handle(["jsonrpc": "2.0", "id": index, "method": "tools/call",
                                                            "params": ["name": "pencil_echo_status"]]))
            // Nothing is shared, so the tool reports that as a tool error, not a protocol error.
            #expect((reply["result"] as? [String: Any])?["isError"] as? Bool == true)
        }
        let limited = try #require(await dispatch.handle(["jsonrpc": "2.0", "id": 99, "method": "tools/call",
                                                          "params": ["name": "pencil_echo_status"]]))
        let text = (((limited["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        #expect(text.contains("Too many"))
    }
}

@MainActor
struct MCPCanvasToolTests {
    let base = AskAITests()
    static let answer = #"{"version":3,"operations":[{"op":"add_object","type":"text","source":"4","placement":"right_of_scope","frame":null}],"message":"Four."}"#

    func shared() -> (FakeAskDocument, FakeShareTarget, MCPCanvasTools) {
        let document = base.canvasDocument()
        let target = FakeShareTarget(document)
        let tools = MCPCanvasTools(now: { Date(timeIntervalSince1970: 2_000) })
        tools.target = target
        return (document, target, tools)
    }

    static func text(_ result: [String: Any]) -> String {
        ((result["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    static func captureInfo(_ result: [String: Any]) throws -> [String: Any] {
        let content = try #require(result["content"] as? [[String: Any]])
        let json = try #require(content.last?["text"] as? String)
        return try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func nothingSharedIsAToolError() async {
        let tools = MCPCanvasTools()
        for name in [MCPCatalog.status, MCPCatalog.capture, MCPCatalog.place] {
            let result = await tools.call(name, arguments: [:])
            #expect(result["isError"] as? Bool == true && Self.text(result).contains("Share with Claude Code"))
        }
    }

    @Test func statusAndInstructions() async {
        let (_, target, tools) = shared()
        defer { withExtendedLifetime(target) {} }
        let status = await tools.call(MCPCatalog.status, arguments: [:])
        #expect(status["isError"] == nil && Self.text(status).contains("Fake page") && Self.text(status).contains("\"pages\" : 1"))
        let rules = Self.text(await tools.call(MCPCatalog.instructions, arguments: [:]))
        #expect(rules.contains("focusFrame") && rules.contains("drafts") && rules.contains("Answer JSON Schema"))
    }

    @Test func captureWithoutNewInkFallsBackToVisible() async throws {
        let (_, target, tools) = shared()
        let result = await tools.call(MCPCatalog.capture, arguments: [:])
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "image" && content.first?["mimeType"] as? String == "image/png")
        let encoded = try #require(content.first?["data"] as? String)
        let png = try #require(Data(base64Encoded: encoded))
        #expect(UIImage(data: png) != nil)
        let info = try Self.captureInfo(result)
        #expect(info["target"] as? String == "visible")
        let frame = try #require(info["captureFrame"] as? [String: Double])
        #expect(frame["width"] == target.visible.width && frame["height"] == target.visible.height)
    }

    @Test func newestCaptureUsesInkWrittenAfterSharing() async throws {
        let (document, target, tools) = shared()
        defer { withExtendedLifetime(target) {} }
        let note = AutoAskTests.stroke([CGPoint(x: 500, y: 600), CGPoint(x: 620, y: 630)], at: Date(timeIntervalSince1970: 1_800_005_000))
        document.edit { $0.drawing.strokes.append(note) }
        let info = try Self.captureInfo(await tools.call(MCPCatalog.capture, arguments: ["target": "newest"]))
        #expect(info["target"] as? String == "newest")
        let focus = try #require(info["focusFrame"] as? [String: Double])
        let expected = note.renderBounds.insetBy(dx: -AskAIController.captureMargin, dy: -AskAIController.captureMargin)
        #expect(abs((focus["x"] ?? 0) - expected.minX) < 0.01 && abs((focus["width"] ?? 0) - expected.width) < 0.01)
        // Captured ink is no longer new.
        let again = try Self.captureInfo(await tools.call(MCPCatalog.capture, arguments: ["target": "newest"]))
        #expect(again["target"] as? String == "visible")
    }

    @Test func selectionAndPageTargets() async throws {
        let (_, target, tools) = shared()
        #expect(await tools.call(MCPCatalog.capture, arguments: ["target": "selection"])["isError"] as? Bool == true)
        target.selection = CGRect(x: 80, y: 80, width: 200, height: 100)
        let selected = try Self.captureInfo(await tools.call(MCPCatalog.capture, arguments: ["target": "selection"]))
        #expect((selected["captureFrame"] as? [String: Double])?["width"] == 200)
        let page = try Self.captureInfo(await tools.call(MCPCatalog.capture, arguments: ["target": "page", "page": 0]))
        #expect((page["captureFrame"] as? [String: Double])?["width"] == 2_000)
        #expect(await tools.call(MCPCatalog.capture, arguments: ["target": "page", "page": 4])["isError"] as? Bool == true)
        #expect(await tools.call(MCPCatalog.capture, arguments: ["target": "everything"])["isError"] as? Bool == true)
    }

    @Test func placeAddsDraftsOnceAndExplainsRejections() async throws {
        let (document, target, tools) = shared()
        defer { withExtendedLifetime(target) {} }
        let id = try #require(try Self.captureInfo(await tools.call(MCPCatalog.capture, arguments: [:]))["captureId"] as? String)

        let unknown = await tools.call(MCPCatalog.place, arguments: ["captureId": "nope", "answer": [String: Any]()])
        #expect(unknown["isError"] as? Bool == true && Self.text(unknown).contains("Unknown captureId"))

        let bad = await tools.call(MCPCatalog.place, arguments: ["captureId": id, "answer": ["version": 9, "operations": [[String: Any]](), "message": NSNull()]])
        #expect(bad["isError"] as? Bool == true && Self.text(bad).contains("rejected") && Self.text(bad).contains("/version"))
        #expect(document.applyCount == 0)

        let answer = try #require(try JSONSerialization.jsonObject(with: Data(Self.answer.utf8)) as? [String: Any])
        let placed = await tools.call(MCPCatalog.place, arguments: ["captureId": id, "answer": answer])
        #expect(placed["isError"] == nil && Self.text(placed).contains("drafts"))
        #expect(document.applyCount == 1 && document.lastActionName == "Claude Code drafts")
        let added = try #require(document.snapshot.objects.first)
        #expect(added.source == "4" && added.isDraft == true)

        let twice = await tools.call(MCPCatalog.place, arguments: ["captureId": id, "answer": Self.answer])
        #expect(twice["isError"] as? Bool == true && Self.text(twice).contains("already placed"))
        #expect(document.applyCount == 1)
    }

    @Test func placeAfterThePageChangedAsksForANewCapture() async throws {
        let (document, target, tools) = shared()
        target.visible = base.region
        let id = try #require(try Self.captureInfo(await tools.call(MCPCatalog.capture, arguments: ["target": "visible"]))["captureId"] as? String)
        document.edit { $0.drawing.strokes.append(AskAITests.stroke([CGPoint(x: 120, y: 150), CGPoint(x: 180, y: 150)])) }
        let result = await tools.call(MCPCatalog.place, arguments: ["captureId": id, "answer": Self.answer])
        #expect(result["isError"] as? Bool == true && Self.text(result).contains("Capture again"))
        #expect(document.applyCount == 0)
    }

    @Test func readOnlyDocumentPlacesNothing() async throws {
        let (document, target, tools) = shared()
        defer { withExtendedLifetime(target) {} }
        let id = try #require(try Self.captureInfo(await tools.call(MCPCatalog.capture, arguments: [:]))["captureId"] as? String)
        document.isReadOnly = true
        let result = await tools.call(MCPCatalog.place, arguments: ["captureId": id, "answer": Self.answer])
        #expect(result["isError"] as? Bool == true && Self.text(result).contains("read-only") && document.applyCount == 0)
    }

    @Test func inkDraftsAreMarkedForDiscard() async throws {
        let (document, target, tools) = shared()
        defer { withExtendedLifetime(target) {} }
        let id = try #require(try Self.captureInfo(await tools.call(MCPCatalog.capture, arguments: [:]))["captureId"] as? String)
        let circle = #"{"version":2,"operations":[{"op":"draw_ink","width":100,"height":50,"strokes":[{"kind":"ellipse","points":[[0,0],[100,50]],"closed":true,"color":"red","size":3}],"placement":"right_of_scope","frame":null}],"message":null}"#
        _ = await tools.call(MCPCatalog.place, arguments: ["captureId": id, "answer": circle])
        let batch = try #require(document.snapshot.draftInk.first)
        let added = try #require(document.snapshot.drawing.strokes.last)
        // Positive (PencilKit doesn't draw pre-1970 strokes) but inside the synthetic first day of 1970.
        #expect(batch.strokeDate.timeIntervalSince1970 >= 60 && DraftMarker.isSynthetic(batch.strokeDate) && added.path.creationDate == batch.strokeDate)
    }
}

/// A real TLS-PSK connection over localhost: the same parameters the bridge uses.
struct MCPTransportTests {
    final class Client: @unchecked Sendable {
        let connection: NWConnection
        var buffer = MCPLineBuffer()
        init(port: NWEndpoint.Port, pairing: MCPPairing) {
            connection = NWConnection(host: "127.0.0.1", port: port, using: MCPWire.parameters(pairing: pairing))
        }

        /// Sends one line and waits for one reply line, or nil on failure or timeout.
        func roundTrip(_ line: Data, timeout: Duration = .seconds(5)) async -> Data? {
            await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                let once = Once(continuation)
                let queue = DispatchQueue(label: "mcp-test-client")
                connection.stateUpdateHandler = { [connection] state in
                    switch state {
                    case .ready:
                        connection.send(content: line, completion: .contentProcessed { _ in })
                        self.read(once)
                    case .failed, .cancelled: once.resume(nil)
                    case .waiting: once.resume(nil)
                    default: break
                    }
                }
                connection.start(queue: queue)
                queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout.components.seconds * 1_000))) { once.resume(nil) }
            }
        }

        private func read(_ once: Once) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                if let data, let line = try? self.buffer.append(data).first { once.resume(line); return }
                if error != nil { once.resume(nil); return }
                self.read(once)
            }
        }
    }

    final class Once: @unchecked Sendable {
        private var continuation: CheckedContinuation<Data?, Never>?
        private let lock = NSLock()
        init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
        func resume(_ value: Data?) {
            lock.lock(); let current = continuation; continuation = nil; lock.unlock()
            current?.resume(returning: value)
        }
    }

    func startServer(_ pairing: MCPPairing) async throws -> (MCPServer, NWEndpoint.Port) {
        let port = NWEndpoint.Port(rawValue: UInt16.random(in: 40_000...60_000))!
        let ready = AsyncStream<Bool>.makeStream()
        let server = MCPServer(pairing: pairing, advertise: false, port: port, handler: { line in
            var reply = Data("echo:".utf8)
            reply.append(line)
            reply.append(0x0A)
            return reply
        }, onEvent: { event in
            if case .listening = event { ready.continuation.yield(true) }
            if case .failed = event { ready.continuation.yield(false) }
        })
        server.start()
        var iterator = ready.stream.makeAsyncIterator()
        let started = await iterator.next()
        #expect(started == true)
        return (server, port)
    }

    @Test func pairedClientRoundTrips() async throws {
        let pairing = MCPPairing.generate()
        let (server, port) = try await startServer(pairing)
        defer { server.stop() }
        let reply = await Client(port: port, pairing: pairing).roundTrip(Data("{\"id\":1}\n".utf8))
        #expect(reply == Data("echo:{\"id\":1}".utf8))
    }

    @Test func wrongKeyIsRefused() async throws {
        let pairing = MCPPairing.generate()
        let (server, port) = try await startServer(pairing)
        defer { server.stop() }
        var other = MCPPairing.generate()
        other.hostId = pairing.hostId
        let reply = await Client(port: port, pairing: other).roundTrip(Data("{\"id\":1}\n".utf8), timeout: .seconds(3))
        #expect(reply == nil)
    }
}
