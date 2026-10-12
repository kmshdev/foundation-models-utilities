import EngineeringServices
import EngineeringCore
import Foundation

/// Credentials belong to this installed app's Keychain, never workspace JSON.
@MainActor
package protocol ConnectionCredentialStore {
    func read(_ account: String) throws -> String?
    func write(_ value: String?, account: String) throws
}
