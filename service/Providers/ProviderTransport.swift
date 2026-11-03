import Foundation

/// Internal transport seam allows fixture tests without credentials/network.
enum ProviderHTTPEvent: Sendable {
    case response(status: Int, contentType: String)
    case data(Data)
}

struct ProviderHTTPStream: Sendable {
    let events: AsyncThrowingStream<ProviderHTTPEvent, Error>
    let cancel: @Sendable () -> Void
}

protocol ProviderTransport: Sendable {
    func open(_ request: URLRequest) -> ProviderHTTPStream
}

struct URLSessionProviderTransport: ProviderTransport {
    // Dependency injection for an isolated URLProtocol fixture; defaults to no customization.
    var configureSession: @Sendable (URLSessionConfiguration) -> Void = { _ in }
    func open(_ request: URLRequest) -> ProviderHTTPStream {
        let pair = AsyncThrowingStream<ProviderHTTPEvent, Error>.makeStream(bufferingPolicy: .bufferingOldest(32))
        let delegate = StreamingDelegate(continuation: pair.continuation)
        let configuration = URLSessionConfiguration.ephemeral
        configureSession(configuration)
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        let cancel: @Sendable () -> Void = { task.cancel(); session.invalidateAndCancel() }
        pair.continuation.onTermination = { @Sendable _ in cancel() }
        task.resume()
        return ProviderHTTPStream(events: pair.stream, cancel: cancel)
    }
}

/// Mutable counters are accessed only by URLSession's serial delegate queue.
/// Continuation and URLSession cancellation APIs are thread-safe.
private final class StreamingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let continuation: AsyncThrowingStream<ProviderHTTPEvent, Error>.Continuation
    private var receivedBytes = 0

    init(continuation: AsyncThrowingStream<ProviderHTTPEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the key or image to a redirect target, including same-host redirects.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            continuation.finish(throwing: AIError.network)
            completionHandler(.cancel)
            return
        }
        emit(.response(status: response.statusCode, contentType: response.value(forHTTPHeaderField: "Content-Type") ?? ""), session: session)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedBytes += data.count
        guard receivedBytes <= ProviderSSEParser.maxWireBytes else {
            continuation.finish(throwing: AIError.invalidOutput)
            session.invalidateAndCancel()
            return
        }
        emit(.data(data), session: session)
    }

    private func emit(_ event: ProviderHTTPEvent, session: URLSession) {
        switch continuation.yield(event) {
        case .enqueued: break
        case .dropped:
            continuation.finish(throwing: AIError.invalidOutput)
            session.invalidateAndCancel()
        case .terminated: session.invalidateAndCancel()
        @unknown default: session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { continuation.finish(throwing: AIError.normalized(error)) }
        else { continuation.finish() }
        session.finishTasksAndInvalidate()
    }
}
