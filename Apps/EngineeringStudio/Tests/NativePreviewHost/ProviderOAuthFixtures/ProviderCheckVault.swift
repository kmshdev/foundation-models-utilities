import EngineeringMCP
import Foundation

/// In-memory protected-record fixture. Every mutation honors the real
/// transaction fence, including a completion delayed beyond cancellation.
actor ProviderCheckVault: ProviderOAuthVault {
    let writeGate = ProviderCheckGate()
    private var records: [MCPConnectionIdentity: [String: Data]] = [:]
    private var rejectedRecord: ProviderOAuthVaultRecord?
    private var pendingTransaction: ProviderOAuthStorageTransaction?
    private(set) var readCount = 0
    private(set) var writeCount = 0
    private(set) var grantCommitCount = 0

    var counts: (reads: Int, writes: Int, grantCommits: Int) { (readCount, writeCount, grantCommitCount) }
    var pendingWriteIsInvalidated: Bool { pendingTransaction?.isActive == false }

    func read(_ record: ProviderOAuthVaultRecord, for identity: MCPConnectionIdentity) -> Data? {
        readCount += 1
        return records[identity]?[record.rawValue]
    }

    func write(_ data: Data?, record: ProviderOAuthVaultRecord, for identity: MCPConnectionIdentity,
               transaction: ProviderOAuthStorageTransaction) async throws {
        pendingTransaction = transaction
        defer { pendingTransaction = nil }
        await writeGate.waitIfSuspended()
        guard rejectedRecord != record else { throw ProviderOAuthError.secureStorageUnavailable }
        try transaction.commit {
            records[identity, default: [:]][record.rawValue] = data
            writeCount += 1
            if record == .grant, data != nil { grantCommitCount += 1 }
        }
    }

    func rejectWrites(to record: ProviderOAuthVaultRecord?) { rejectedRecord = record }

    func contains(_ record: ProviderOAuthVaultRecord, for identity: MCPConnectionIdentity) -> Bool {
        records[identity]?[record.rawValue] != nil
    }
}
