import Foundation

/// Local provenance and the actual remote commit are retained separately.
public struct ExecutionPullRequestReceipt: Codable, Sendable, Equatable, Identifiable {
    public let executionID: UUID
    public let key: ExecutionTaskKey
    public let pullRequestNumber: Int
    public let url: URL
    public let branch: String
    public let baseBranch: String
    public let remoteHeadSHA: String
    public let localCommitSHA: String
    public let remoteTreeSHA: String
    public var id: String { key.id }
    public init(executionID: UUID, key: ExecutionTaskKey, pullRequestNumber: Int, url: URL, branch: String,
                baseBranch: String, remoteHeadSHA: String, localCommitSHA: String, remoteTreeSHA: String) {
        self.executionID = executionID; self.key = key; self.pullRequestNumber = pullRequestNumber; self.url = url
        self.branch = branch; self.baseBranch = baseBranch; self.remoteHeadSHA = remoteHeadSHA
        self.localCommitSHA = localCommitSHA; self.remoteTreeSHA = remoteTreeSHA
    }
}
