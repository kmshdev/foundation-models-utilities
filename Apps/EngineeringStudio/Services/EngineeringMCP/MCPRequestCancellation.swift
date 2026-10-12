import MCP

/// SDK request tasks outlive the caller. Close the dedicated connection to ensure
/// they also finish if cancellation races pending-request registration or notification I/O.
/// Cancellation is advisory; it does not establish rollback of remote actions.
actor MCPRequestCancellation {
    let client: Client
    let requestID: ID?
    private var cancelled = false
    private(set) var didExceedDeadline = false

    init(client: Client, requestID: ID? = nil) {
        self.client = client
        self.requestID = requestID
    }

    func cancel() async {
        guard !cancelled else { return }
        cancelled = true
        await withTaskGroup(of: Void.self) { group in
            if let requestID {
                group.addTask { [client] in
                    try? await client.cancelRequest(requestID, reason: "Application request cancelled or timed out")
                }
            }
            group.addTask { [client] in await client.disconnect() }
        }
    }

    func timeOut() async {
        didExceedDeadline = true
        await cancel()
    }
}
