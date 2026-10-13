import MCP

public struct MCPToolCatalog: Sendable {
    public let identity: MCPConnectionIdentity
    public let revision: UInt64
    public let tools: [MCP.Tool]
}
