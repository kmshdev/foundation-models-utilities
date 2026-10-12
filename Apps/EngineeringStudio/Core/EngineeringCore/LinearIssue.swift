import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LinearIssue: Codable, Sendable, Identifiable {
    public let id: String
    public let identifier: String
    public let title: String
    public let description: String?
    public let priority: Int
    public let state: State
    public let webURL: URL
    public struct State: Codable, Sendable { public let name: String; public let type: String }
    enum CodingKeys: String, CodingKey { case id, identifier, title, description, priority, state, webURL = "url" }
}
