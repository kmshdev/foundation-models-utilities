import Foundation

public struct ChatGPTAuthorizationAttempt: Sendable {
    public let authorizationURL: URL
    public let callbackURL: URL
    public let expiresAt: Date
    package let id: UUID
    package let state: String
    package let nonce: String
    package let verifier: String
    package let clientID: String?

    package init(authorizationURL: URL, callbackURL: URL, expiresAt: Date,
                 id: UUID, state: String, nonce: String, verifier: String, clientID: String?) {
        self.authorizationURL = authorizationURL
        self.callbackURL = callbackURL
        self.expiresAt = expiresAt
        self.id = id
        self.state = state
        self.nonce = nonce
        self.verifier = verifier
        self.clientID = clientID
    }
}
