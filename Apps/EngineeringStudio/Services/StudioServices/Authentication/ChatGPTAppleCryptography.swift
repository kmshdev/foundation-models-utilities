import EngineeringServices
import Foundation
import CryptoKit
import Security
import EngineeringCore

package struct ChatGPTAppleCryptography: ChatGPTAuthorizationCryptography {
    package func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ChatGPTAuthenticationError.invalidTokenResponse
        }
        return encode(Data(bytes))
    }

    package func challenge(for verifier: String) -> String { encode(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    private func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
