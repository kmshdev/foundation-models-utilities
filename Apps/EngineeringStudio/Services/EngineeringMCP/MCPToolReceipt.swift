import Foundation
import MCP

/// Actual read output. `isError` is preserved and must not be reported as success.
/// No access token or Authorization header is included in this application receipt.
public struct MCPToolReceipt: Sendable {
    public let identity: MCPConnectionIdentity
    public let requestID: ID
    public let toolName: String
    public let catalogRevision: UInt64
    public let completedAt: Date
    public let result: CallTool.Result
}
