import Foundation

public protocol ProviderOAuthVault: Sendable {
    func read(_ record: ProviderOAuthVaultRecord, for identity: MCPConnectionIdentity) async throws -> Data?

    /// The implementation must put the actual atomic storage mutation inside transaction.commit.
    /// Waiting for a device lock or an injected storage delay must happen before that check.
    func write(_ data: Data?, record: ProviderOAuthVaultRecord, for identity: MCPConnectionIdentity,
               transaction: ProviderOAuthStorageTransaction) async throws
}
