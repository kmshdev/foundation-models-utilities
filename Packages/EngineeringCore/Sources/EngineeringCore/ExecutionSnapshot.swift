import Foundation

public struct ExecutionSnapshot: Codable, Sendable, Equatable {
    public let connected: Bool
    public let developers: [ExecutionDeveloperPresence]
    public let records: [ExecutionRecord]
    public let blocker: String?
    public let pullRequests: [ExecutionPullRequestReceipt]
    public init(connected: Bool, developers: [ExecutionDeveloperPresence], records: [ExecutionRecord], blocker: String?, pullRequests: [ExecutionPullRequestReceipt] = []) {
        self.connected = connected; self.developers = developers; self.records = records; self.blocker = blocker; self.pullRequests = pullRequests
    }
    private enum CodingKeys: String, CodingKey { case connected, developers, records, blocker, pullRequests }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        connected = try values.decode(Bool.self, forKey: .connected)
        developers = try values.decode([ExecutionDeveloperPresence].self, forKey: .developers)
        records = try values.decode([ExecutionRecord].self, forKey: .records)
        blocker = try values.decodeIfPresent(String.self, forKey: .blocker)
        pullRequests = try values.decodeIfPresent([ExecutionPullRequestReceipt].self, forKey: .pullRequests) ?? []
        guard pullRequests.allSatisfy({ receipt in
            ExecutionRemoteReceiptValidation.matches(receipt, key: receipt.key) &&
                records.contains { $0.id == receipt.executionID && $0.key == receipt.key && $0.commitSHA == receipt.localCommitSHA }
        }) else {
            throw DecodingError.dataCorruptedError(forKey: .pullRequests, in: values,
                                                   debugDescription: "Execution publication receipts must match their saved task and repository.")
        }
    }
}

