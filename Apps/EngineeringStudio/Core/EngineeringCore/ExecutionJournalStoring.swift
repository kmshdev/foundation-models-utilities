import Foundation

public protocol ExecutionJournalStoring: Sendable {
    func load() async throws -> [ExecutionRecord]
    func save(_ record: ExecutionRecord) async throws
    /// Production implementations must atomically reserve the complete batch.
    func saveBatch(_ records: [ExecutionRecord]) async throws
}
