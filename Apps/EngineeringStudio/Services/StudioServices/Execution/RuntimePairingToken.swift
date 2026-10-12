import EngineeringServices
import EngineeringCore
import Foundation
import Security

package enum RuntimePairingToken {
    package static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ExecutionError.unavailable("A secure pairing code could not be created.")
        }
        let token = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        guard ExecutionRemoteLimits.validPairingToken(token) else { throw ExecutionRemoteError.invalidConfiguration }
        return token
    }
}
