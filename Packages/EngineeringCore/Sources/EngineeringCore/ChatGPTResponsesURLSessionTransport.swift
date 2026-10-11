import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Apple-platform streaming uses URLSession.AsyncBytes. No cookie or credential cache is retained.
public final class URLSessionChatGPTResponsesTransport: ChatGPTResponsesStreamingTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: ChatGPTModelRedirectDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func open(_ request: URLRequest) async throws -> ChatGPTResponsesHTTPStream {
        #if canImport(Darwin)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTResponsesError.invalidResponse }
        let pair = AsyncThrowingStream<Data, any Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
        let task = Task {
            do {
                var chunk = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    chunk.append(byte)
                    if byte == 10 || byte == 13 || chunk.count == 4096 {
                        switch pair.continuation.yield(chunk) {
                        case .enqueued: chunk.removeAll(keepingCapacity: true)
                        case .dropped: throw ChatGPTResponsesError.oversizedEvent
                        case .terminated: throw CancellationError()
                        @unknown default: throw ChatGPTResponsesError.invalidStream
                        }
                    }
                }
                if !chunk.isEmpty { pair.continuation.yield(chunk) }
                pair.continuation.finish()
            } catch { pair.continuation.finish(throwing: error) }
        }
        pair.continuation.onTermination = { _ in task.cancel() }
        return ChatGPTResponsesHTTPStream(statusCode: http.statusCode, headers: headers(http), body: pair.stream,
                                         cancel: { task.cancel() })
        #else
        // FoundationNetworking has no AsyncBytes. Native applications use the streaming branch above.
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatGPTResponsesError.invalidResponse }
        let body = AsyncThrowingStream<Data, any Error> { $0.yield(data); $0.finish() }
        return ChatGPTResponsesHTTPStream(statusCode: http.statusCode, headers: headers(http), body: body)
        #endif
    }

    private func headers(_ response: HTTPURLResponse) -> [String: String] {
        response.allHeaderFields.reduce(into: [:]) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
        }
    }
}
