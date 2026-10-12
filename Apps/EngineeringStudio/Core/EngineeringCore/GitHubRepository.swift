import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubRepository: Codable, Sendable, Identifiable {
    public let id: Int
    public let fullName: String
    public let defaultBranch: String
    public let webURL: URL
    enum CodingKeys: String, CodingKey { case id, fullName = "full_name", defaultBranch = "default_branch", webURL = "html_url" }
}
