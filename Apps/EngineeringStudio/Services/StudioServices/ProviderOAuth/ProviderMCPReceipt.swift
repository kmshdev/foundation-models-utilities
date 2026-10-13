import EngineeringMCP
import Foundation

/// Observed server capabilities. This is not a verified user identity or an API write grant.
package struct ProviderMCPReceipt: Equatable, Sendable {
    package let identity: MCPConnectionIdentity
    package let serverName: String
    package let serverVersion: String
    package let protocolVersion: String
    package let toolCount: Int
    package let verifiedAt: Date

    package init(identity: MCPConnectionIdentity, serverName: String, serverVersion: String,
                 protocolVersion: String, toolCount: Int, verifiedAt: Date) {
        self.identity = identity
        self.serverName = serverName
        self.serverVersion = serverVersion
        self.protocolVersion = protocolVersion
        self.toolCount = toolCount
        self.verifiedAt = verifiedAt
    }
}
