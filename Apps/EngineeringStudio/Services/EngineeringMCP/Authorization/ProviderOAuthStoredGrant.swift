import Foundation

/// One atomic record binds rotating tokens to the exact client, callback, resource and local slot.
struct ProviderOAuthStoredGrant: Codable, Sendable {
    let identity: MCPConnectionIdentity
    let clientID: String
    let redirectURI: URL
    let resource: URL
    let authorizationServer: URL
    let tokenEndpoint: URL
    let accessToken: String
    let scopes: Set<String>
    let expiresAt: Date?
    let refreshToken: String?
    let refreshExpiresAt: Date?
    var pendingRefresh: ProviderOAuthPendingRefresh?

    var receipt: ProviderOAuthAuthorizationReceipt {
        .init(identity: identity, clientID: clientID, scopes: scopes,
              expiresAt: expiresAt, refreshExpiresAt: refreshExpiresAt)
    }
}
