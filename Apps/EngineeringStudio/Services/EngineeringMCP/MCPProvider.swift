import Foundation

/// Supported first-party remote MCP endpoints. Arbitrary URLs are not accepted.
public enum MCPProvider: String, Codable, Sendable {
    case github
    case linear

    public var endpoint: URL {
        switch self {
        case .github: URL(string: "https://api.githubcopilot.com/mcp/")!
        case .linear: URL(string: "https://mcp.linear.app/mcp/readonly")!
        }
    }
}
