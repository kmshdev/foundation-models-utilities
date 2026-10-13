/// One terminal winner controls whether cleanup may close the dedicated connection.
enum MCPRequestResolution: Sendable {
    case pending
    case completed
    case cancelled
    case timedOut
}
