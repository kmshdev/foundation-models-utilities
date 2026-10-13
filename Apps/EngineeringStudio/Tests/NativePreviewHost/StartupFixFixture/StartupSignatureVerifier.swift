import EngineeringCore
import Foundation

struct StartupSignatureVerifier: ChatGPTJWTSignatureVerifying {
    func verify(message: Data, signature: Data, modulus: Data, exponent: Data) -> Bool { false }
}
