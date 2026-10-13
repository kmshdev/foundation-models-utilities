import Foundation

public struct ExecutionPublicationSnapshot: Sendable, Equatable {
    public let commitSHA: String
    public let parentSHA: String
    public let treeSHA: String
    public let parentTreeSHA: String
    public let message: String
    public let author: ExecutionPublicationIdentity
    public let committer: ExecutionPublicationIdentity
    public let signature: String?
    public let changes: [ExecutionPublicationChange]
    public init(commitSHA: String, parentSHA: String, treeSHA: String, parentTreeSHA: String, message: String,
                author: ExecutionPublicationIdentity, committer: ExecutionPublicationIdentity, signature: String? = nil,
                changes: [ExecutionPublicationChange]) {
        self.commitSHA = commitSHA; self.parentSHA = parentSHA; self.treeSHA = treeSHA; self.parentTreeSHA = parentTreeSHA
        self.message = message; self.author = author; self.committer = committer; self.signature = signature; self.changes = changes
    }
}
