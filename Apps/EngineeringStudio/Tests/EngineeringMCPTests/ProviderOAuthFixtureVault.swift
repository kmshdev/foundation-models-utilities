import Foundation
import EngineeringMCP

actor ProviderOAuthFixtureVault: ProviderOAuthVault {
    private var values: [String: Data] = [:]
    private var blockedRecord: ProviderOAuthVaultRecord?
    private var gate: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var reached = false

    func read(_ record: ProviderOAuthVaultRecord, for identity: MCPConnectionIdentity) async throws -> Data? {
        values[key(record, identity)]
    }

    func write(_ data: Data?, record: ProviderOAuthVaultRecord, for identity: MCPConnectionIdentity,
               transaction: ProviderOAuthStorageTransaction) async throws {
        if blockedRecord == record {
            blockedRecord = nil; reached = true
            waiting?.resume(); waiting = nil
            await withCheckedContinuation { gate = $0 }
        }
        try transaction.commit { values[key(record, identity)] = data }
    }

    func blockNext(_ record: ProviderOAuthVaultRecord) { blockedRecord = record; reached = false }

    func waitForBlockedWrite() async {
        guard !reached else { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func releaseWrite() { gate?.resume(); gate = nil }

    private func key(_ record: ProviderOAuthVaultRecord, _ identity: MCPConnectionIdentity) -> String {
        "\(identity.provider.rawValue)|\(identity.accountID)|\(record.rawValue)"
    }
}
