import Foundation

struct ProviderOAuthRegistration: Codable, Sendable {
    let clientID: String
    let redirectURI: URL
}
