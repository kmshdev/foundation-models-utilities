import Foundation

/// This record is serialized only into protected Keychain storage.
package struct RuntimeRemoteCredential: Codable {
    package let origin: String
    package let token: String
    package let accessID: String
    package let accessSecret: String

    package init(origin: String, token: String, accessID: String, accessSecret: String) {
        self.origin = origin
        self.token = token
        self.accessID = accessID
        self.accessSecret = accessSecret
    }
}
