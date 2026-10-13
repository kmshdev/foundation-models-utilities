/// Cryptographic primitives are supplied by the native platform, not approximated in portable code.
public protocol ChatGPTAuthorizationCryptography: Sendable {
    func randomToken() throws -> String
    func challenge(for verifier: String) throws -> String
}
