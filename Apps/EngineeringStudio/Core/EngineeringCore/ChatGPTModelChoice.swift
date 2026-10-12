import Foundation

/// An account-specific model advertised for display by Sign in with ChatGPT.
public struct ChatGPTModelChoice: Decodable, Sendable, Equatable, Identifiable {
    public let slug: String
    public let displayName: String
    public let visibility: String
    public var id: String { slug }

    public init(slug: String, displayName: String, visibility: String = "list") {
        self.slug = slug
        self.displayName = displayName
        self.visibility = visibility
    }

    enum CodingKeys: String, CodingKey { case slug, displayName = "display_name", visibility }
}
