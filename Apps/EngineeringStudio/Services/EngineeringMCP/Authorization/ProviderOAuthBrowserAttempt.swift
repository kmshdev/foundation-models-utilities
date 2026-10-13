import Foundation

public struct ProviderOAuthBrowserAttempt: Sendable, Equatable {
    public let id: UUID
    public let redirectURI: URL

    public init(id: UUID = UUID(), redirectURI: URL) {
        self.id = id
        self.redirectURI = redirectURI
    }
}
