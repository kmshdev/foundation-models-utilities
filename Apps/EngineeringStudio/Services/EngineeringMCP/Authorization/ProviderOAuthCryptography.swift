public protocol ProviderOAuthCryptography: Sendable {
    func randomToken() throws -> String
    func challenge(for verifier: String) throws -> String
}
