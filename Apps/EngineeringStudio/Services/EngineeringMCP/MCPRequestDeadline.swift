import Foundation

enum MCPRequestDeadline {
    static func run<Output: Sendable>(
        duration: Duration,
        cancellation: MCPRequestCancellation,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withThrowingTaskGroup(of: MCPRequestEvent<Output>.self) { group in
                group.addTask {
                    let result: Result<Output, any Error>
                    do { result = .success(try await operation()) }
                    catch { result = .failure(error) }
                    guard await cancellation.complete() else { return .ignored }
                    return .result(result)
                }
                group.addTask {
                    do { try await sleep(duration) }
                    catch { return .ignored }
                    return await cancellation.timeOut() ? .timedOut : .ignored
                }
                defer { group.cancelAll() }
                for try await event in group {
                    if Task.isCancelled {
                        await cancellation.cancel()
                        throw CancellationError()
                    }
                    switch event {
                    case .result(let result): return try result.get()
                    case .timedOut: throw MCPClientError.deadlineExceeded
                    case .ignored: continue
                    }
                }
                throw CancellationError()
            }
        } onCancel: {
            // The handler is synchronous; its only task bridges to actor-owned cleanup.
            Task { @concurrent in await cancellation.cancel() }
        }
    }
}
