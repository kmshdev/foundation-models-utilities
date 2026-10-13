import MCP

/// Uses the pinned SDK’s public PKCE helpers. S256 requires CryptoKit on Apple platforms.
public struct ProviderOAuthSDKCryptography: ProviderOAuthCryptography {
    public init() {}

    public func randomToken() throws -> String { PKCE.makeVerifier() }

    public func challenge(for verifier: String) throws -> String {
        do { return try PKCE.makeChallenge(from: verifier) }
        catch { throw ProviderOAuthError.tokenRejected }
    }
}
