/// The existing host runtime implements these operations. Remote requests cannot change account or repository settings.
public protocol ExecutionRemoteHandler: Sendable {
    func snapshot() async throws -> ExecutionSnapshot
    func dispatch(_ request: ExecutionRemoteDispatch) async throws -> ExecutionSnapshot
    func cancel(_ key: ExecutionTaskKey) async throws -> ExecutionSnapshot
    func resume(_ key: ExecutionTaskKey) async throws -> ExecutionSnapshot
    func stop() async throws -> ExecutionSnapshot
    func restart() async throws -> ExecutionSnapshot
    func publish(_ key: ExecutionTaskKey) async throws -> ExecutionPullRequestReceipt
}

/// Older hosts fail explicitly for operations they do not implement.
extension ExecutionRemoteHandler {
    public func restart() async throws -> ExecutionSnapshot { throw ExecutionRemoteError.unsupportedRoute }
    public func publish(_ key: ExecutionTaskKey) async throws -> ExecutionPullRequestReceipt { throw ExecutionRemoteError.unsupportedRoute }
}
