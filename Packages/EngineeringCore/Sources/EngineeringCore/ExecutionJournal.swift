import Foundation

/// Saves before publishing new state. A failed write never advances the ledger.
public actor ExecutionJournal: ExecutionJournalStoring {
    private let url: URL
    private var records: [ExecutionRecord]?
    public init(url: URL) { self.url = url }
    public func load() throws -> [ExecutionRecord] {
        if let records { return records }
        guard FileManager.default.fileExists(atPath: url.path) else { records = []; return [] }
        let decoded = try JSONDecoder().decode([ExecutionRecord].self, from: Data(contentsOf: url))
        guard Set(decoded.map(\.key)).count == decoded.count else { throw ExecutionError.persistenceFailed }
        records = decoded; return decoded
    }
    public func save(_ record: ExecutionRecord) throws {
        try saveBatch([record])
    }
    public func saveBatch(_ incoming: [ExecutionRecord]) throws {
        var next = try load()
        guard Set(incoming.map(\.key)).count == incoming.count else { throw ExecutionError.persistenceFailed }
        for record in incoming {
            if let index = next.firstIndex(where: { $0.key == record.key }) { next[index] = record }
            else { next.append(record) }
        }
        let data = try JSONEncoder().encode(next)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        records = next
    }
}
