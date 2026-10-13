import MCP

/// SDK request tasks outlive the caller. Close the dedicated connection to ensure
/// they also finish if cancellation races pending-request registration or notification I/O.
/// Cancellation is advisory; it does not establish rollback of remote actions.
actor MCPRequestCancellation {
    let client: Client
    let requestID: ID?
    private(set) var resolution: MCPRequestResolution = .pending

    var didExceedDeadline: Bool { resolution == .timedOut }

    init(client: Client, requestID: ID? = nil) {
        self.client = client
        self.requestID = requestID
    }

    func cancel() async {
        // Explicit caller cancellation may supersede a completed response that has
        // not yet been returned to that caller. A losing timer may not do the same.
        guard resolution != .cancelled, resolution != .timedOut else { return }
        resolution = .cancelled
        await closeConnection()
    }

    func complete() -> Bool {
        guard resolution == .pending else { return false }
        resolution = .completed
        return true
    }

    private func closeConnection() async {
        await withTaskGroup(of: Void.self) { group in
            if let requestID {
                group.addTask { [client] in
                    try? await client.cancelRequest(requestID, reason: "Application request cancelled or timed out")
                }
            }
            group.addTask { [client] in await client.disconnect() }
        }
    }

    @discardableResult
    func timeOut() async -> Bool {
        guard resolution == .pending else { return false }
        resolution = .timedOut
        await closeConnection()
        return true
    }
}
