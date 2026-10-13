import Foundation

/// Observed protocol/server capabilities, not inferred connection or model availability.
public struct MCPInitializationReceipt: Equatable, Sendable {
    public let identity: MCPConnectionIdentity
    public let protocolVersion: String
    public let serverName: String
    public let serverVersion: String
    public let supportsToolListChanges: Bool
    public let initializedAt: Date
}
