import Foundation

public struct ChatGPTTokenSet: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let idToken: String
    public let scopes: Set<String>
    public let expiresAt: Date
    public let earliestRefreshAt: Date?

    init(accessToken: String, refreshToken: String, idToken: String, scopes: Set<String>, expiresAt: Date, earliestRefreshAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.scopes = scopes
        self.expiresAt = expiresAt
        self.earliestRefreshAt = earliestRefreshAt
    }
}
