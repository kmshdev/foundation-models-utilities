enum MCPRequestEvent<Output: Sendable>: Sendable {
    case result(Result<Output, any Error>)
    case timedOut
    case ignored
}
