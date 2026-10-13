import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import EngineeringCore
@testable import EngineeringServices

@Suite struct ChatGPTResponsesTests {
    @Test func catalogUsesSubscriptionEnvelopeAndKeepsDisplayOrder() async throws {
        let transport = CatalogTransport(body: #"{"models":[{"slug":"second","display_name":"Second","visibility":"list"},{"slug":"internal","display_name":"Hidden","visibility":"hide"},{"slug":"first","display_name":"First","visibility":"list"}]}"#)
        let token = TokenProvider()
        let client = ChatGPTResponsesClient(tokenProvider: token, catalogTransport: transport)
        let models = try await client.models()
        #expect(models.map(\.slug) == ["second", "first"])
        #expect(models.map(\.displayName) == ["Second", "First"])
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(requests[0].httpMethod == "GET")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer test-oauth")
        #expect(await token.calls == 1)
    }

    @Test func apiBillingEnvelopeIsRejected() async throws {
        let client = ChatGPTResponsesClient(tokenProvider: TokenProvider(), catalogTransport: CatalogTransport(body: #"{"data":[]}"#))
        await #expect(throws: ChatGPTResponsesError.invalidResponse) { _ = try await client.models() }
    }

    @Test func requestIncludesAllLocalHistoryWithoutUnsupportedStateOrSamplingFields() async throws {
        let transport = StreamTransport(chunks: [complete])
        let client = ChatGPTResponsesClient(tokenProvider: TokenProvider(), streamingTransport: transport)
        let history: [ChatGPTResponsesMessage] = [
            .init(role: .developer, content: "Use Swift."), .init(role: .user, content: "Earlier outcome"),
            .init(role: .assistant, content: "Earlier answer"), .init(role: .user, content: "Now plan it")
        ]
        _ = try await events(client.response(to: .init(model: "model-slug", input: history)))
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-oauth")
        let requestBody = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect(Set(object.keys) == ["model", "input", "store", "stream"])
        #expect(object["model"] as? String == "model-slug")
        #expect(object["store"] as? Bool == false)
        #expect(object["stream"] as? Bool == true)
        let input = try #require(object["input"] as? [[String: String]])
        #expect(input.map { $0["role"] } == ["developer", "user", "assistant", "user"])
        #expect(input.map { $0["content"] } == history.map(\.content))
    }

    @Test func structuredRequestSendsStrictResponsesFormatAndClosesNestedObjects() throws {
        let format = try ChatGPTResponsesFormat(name: "Plan", schemaJSON: Data(#"{"type":"object","properties":{"task":{"type":"object","properties":{"title":{"type":"string"}},"required":["title"]}},"required":["task"]}"#.utf8))
        let request = ChatGPTResponsesRequest(model: "model", input: [.init(role: .user, content: "Plan")], format: format)
        let body = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let text = try #require(body["text"] as? [String: Any])
        let encoded = try #require(text["format"] as? [String: Any])
        #expect(encoded["type"] as? String == "json_schema")
        #expect(encoded["strict"] as? Bool == true)
        let schema = try #require(encoded["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect((properties["task"] as? [String: Any])?["additionalProperties"] as? Bool == false)
    }

    @Test func optionalAndOpenObjectSchemasAreRejectedInsteadOfChangingMeaning() {
        #expect(throws: ChatGPTResponsesError.unsupportedSchema) {
            _ = try ChatGPTResponsesFormat(name: "Plan", schemaJSON: Data(#"{"type":"object","properties":{"name":{"type":"string"}},"required":[]}"#.utf8))
        }
        #expect(throws: ChatGPTResponsesError.unsupportedSchema) {
            _ = try ChatGPTResponsesFormat(name: "Plan", schemaJSON: Data(#"{"type":"object","properties":{},"required":[],"additionalProperties":true}"#.utf8))
        }
    }

    @Test func utf8AndCrLfCanSplitAtEveryByteAndUsageIsAuthoritative() async throws {
        let text = "\u{FEFF}: heartbeat\r\nevent: response.output_text.delta\r\ndata: {\"type\":\"response.output_text.delta\",\r\ndata: \"delta\":\"Hi 👋\"}\r\n\r\n"
        let usage = #"data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":10,"output_tokens":4,"input_tokens_details":{"cached_tokens":2},"output_tokens_details":{"reasoning_tokens":1}}}}"# + "\r\n\r\n"
        let chunks = Data((text + usage).utf8).map { Data([$0]) }
        let client = ChatGPTResponsesClient(tokenProvider: TokenProvider(), streamingTransport: StreamTransport(chunks: chunks))
        let result = try await events(client.response(to: prompt))
        #expect(result == [.textDelta("Hi 👋"), .completed(.init(inputTokens: 10, cachedInputTokens: 2, outputTokens: 4, reasoningOutputTokens: 1))])
    }

    @Test func usageFailureAfterTextNeverBecomesCompletion() async throws {
        let failed = Data((#"data: {"type":"response.failed","response":{"status":"failed","error":{"code":"subscription_sharing_usage_limit_exceeded","message":"do not log this"}}}"# + "\n\n").utf8)
        let transport = StreamTransport(chunks: [delta, failed])
        let client = ChatGPTResponsesClient(tokenProvider: TokenProvider(), streamingTransport: transport)
        var collected: [ChatGPTResponsesEvent] = []
        do {
            for try await event in client.response(to: prompt) { collected.append(event) }
            Issue.record("Expected usage limit failure")
        } catch {
            #expect(error as? ChatGPTResponsesError == .usageLimit)
        }
        #expect(collected == [.textDelta("partial")])
        #expect(await transport.requests.count == 1)
    }

    @Test func incompleteRefusalAndInterruptedEndingsRemainFailures() async throws {
        let endings: [(Data, ChatGPTResponsesError)] = [
            (Data((#"data: {"type":"response.incomplete","response":{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}"# + "\n\n").utf8), .incomplete(reason: "max_output_tokens")),
            (Data((#"data: {"type":"response.refusal.delta","delta":"No"}"# + "\n\n").utf8), .refusal),
            (Data(), .interrupted),
            (Data(#"data: {"type":"response.completed","response":{"status":"completed"}}"#.utf8), .interrupted)
        ]
        for (ending, expected) in endings {
            let client = ChatGPTResponsesClient(tokenProvider: TokenProvider(), streamingTransport: StreamTransport(chunks: [delta, ending]))
            await #expect(throws: expected) { _ = try await events(client.response(to: prompt)) }
        }
    }

    @Test func malformedTypeMismatchAndInvalidUsageDoNotProduceSuccess() async throws {
        let fixtures = [
            "event: error\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n",
            "data: [DONE]\n\n",
            "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"failed\"}}\n\n",
            "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":2,\"output_tokens\":1,\"input_tokens_details\":{\"cached_tokens\":3}}}}\n\n"
        ]
        for fixture in fixtures {
            let client = ChatGPTResponsesClient(tokenProvider: TokenProvider(), streamingTransport: StreamTransport(chunks: [Data(fixture.utf8)]))
            await #expect(throws: ChatGPTResponsesError.invalidStream) { _ = try await events(client.response(to: prompt)) }
        }
    }

    @Test func httpUsageErrorsAndUnauthorizedAreNotRetried() async throws {
        let transport = StreamTransport(chunks: [Data(#"{"error":{"code":"subscription_sharing_usage_unavailable"}}"#.utf8)], status: 403)
        let client = ChatGPTResponsesClient(tokenProvider: TokenProvider(), streamingTransport: transport)
        await #expect(throws: ChatGPTResponsesError.usageUnavailable) { _ = try await events(client.response(to: prompt)) }
        #expect(await transport.requests.count == 1)
        let unauthorized = StreamTransport(chunks: [], status: 401)
        let other = ChatGPTResponsesClient(tokenProvider: TokenProvider(), streamingTransport: unauthorized)
        await #expect(throws: ChatGPTResponsesError.http(status: 401, code: nil, retryAfter: nil)) { _ = try await events(other.response(to: prompt)) }
        #expect(await unauthorized.requests.count == 1)
    }

    @Test func invalidRequestDoesNotObtainCredentialOrOpenTransport() async throws {
        let token = TokenProvider()
        let transport = StreamTransport(chunks: [])
        let client = ChatGPTResponsesClient(tokenProvider: token, streamingTransport: transport)
        await #expect(throws: ChatGPTResponsesError.invalidRequest("conversation")) {
            _ = try await events(client.response(to: .init(model: "model", input: [])))
        }
        #expect(await token.calls == 0)
        #expect(await transport.requests.isEmpty)
    }

    @Test func sseSizeBoundAndInvalidUtf8AreEnforced() throws {
        var parser = ChatGPTSSEParser(maximumEventBytes: 20)
        #expect(throws: ChatGPTResponsesError.oversizedEvent) { _ = try parser.append(Data(repeating: 65, count: 21)) }
        var malformed = ChatGPTSSEParser()
        #expect(throws: ChatGPTResponsesError.invalidStream) { _ = try malformed.append(Data([0xFF, 10])) }
    }

    @Test func completedEventCancelsTheUnderlyingHttpStream() async throws {
        let probe = CancellationProbe()
        let transport = StreamTransport(chunks: [complete], probe: probe)
        let client = ChatGPTResponsesClient(tokenProvider: TokenProvider(), streamingTransport: transport)
        #expect(try await events(client.response(to: prompt)) == [.completed(nil)])
        #expect(probe.wasCancelled)
    }

    @Test func cancellationAfterDeltaCancelsProducerWithoutConfirmingSuccess() async throws {
        let probe = CancellationProbe()
        let pair = AsyncThrowingStream<Data, any Error>.makeStream()
        let transport = StreamTransport(chunks: [], body: pair.stream, probe: probe)
        let client = ChatGPTResponsesClient(tokenProvider: TokenProvider(), streamingTransport: transport)
        let task = Task {
            for try await event in client.response(to: prompt) {
                if event == .textDelta("partial") { return }
                Issue.record("Unexpected completion")
            }
        }
        pair.continuation.yield(delta)
        try await task.value
        // Finishing the consumer releases/cancels the response stream and its transport.
        for _ in 0..<100 where !probe.wasCancelled { await Task.yield() }
        #expect(probe.wasCancelled)
        pair.continuation.finish()
    }

    private var prompt: ChatGPTResponsesRequest { .init(model: "model", input: [.init(role: .user, content: "Plan")]) }
    private var delta: Data { Data((#"data: {"type":"response.output_text.delta","delta":"partial"}"# + "\n\n").utf8) }
    private var complete: Data { Data((#"data: {"type":"response.completed","response":{"status":"completed"}}"# + "\n\n").utf8) }

    private func events(_ stream: AsyncThrowingStream<ChatGPTResponsesEvent, any Error>) async throws -> [ChatGPTResponsesEvent] {
        var result: [ChatGPTResponsesEvent] = []
        for try await event in stream { result.append(event) }
        return result
    }

    private actor TokenProvider: ChatGPTTokenProviding {
        private(set) var calls = 0
        func accessToken() async throws -> String { calls += 1; return "test-oauth" }
    }
    private actor CatalogTransport: ServiceHTTPTransport {
        let body: String
        private(set) var requests: [URLRequest] = []
        init(body: String) { self.body = body }
        func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
            requests.append(request)
            return .init(data: Data(body.utf8), statusCode: 200)
        }
    }
    private actor StreamTransport: ChatGPTResponsesStreamingTransport {
        let chunks: [Data]
        let status: Int
        let body: AsyncThrowingStream<Data, any Error>?
        let probe: CancellationProbe?
        private(set) var requests: [URLRequest] = []
        init(chunks: [Data], status: Int = 200, body: AsyncThrowingStream<Data, any Error>? = nil, probe: CancellationProbe? = nil) {
            self.chunks = chunks; self.status = status; self.body = body; self.probe = probe
        }
        func open(_ request: URLRequest) async throws -> ChatGPTResponsesHTTPStream {
            requests.append(request)
            let stream = body ?? AsyncThrowingStream<Data, any Error> { continuation in
                for chunk in chunks { continuation.yield(chunk) }
                continuation.finish()
            }
            return .init(statusCode: status, headers: ["Content-Type": "text/event-stream; charset=utf-8"], body: stream,
                         cancel: { [probe] in probe?.cancel() })
        }
    }
    private final class CancellationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var wasCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }
}
