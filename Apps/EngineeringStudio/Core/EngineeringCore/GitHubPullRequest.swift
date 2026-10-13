import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubPullRequest: Codable, Sendable, Identifiable {
    public let id: Int
    public let number: Int
    public let title: String
    public let state: String
    public let isDraft: Bool
    public let webURL: URL
    public let head: Head
    public var headSHA: String { head.sha }
    public struct Head: Codable, Sendable { public let sha: String }
    enum CodingKeys: String, CodingKey { case id, number, title, state, head, isDraft = "draft", webURL = "html_url" }
}
