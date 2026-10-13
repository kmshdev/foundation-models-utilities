#if !os(Linux)
enum MCPHTTPResponseMode: Sendable {
    case json
    case sse
}
#endif
