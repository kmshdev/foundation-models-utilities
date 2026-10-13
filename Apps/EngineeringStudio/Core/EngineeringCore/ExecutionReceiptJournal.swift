import Foundation

/// Successful remote writes survive relaunch independently of worker availability.
public actor ExecutionReceiptJournal {
    private let url: URL
    private var receipts: [ExecutionPullRequestReceipt]?
    public init(url: URL) { self.url = url }
    public func load() throws -> [ExecutionPullRequestReceipt] {
        if let receipts { return receipts }
        guard FileManager.default.fileExists(atPath: url.path) else { receipts = []; return [] }
        let saved = try JSONDecoder().decode([ExecutionPullRequestReceipt].self, from: Data(contentsOf: url))
        guard saved.allSatisfy({ ExecutionRemoteReceiptValidation.matches($0, key: $0.key) }),
              Set(saved.map(\.executionID)).count == saved.count else { throw ExecutionPublicationError.invalidRecord }
        receipts = saved
        return saved
    }
    public func save(_ receipt: ExecutionPullRequestReceipt) throws {
        guard ExecutionRemoteReceiptValidation.matches(receipt, key: receipt.key) else { throw ExecutionPublicationError.invalidRecord }
        var values = try load()
        if let existing = values.first(where: { $0.executionID == receipt.executionID }) {
            guard existing == receipt else { throw ExecutionPublicationError.pullRequestConflict }
            return
        }
        values.append(receipt)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(values)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        receipts = values
    }
}
