import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import EngineeringCore
@testable import EngineeringServices

private let remoteToken = String(repeating: "r", count: 43)
private let remoteSnapshot = ExecutionSnapshot(connected: true, developers: [], records: [], blocker: nil)

private actor RemoteHandlerFixture: ExecutionRemoteHandler {
    private(set) var operations: [String] = []
    private(set) var dispatches: [ExecutionRemoteDispatch] = []
    private(set) var keys: [ExecutionTaskKey] = []
    private var publication: ExecutionPullRequestReceipt?
    var reject = false
    func setReject() { reject = true }
    func setPublication(_ value: ExecutionPullRequestReceipt) { publication = value }
    func snapshot() throws -> ExecutionSnapshot {
        operations.append("snapshot")
        if reject { throw ServiceClientError.invalidInput("sensitive-host-path-and-token") }
        return remoteSnapshot
    }
    func dispatch(_ request: ExecutionRemoteDispatch) -> ExecutionSnapshot { operations.append("dispatch"); dispatches.append(request); return remoteSnapshot }
    func cancel(_ key: ExecutionTaskKey) -> ExecutionSnapshot { operations.append("cancel"); keys.append(key); return remoteSnapshot }
    func resume(_ key: ExecutionTaskKey) -> ExecutionSnapshot { operations.append("resume"); keys.append(key); return remoteSnapshot }
    func stop() -> ExecutionSnapshot { operations.append("stop"); return remoteSnapshot }
    func restart() -> ExecutionSnapshot { operations.append("restart"); return remoteSnapshot }
    func publish(_ key: ExecutionTaskKey) -> ExecutionPullRequestReceipt {
        operations.append("publish"); keys.append(key); return publication ?? remoteReceipt(key)
    }
}

private actor RemoteTransportFixture: ServiceHTTPTransport {
    let response: ServiceHTTPResponse
    private(set) var requests: [URLRequest] = []
    init(status: Int = 200, data: Data? = nil) throws {
        response = ServiceHTTPResponse(data: try data ?? JSONEncoder().encode(remoteSnapshot), statusCode: status)
    }
    func send(_ request: URLRequest) -> ServiceHTTPResponse { requests.append(request); return response }
}

private func remoteBytes(_ route: String, token: String? = remoteToken, body: Data? = nil, extra: String = "") -> Data {
    let method = route == "snapshot" ? "GET" : "POST"
    var header = "\(method) /v1/execution/\(route) HTTP/1.1\r\nHost: executor.example\r\n"
    if let token { header += "Authorization: Bearer \(token)\r\n" }
    if method == "POST" { header += "Content-Type: application/json\r\nContent-Length: \(body?.count ?? 0)\r\n" }
    var data = Data((header + extra + "\r\n").utf8); if let body { data.append(body) }; return data
}

private func remoteReceipt(_ key: ExecutionTaskKey, url: URL? = nil, head: String? = nil) -> ExecutionPullRequestReceipt {
    ExecutionPullRequestReceipt(executionID: UUID(), key: key, pullRequestNumber: 17,
        url: url ?? URL(string: "https://github.com/kmshdev/foundation-models-utilities/pull/17")!,
        branch: "engineering/task", baseBranch: "main", remoteHeadSHA: head ?? String(repeating: "a", count: 40),
        localCommitSHA: String(repeating: "b", count: 40), remoteTreeSHA: String(repeating: "c", count: 40))
}

@Test func remoteRejectsCredentialsAndNeverInvokesHandler() async throws {
    let handler = RemoteHandlerFixture(), router = try ExecutionRemoteRouter(pairingToken: remoteToken, handler: handler)
    for token in [nil, String(repeating: "x", count: 43), remoteToken + "x", String(remoteToken.dropLast())] {
        let request = try #require(try ExecutionRemoteRequest.parse(remoteBytes("stop", token: token)))
        #expect(await router.respond(to: request).statusCode == 401)
    }
    #expect(await handler.operations.isEmpty)
}

@Test func remoteRoutesCompleteTypedContractAndSanitizesHandlerErrors() async throws {
    let handler = RemoteHandlerFixture(), router = try ExecutionRemoteRouter(pairingToken: remoteToken, handler: handler)
    let key = ExecutionTaskKey(outcomeID: UUID(), taskID: "task-1")
    let task = WorkTask(id: key.taskID, title: "Native ownership", owner: .architecture, paths: ["Sources/Ownership.swift"], acceptance: ["One owner"], dependencies: [], handoff: "Share evidence")
    let dispatch = ExecutionRemoteDispatch(outcomeID: key.outcomeID, outcome: "Build ownership", plan: WorkPlan(summary: "Plan", tasks: [task]))
    for (route, data) in [("snapshot", nil), ("dispatch", try JSONEncoder().encode(dispatch)),
                          ("cancel", try JSONEncoder().encode(key)), ("resume", try JSONEncoder().encode(key)), ("stop", nil), ("restart", nil)] {
        let request = try #require(try ExecutionRemoteRequest.parse(remoteBytes(route, body: data)))
        let response = await router.respond(to: request)
        #expect(response.statusCode == 200)
        #expect(try JSONDecoder().decode(ExecutionSnapshot.self, from: response.data) == remoteSnapshot)
    }
    #expect(await handler.operations == ["snapshot", "dispatch", "cancel", "resume", "stop", "restart"])
    #expect(await handler.dispatches == [dispatch])
    #expect(await handler.keys == [key, key])
    await handler.setReject()
    let request = try #require(try ExecutionRemoteRequest.parse(remoteBytes("snapshot")))
    let response = await router.respond(to: request)
    #expect(response.statusCode == 409)
    #expect(!String(decoding: response.data, as: UTF8.self).contains("sensitive"))
}

@Test func remoteFramingRejectsSmugglingOversizeAndProxyTargets() throws {
    let valid = remoteBytes("snapshot")
    #expect(try ExecutionRemoteRequest.parse(Data(valid.dropLast())) == nil)
    var pipelined = valid; pipelined.append(valid)
    #expect(throws: ExecutionRemoteError.malformedRequest) { try ExecutionRemoteRequest.parse(pipelined) }
    #expect(throws: ExecutionRemoteError.malformedRequest) { try ExecutionRemoteRequest.parse(remoteBytes("snapshot", extra: "Authorization: Bearer second\r\n")) }
    #expect(throws: ExecutionRemoteError.malformedRequest) { try ExecutionRemoteRequest.parse(remoteBytes("snapshot", extra: "Transfer-Encoding: chunked\r\n")) }
    #expect(throws: ExecutionRemoteError.oversizedRequest) { try ExecutionRemoteRequest.parse(Data("POST /v1/execution/dispatch HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: 262145\r\n\r\n".utf8)) }
    #expect(throws: ExecutionRemoteError.oversizedRequest) { try ExecutionRemoteRequest.parse(Data(repeating: 65, count: 16_385)) }
    for target in ["https://other.example/v1/execution/snapshot", "/v1/execution/snapshot?token=x", "/v1/execution/%73napshot", "/v1/execution/snapshot/../stop"] {
        #expect(throws: ExecutionRemoteError.unsupportedRoute) { try ExecutionRemoteRequest.parse(Data("GET \(target) HTTP/1.1\r\nHost: x\r\n\r\n".utf8)) }
    }
}

@Test func remoteMalformedPayloadDoesNotReachRuntime() async throws {
    let handler = RemoteHandlerFixture(), router = try ExecutionRemoteRouter(pairingToken: remoteToken, handler: handler)
    for route in ["dispatch", "cancel", "resume", "publish"] {
        let request = try #require(try ExecutionRemoteRequest.parse(remoteBytes(route, body: Data("{}".utf8))))
        #expect(await router.respond(to: request).statusCode == 400)
    }
    #expect(await handler.operations.isEmpty)
}

@Test func remoteClientUsesFixedHTTPSRoutesAndSeparateAccessHeaders() async throws {
    let transport = try RemoteTransportFixture()
    let access = try ExecutionRemoteAccessCredential(clientID: "fixture.access", clientSecret: "fixture-secret")
    let client = try ExecutionRemoteClient(baseURL: URL(string: "https://executor.example/")!, pairingToken: remoteToken, access: access, transport: transport)
    let key = ExecutionTaskKey(outcomeID: UUID(), taskID: "task-2")
    _ = try await client.snapshot(); _ = try await client.cancel(key); _ = try await client.resume(key); _ = try await client.stop(); _ = try await client.restart()
    let requests = await transport.requests
    #expect(requests.map { $0.url!.path } == ["/v1/execution/snapshot", "/v1/execution/cancel", "/v1/execution/resume", "/v1/execution/stop", "/v1/execution/restart"])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(remoteToken)" && $0.value(forHTTPHeaderField: "CF-Access-Client-ID") == "fixture.access" && $0.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "fixture-secret" && $0.timeoutInterval == 15 })
    #expect(try JSONDecoder().decode(ExecutionTaskKey.self, from: requests[1].httpBody!) == key)
    #expect(requests[3].httpBody == Data())
    #expect(requests[4].httpBody == Data())
}

@Test func remoteClientRejectsConfigurationErrorsAndDoesNotFollowRemoteErrorContent() async throws {
    let transport = try RemoteTransportFixture(status: 302, data: Data("secret-token-in-body".utf8))
    for address in ["http://executor.example", "https://user:pass@executor.example", "https://executor.example/path", "https://executor.example?token=x", "https://executor.example#fragment"] {
        #expect(throws: ExecutionRemoteError.invalidConfiguration) { try ExecutionRemoteClient(baseURL: URL(string: address)!, pairingToken: remoteToken, transport: transport) }
    }
    #expect(throws: ExecutionRemoteError.invalidConfiguration) { try ExecutionRemoteAccessCredential(clientID: "id\r\n", clientSecret: "secret") }
    let client = try ExecutionRemoteClient(baseURL: URL(string: "https://executor.example")!, pairingToken: remoteToken, transport: transport)
    await #expect(throws: ExecutionRemoteError.unavailable) { try await client.snapshot() }
    #expect(await transport.requests.count == 1)
    let oversized = try RemoteTransportFixture(data: Data(repeating: 0, count: ExecutionRemoteLimits.maximumResponseBytes + 1))
    let bounded = try ExecutionRemoteClient(baseURL: URL(string: "https://executor.example")!, pairingToken: remoteToken, transport: oversized)
    await #expect(throws: ExecutionRemoteError.oversizedResponse) { try await bounded.snapshot() }
}

@Test func remoteOversizedDispatchAndCanceledRequestNeverReachTransport() async throws {
    let transport = try RemoteTransportFixture()
    let client = try ExecutionRemoteClient(baseURL: URL(string: "https://executor.example")!, pairingToken: remoteToken, transport: transport)
    let task = WorkTask(id: "large", title: "Large", owner: .architecture, paths: ["Sources/File.swift"], acceptance: [], dependencies: [], handoff: "")
    let input = ExecutionRemoteDispatch(outcomeID: UUID(), outcome: String(repeating: "x", count: ExecutionRemoteLimits.maximumBodyBytes), plan: WorkPlan(summary: "", tasks: [task]))
    await #expect(throws: ExecutionRemoteError.oversizedRequest) { try await client.dispatch(input) }
    let operation = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await client.snapshot()
    }
    await #expect(throws: CancellationError.self) { try await operation.value }
    #expect(await transport.requests.isEmpty)
}

@Test func remoteDefaultTransportCancelsBeforeInstallingNetworkTask() async throws {
    let transport = ExecutionRemoteURLSessionTransport()
    let operation = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await transport.send(URLRequest(url: URL(string: "https://never-contact-this.invalid")!))
    }
    await #expect(throws: CancellationError.self) { try await operation.value }
}

@Test func remotePublishPreservesReceiptIdentityAndNeverTransmitsRepositoryCredentials() async throws {
    let key = ExecutionTaskKey(outcomeID: UUID(), taskID: "publish-task")
    let handler = RemoteHandlerFixture(), router = try ExecutionRemoteRouter(pairingToken: remoteToken, handler: handler)
    let request = try #require(try ExecutionRemoteRequest.parse(remoteBytes("publish", body: JSONEncoder().encode(key))))
    let response = await router.respond(to: request)
    #expect(response.statusCode == 200)
    let receipt = try JSONDecoder().decode(ExecutionPullRequestReceipt.self, from: response.data)
    #expect(receipt.key == key)
    #expect(receipt.localCommitSHA != receipt.remoteHeadSHA)
    #expect(await handler.operations == ["publish"])
    let transport = try RemoteTransportFixture(data: JSONEncoder().encode(receipt))
    let client = try ExecutionRemoteClient(baseURL: URL(string: "https://executor.example")!, pairingToken: remoteToken, transport: transport)
    #expect(try await client.publish(key) == receipt)
    let sent = try #require(await transport.requests.first)
    #expect(sent.url?.path == "/v1/execution/publish")
    #expect(sent.timeoutInterval == 110)
    let body = try JSONSerialization.jsonObject(with: sent.httpBody!) as? [String: Any]
    #expect(Set(body?.keys.map { $0 } ?? []) == ["outcomeID", "taskID"])
    #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer \(remoteToken)")
}

@Test func remotePublishRejectsMismatchedIdentityUnscopedURLsAndUnauthorizedMutation() async throws {
    let key = ExecutionTaskKey(outcomeID: UUID(), taskID: "publish-task")
    let handler = RemoteHandlerFixture(), router = try ExecutionRemoteRouter(pairingToken: remoteToken, handler: handler)
    let unauthorized = try #require(try ExecutionRemoteRequest.parse(remoteBytes("publish", token: String(repeating: "x", count: 43), body: JSONEncoder().encode(key))))
    #expect(await router.respond(to: unauthorized).statusCode == 401)
    let restart = try #require(try ExecutionRemoteRequest.parse(remoteBytes("restart", token: nil)))
    #expect(await router.respond(to: restart).statusCode == 401)
    #expect(await handler.operations.isEmpty)
    let request = try #require(try ExecutionRemoteRequest.parse(remoteBytes("publish", body: JSONEncoder().encode(key))))
    for receipt in [remoteReceipt(ExecutionTaskKey(outcomeID: UUID(), taskID: key.taskID)),
                    remoteReceipt(key, url: URL(string: "https://attacker.invalid/pull/17")!),
                    remoteReceipt(key, head: "not-a-commit")] {
        await handler.setPublication(receipt)
        #expect(await router.respond(to: request).statusCode == 409)
        let transport = try RemoteTransportFixture(data: JSONEncoder().encode(receipt))
        let client = try ExecutionRemoteClient(baseURL: URL(string: "https://executor.example")!, pairingToken: remoteToken, transport: transport)
        await #expect(throws: ExecutionRemoteError.invalidResponse) { try await client.publish(key) }
    }
}
