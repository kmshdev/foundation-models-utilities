import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LinearProject: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let webURL: URL
    enum CodingKeys: String, CodingKey { case id, name, webURL = "url" }
}
