import Foundation

public struct ChatGPTAuthorizationAttempt: Sendable {
    public let authorizationURL: URL
    public let callbackURL: URL
    public let expiresAt: Date
    let id: UUID
    let state: String
    let nonce: String
    let verifier: String
    let clientID: String?
}
