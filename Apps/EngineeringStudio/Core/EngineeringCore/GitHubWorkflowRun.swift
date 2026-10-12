import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubWorkflowRun: Codable, Sendable, Identifiable {
    public let id: Int
    public let name: String?
    public let status: String
    public let conclusion: String?
    public let headSHA: String
    public let webURL: URL
    enum CodingKeys: String, CodingKey { case id, name, status, conclusion, headSHA = "head_sha", webURL = "html_url" }
}
