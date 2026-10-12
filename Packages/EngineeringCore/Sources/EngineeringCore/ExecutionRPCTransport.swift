import Foundation

/// A transport lifetime is separate from durable conversation and task identity.
public protocol ExecutionRPCTransport: Sendable {
    func start(accessToken: String?) async throws
    func request(method: String, params: ExecutionJSON) async throws -> ExecutionJSON
    func notify(method: String, params: ExecutionJSON) async throws
    func notifications() async -> AsyncStream<ExecutionNotification>
    func stop() async
}
