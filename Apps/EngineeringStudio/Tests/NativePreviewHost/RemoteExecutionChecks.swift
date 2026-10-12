@testable import WorkspaceFeature
@testable import StudioWorkflows
@testable import StudioServices
import StudioUI
import EngineeringWorkflows
import EngineeringServices
import Foundation
import Network
import EngineeringCore

/// Exercises the production Network listener with a typed Swift client and isolated pairing credentials.
/// The injected transport carries fixture requests over raw local TCP; production clients still require HTTPS.
@MainActor
func checkRemoteExecution() async throws {
    let token = String(repeating: "n", count: 43)
    let handler = RemoteExecutionCheckHandler()
    let server = ExecutionLoopbackServer(pairingToken: token, handler: handler)
    let port = try await server.start()
    defer { server.stop() }
    let transport = RemoteExecutionCheckTransport(port: port)
    let client = try ExecutionRemoteClient(baseURL: URL(string: "https://bridge-fixture.invalid")!, pairingToken: token, transport: transport)
    let snapshot = try await client.snapshot()
    try remoteRequire(snapshot.connected, "Native loopback snapshot roundtrip")
    let task = WorkTask(id: "native-remote", title: "Remote fixture", owner: .architecture,
                        paths: ["Sources/Fixture.swift"], acceptance: ["Evidence preserved"], dependencies: [], handoff: "Fixture only")
    let input = ExecutionRemoteDispatch(outcomeID: UUID(), outcome: "Isolated remote execution check", plan: WorkPlan(summary: "Fixture", tasks: [task]))
    _ = try await client.dispatch(input)
    let key = ExecutionTaskKey(outcomeID: input.outcomeID, taskID: task.id)
    _ = try await client.cancel(key); _ = try await client.resume(key); _ = try await client.stop(); _ = try await client.restart()
    let receipt = try await client.publish(key)
    try remoteRequire(receipt.key == key && receipt.pullRequestNumber == 19 && receipt.localCommitSHA != receipt.remoteHeadSHA, "Publication receipt retains remote and local provenance")
    try remoteRequire(await handler.operations == ["snapshot", "dispatch", "cancel", "resume", "stop", "restart", "publish"], "All typed operations arrive once")
    try remoteRequire(await handler.dispatches == [input], "Outcome and plan survive actual TCP")
    try remoteRequire(await handler.keys == [key, key, key], "Cancel, resume and publication preserve task identity")
    let unauthorized = try ExecutionRemoteClient(baseURL: URL(string: "https://bridge-fixture.invalid")!, pairingToken: String(repeating: "x", count: 43), transport: transport)
    do { _ = try await unauthorized.stop(); throw remoteFailure("Wrong pairing token must fail") }
    catch ExecutionRemoteError.unauthorized { }
    do { _ = try await unauthorized.restart(); throw remoteFailure("Wrong pairing token cannot restart") }
    catch ExecutionRemoteError.unauthorized { }
    do { _ = try await unauthorized.publish(key); throw remoteFailure("Wrong pairing token cannot publish") }
    catch ExecutionRemoteError.unauthorized { }
    let malformed = Data("POST /v1/execution/dispatch HTTP/1.1\r\nHost: fixture\r\nAuthorization: Bearer \(token)\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}".utf8)
    let malformedResponse = try await RemoteExecutionCheckExchange().send(malformed, port: port)
    try remoteRequire(malformedResponse.statusCode == 400, "Malformed JSON rejected before runtime mutation")
    let tooLarge = Data("POST /v1/execution/dispatch HTTP/1.1\r\nHost: fixture\r\nAuthorization: Bearer \(token)\r\nContent-Type: application/json\r\nContent-Length: 262145\r\n\r\n".utf8)
    let sizeResponse = try await RemoteExecutionCheckExchange().send(tooLarge, port: port)
    try remoteRequire(sizeResponse.statusCode == 413, "Oversize length rejected before body allocation")
    try remoteRequire(await handler.operations.count == 7, "Rejected requests never invoke runtime")
    server.stop()
    let restartedPort = try await server.start()
    let restarted = try ExecutionRemoteClient(baseURL: URL(string: "https://bridge-fixture.invalid")!, pairingToken: token, transport: RemoteExecutionCheckTransport(port: restartedPort))
    _ = try await restarted.snapshot()
    print("Remote execution checks passed: actual IPv4 loopback listener, typed snapshot/dispatch/cancel/resume/stop/restart and fixture publication receipt, pairing rejection, malformed/oversize rejection and listener restart.")
}

private actor RemoteExecutionCheckHandler: ExecutionRemoteHandler {
    private(set) var operations: [String] = []
    private(set) var dispatches: [ExecutionRemoteDispatch] = []
    private(set) var keys: [ExecutionTaskKey] = []
    private let value = ExecutionSnapshot(connected: true, developers: [], records: [], blocker: nil)
    func snapshot() -> ExecutionSnapshot { operations.append("snapshot"); return value }
    func dispatch(_ request: ExecutionRemoteDispatch) -> ExecutionSnapshot { operations.append("dispatch"); dispatches.append(request); return value }
    func cancel(_ key: ExecutionTaskKey) -> ExecutionSnapshot { operations.append("cancel"); keys.append(key); return value }
    func resume(_ key: ExecutionTaskKey) -> ExecutionSnapshot { operations.append("resume"); keys.append(key); return value }
    func stop() -> ExecutionSnapshot { operations.append("stop"); return value }
    func restart() -> ExecutionSnapshot { operations.append("restart"); return value }
    func publish(_ key: ExecutionTaskKey) -> ExecutionPullRequestReceipt {
        operations.append("publish"); keys.append(key)
        return ExecutionPullRequestReceipt(executionID: UUID(), key: key, pullRequestNumber: 19,
            url: URL(string: "https://github.com/kmshdev/foundation-models-utilities/pull/19")!,
            branch: "engineering/fixture", baseBranch: "main", remoteHeadSHA: String(repeating: "a", count: 40),
            localCommitSHA: String(repeating: "b", count: 40), remoteTreeSHA: String(repeating: "c", count: 40))
    }
}

@MainActor
private final class RemoteExecutionCheckTransport: ServiceHTTPTransport {
    let port: UInt16
    init(port: UInt16) { self.port = port }
    func send(_ request: URLRequest) async throws -> ServiceHTTPResponse {
        guard request.url?.host == "bridge-fixture.invalid", let path = request.url?.path else { throw remoteFailure("Fixture transport origin") }
        var text = "\(request.httpMethod ?? "GET") \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n"
        for (name, value) in request.allHTTPHeaderFields ?? [:] { text += "\(name): \(value)\r\n" }
        var data = Data((text + "\r\n").utf8); if let body = request.httpBody { data.append(body) }
        return try await RemoteExecutionCheckExchange().send(data, port: port)
    }
}

@MainActor
private final class RemoteExecutionCheckExchange {
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<ServiceHTTPResponse, any Error>?
    private var deadline: Task<Void, Never>?
    private var received = Data()

    func send(_ request: Data, port: UInt16) async throws -> ServiceHTTPResponse {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        self.connection = connection
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        connection.send(content: request, completion: .contentProcessed { [weak self] error in
                            Task { @MainActor in
                                guard let self else { return }
                                if error != nil { self.finish(.failure(remoteFailure("Send native fixture"))) }
                                else { self.read() }
                            }
                        })
                    case .failed: self.finish(.failure(remoteFailure("Connect native fixture")))
                    default: break
                    }
                }
            }
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.finish(.failure(remoteFailure("Native fixture timeout")))
            }
            connection.start(queue: .main)
        }
    }

    private func read() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.continuation != nil else { return }
                if let data { self.received.append(data) }
                guard error == nil, self.received.count <= ExecutionRemoteLimits.maximumResponseBytes + 16_384 else {
                    self.finish(.failure(remoteFailure("Receive native fixture"))); return
                }
                if complete {
                    guard let boundary = self.received.range(of: Data("\r\n\r\n".utf8)),
                          let text = String(data: self.received[..<boundary.lowerBound], encoding: .utf8),
                          let status = text.components(separatedBy: " ").dropFirst().first.flatMap(Int.init) else {
                        self.finish(.failure(remoteFailure("Parse native fixture"))); return
                    }
                    let body = Data(self.received[boundary.upperBound...])
                    self.finish(.success(ServiceHTTPResponse(data: body, statusCode: status)))
                } else { self.read() }
            }
        }
    }

    private func finish(_ result: Result<ServiceHTTPResponse, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadline?.cancel(); deadline = nil
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        continuation.resume(with: result)
    }
}

private func remoteFailure(_ message: String) -> NSError {
    NSError(domain: "RemoteExecutionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

private func remoteRequire(_ condition: Bool, _ message: String) throws {
    if !condition { throw remoteFailure(message) }
}
