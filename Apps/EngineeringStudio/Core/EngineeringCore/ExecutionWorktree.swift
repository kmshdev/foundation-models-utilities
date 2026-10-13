import Foundation

public struct ExecutionWorktree: Codable, Sendable, Equatable {
    public let url: URL
    public let branch: String
    public let baseSHA: String
    public init(url: URL, branch: String, baseSHA: String) { self.url = url; self.branch = branch; self.baseSHA = baseSHA }
}
