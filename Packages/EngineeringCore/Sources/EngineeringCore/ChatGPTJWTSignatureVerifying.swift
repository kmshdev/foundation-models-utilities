import Foundation

/// The native verifier validates an RS256 signature with the selected issuer JWK.
public protocol ChatGPTJWTSignatureVerifying: Sendable {
    func verify(message: Data, signature: Data, modulus: Data, exponent: Data) throws -> Bool
}
