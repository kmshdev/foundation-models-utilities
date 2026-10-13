import Foundation

struct ProviderOAuthProtectedResource: Decodable, Sendable {
    let resource: URL
    let authorizationServers: [URL]
    let scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
    }
}
