import Foundation

/// A local authorization receipt. It is neither a verified person nor an initialized MCP session.
public struct ProviderOAuthAuthorizationReceipt: Sendable, Equatable {
    public let identity: MCPConnectionIdentity
    public let clientID: String
    public let scopes: Set<String>
    public let expiresAt: Date?
    public let refreshExpiresAt: Date?

    public init(identity: MCPConnectionIdentity, clientID: String, scopes: Set<String>,
                expiresAt: Date?, refreshExpiresAt: Date?) {
        self.identity = identity
        self.clientID = clientID
        self.scopes = scopes
        self.expiresAt = expiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }
}
