import Foundation

public struct ExecutionGitReceipt: Sendable, Equatable {
    public let changedPaths: [String]
    public let commitSHA: String?
    public init(changedPaths: [String], commitSHA: String?) { self.changedPaths = changedPaths; self.commitSHA = commitSHA }
}
