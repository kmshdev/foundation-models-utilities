import Foundation

enum MCPRequestDeadline {
    static func run<Output: Sendable>(
        duration: Duration,
        cancellation: MCPRequestCancellation,
        operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withThrowingTaskGroup(of: Output.self) { group in
                group.addTask { try await operation() }
                group.addTask {
                    try await Task.sleep(for: duration)
                    await cancellation.timeOut()
                    throw MCPClientError.deadlineExceeded
                }
                defer { group.cancelAll() }
                do {
                    guard let first = try await group.next() else {
                        throw CancellationError()
                    }
                    try Task.checkCancellation()
                    return first
                } catch {
                    if Task.isCancelled {
                        await cancellation.cancel()
                        throw CancellationError()
                    }
                    if await cancellation.didExceedDeadline {
                        throw MCPClientError.deadlineExceeded
                    }
                    throw error
                }
            }
        } onCancel: {
            // The handler is synchronous; its only task bridges to actor-owned cleanup.
            Task { @concurrent in await cancellation.cancel() }
        }
    }
}
