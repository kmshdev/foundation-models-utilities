import Foundation

struct ProviderOAuthPendingRefresh: Codable, Sendable {
    let token: String
    let startedAt: Date
}
