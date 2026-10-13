import Foundation

/// One adapter instance owns one provider/account connection for its entire lifetime.
public struct MCPConnectionIdentity: Hashable, Codable, Sendable {
    public let provider: MCPProvider
    public let accountID: String

    public var endpoint: URL { provider.endpoint }

    public init(provider: MCPProvider, accountID: String) throws {
        guard !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPClientError.invalidAccount
        }
        self.provider = provider
        self.accountID = accountID
    }
}
