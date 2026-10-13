import Foundation
import MCP

/// Holds request transmission itself, before the fixture server can receive a tool call.
/// Disconnect releases every held send; no sleeping or assumed scheduler timing is used.
actor MCPStalledSendTransport: Transport {
    nonisolated let logger = InMemoryTransport().logger
    private let wrapped: InMemoryTransport
    private let method: String
    private var closed = false
    private var responseStream: AsyncThrowingStream<Data, any Error>?
    private var heldSends: [CheckedContinuation<Void, any Error>] = []
    private var stallWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var didStall = false

    init(wrapping wrapped: InMemoryTransport, method: String) {
        self.wrapped = wrapped
        self.method = method
    }

    func connect() async throws {
        try await wrapped.connect()
        responseStream = await wrapped.receive()
    }

    func disconnect() async {
        closed = true
        let held = heldSends
        heldSends.removeAll()
        held.forEach { $0.resume(throwing: CancellationError()) }
        await wrapped.disconnect()
    }

    func send(_ data: Data) async throws {
        guard !closed else { throw MCPError.connectionClosed }
        let message = try JSONDecoder().decode([String: Value].self, from: data)
        if message["method"]?.stringValue == method {
            didStall = true
            let waiters = stallWaiters
            stallWaiters.removeAll()
            waiters.forEach { $0.resume() }
            try await withCheckedThrowingContinuation { heldSends.append($0) }
        }
        guard !closed else { throw MCPError.connectionClosed }
        try await wrapped.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, any Error> {
        responseStream ?? AsyncThrowingStream { $0.finish(throwing: MCPError.connectionClosed) }
    }

    func waitForStall() async {
        if didStall { return }
        await withCheckedContinuation { stallWaiters.append($0) }
    }
}
