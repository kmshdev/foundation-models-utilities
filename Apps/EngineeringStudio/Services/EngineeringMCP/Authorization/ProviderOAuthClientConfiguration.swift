import Foundation

/// Protected configuration; never exported as application status or a workspace record.
struct ProviderOAuthClientConfiguration: Codable, Sendable {
    let clientID: String
    let clientSecret: String
}
