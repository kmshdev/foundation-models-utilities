import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Direct, stateless HTTP/SSE inference authorized by a selected personal ChatGPT registration.
/// No credential changes the endpoint, and inference is never retried automatically.
public struct ChatGPTResponsesClient: Sendable {
    private let tokenProvider: any ChatGPTTokenProviding
    private let catalogTransport: any ServiceHTTPTransport
    private let streamingTransport: any ChatGPTResponsesStreamingTransport

    public init(tokenProvider: any ChatGPTTokenProviding,
                catalogTransport: any ServiceHTTPTransport = URLSessionServiceTransport(),
                streamingTransport: any ChatGPTResponsesStreamingTransport = URLSessionChatGPTResponsesTransport()) {
        self.tokenProvider = tokenProvider
        self.catalogTransport = catalogTransport
        self.streamingTransport = streamingTransport
    }

    /// The subscription catalog uses `models`, not the API-billing catalog's `data` envelope.
    public func models() async throws -> [ChatGPTModelChoice] {
        try Task.checkCancellation()
        let request = try await authorizedRequest(path: "models", method: "GET")
        let response = try await catalogTransport.send(request)
        try Task.checkCancellation()
        guard response.statusCode == 200 else { throw failure(response) }
        guard response.data.count <= 4_194_304,
              let catalog = try? JSONDecoder().decode(Catalog.self, from: response.data),
              catalog.models.allSatisfy({ !$0.slug.isEmpty && !$0.displayName.isEmpty }),
              Set(catalog.models.map(\.slug)).count == catalog.models.count else {
            throw ChatGPTResponsesError.invalidResponse
        }
        return catalog.models.filter { $0.visibility == "list" }
    }

    /// Each call snapshots local history. Only `completed` confirms a successful generation.
    public func response(to request: ChatGPTResponsesRequest) -> AsyncThrowingStream<ChatGPTResponsesEvent, any Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(256)) { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    try request.validate()
                    var http = try await authorizedRequest(path: "responses", method: "POST")
                    http.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    http.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    http.httpBody = try JSONEncoder().encode(request)
                    let stream = try await streamingTransport.open(http)
                    defer { stream.cancel() }
                    guard stream.statusCode == 200 else { throw try await failure(stream) }
                    guard stream.headers["content-type"]?.lowercased().split(separator: ";").first?
                        .trimmingCharacters(in: .whitespaces) == "text/event-stream" else {
                        throw ChatGPTResponsesError.invalidResponse
                    }
                    var parser = ChatGPTSSEParser()
                    var outputBytes = 0
                    for try await chunk in stream.body {
                        try Task.checkCancellation()
                        for frame in try parser.append(chunk) {
                            guard let wire = try? JSONDecoder().decode(ChatGPTResponsesWireEvent.self, from: frame.data),
                                  frame.event == nil || frame.event == wire.type else {
                                throw ChatGPTResponsesError.invalidStream
                            }
                            switch wire.type {
                            case "response.output_text.delta":
                                guard let delta = wire.delta else { throw ChatGPTResponsesError.invalidStream }
                                outputBytes += delta.utf8.count
                                guard outputBytes <= 16_777_216 else { throw ChatGPTResponsesError.oversizedEvent }
                                try yield(.textDelta(delta), to: continuation)
                            case "response.completed":
                                guard let response = wire.response, response.status == "completed", response.error == nil else {
                                    throw ChatGPTResponsesError.invalidStream
                                }
                                if response.output?.contains(where: { $0.content?.contains(where: { $0.type == "refusal" }) == true }) == true {
                                    throw ChatGPTResponsesError.refusal
                                }
                                try yield(.completed(try response.usage?.validated()), to: continuation)
                                continuation.finish()
                                return
                            case "response.failed", "error":
                                throw ChatGPTResponsesError.providerFailure(code: wire.response?.error?.code ?? wire.error?.code ?? wire.code)
                            case "response.incomplete":
                                throw ChatGPTResponsesError.incomplete(reason: ChatGPTResponsesError.safeCode(wire.response?.incompleteDetails?.reason))
                            case "response.refusal.delta", "response.refusal.done":
                                throw ChatGPTResponsesError.refusal
                            case "response.cancelled": throw ChatGPTResponsesError.interrupted
                            default: break // Non-content lifecycle, reasoning and future events don't confirm success.
                            }
                        }
                    }
                    try Task.checkCancellation()
                    throw ChatGPTResponsesError.interrupted
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func authorizedRequest(path: String, method: String) async throws -> URLRequest {
        let token = try await tokenProvider.accessToken()
        try Task.checkCancellation()
        guard !token.isEmpty, !token.contains("\r"), !token.contains("\n") else {
            throw ChatGPTResponsesError.invalidRequest("authorization")
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func yield(_ event: ChatGPTResponsesEvent, to continuation: AsyncThrowingStream<ChatGPTResponsesEvent, any Error>.Continuation) throws {
        switch continuation.yield(event) {
        case .enqueued: break
        case .dropped: throw ChatGPTResponsesError.oversizedEvent
        case .terminated: throw CancellationError()
        @unknown default: throw ChatGPTResponsesError.invalidStream
        }
    }

    private func failure(_ response: ServiceHTTPResponse) -> ChatGPTResponsesError {
        let envelope = response.data.count <= 65_536 ? try? JSONDecoder().decode(ErrorEnvelope.self, from: response.data) : nil
        return .providerFailure(code: envelope?.error.code, status: response.statusCode, retryAfter: response.headers["retry-after"])
    }

    private func failure(_ stream: ChatGPTResponsesHTTPStream) async throws -> ChatGPTResponsesError {
        var data = Data()
        for try await chunk in stream.body {
            try Task.checkCancellation()
            guard data.count + chunk.count <= 65_536 else { break }
            data.append(chunk)
        }
        return failure(ServiceHTTPResponse(data: data, statusCode: stream.statusCode, headers: stream.headers))
    }

    private struct Catalog: Decodable { let models: [ChatGPTModelChoice] }
    private struct ErrorEnvelope: Decodable { let error: ChatGPTResponsesWireEvent.Failure }
}
