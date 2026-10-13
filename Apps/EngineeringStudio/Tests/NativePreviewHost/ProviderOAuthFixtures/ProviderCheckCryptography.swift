import CryptoKit
import EngineeringMCP
import Foundation

/// Native fixture uses real S256 but never accesses a credential or account.
struct ProviderCheckCryptography: ProviderOAuthCryptography {
    func randomToken() -> String { encode(Data(SHA256.hash(data: Data(UUID().uuidString.utf8)))) }
    func challenge(for verifier: String) -> String { encode(Data(SHA256.hash(data: Data(verifier.utf8)))) }

    private func encode(_ value: Data) -> String {
        value.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
