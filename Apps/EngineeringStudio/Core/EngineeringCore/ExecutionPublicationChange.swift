import Foundation

/// A changed path read from immutable Git objects, never mutable worktree files.
public struct ExecutionPublicationChange: Sendable, Equatable {
    public let path: String
    public let mode: String
    /// Nil SHA and content represent a deletion from the verified base tree.
    public let blobSHA: String?
    public let content: Data?
    public init(path: String, mode: String, blobSHA: String?, content: Data?) {
        self.path = path; self.mode = mode; self.blobSHA = blobSHA; self.content = content
    }
}
