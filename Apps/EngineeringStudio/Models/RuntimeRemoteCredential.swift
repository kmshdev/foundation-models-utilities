import Foundation

/// This record is serialized only into protected Keychain storage.
struct RuntimeRemoteCredential: Codable {
    let origin: String
    let token: String
    let accessID: String
    let accessSecret: String
}
