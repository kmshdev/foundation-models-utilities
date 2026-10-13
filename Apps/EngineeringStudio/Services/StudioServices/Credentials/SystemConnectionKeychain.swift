import EngineeringServices
import EngineeringCore
import Foundation
import Security

@MainActor
package struct SystemConnectionKeychain: ConnectionCredentialStore {
    package init() {}
    package func read(_ account: String) throws -> String? {
        var query = identity(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return value
    }

    package func write(_ value: String?, account: String) throws {
        let query = identity(account)
        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess { throw KeychainError(status: status) }
    }

    private func identity(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "dev.kmsh.engineeringstudio.connections",
         kSecAttrAccount as String: account]
    }
    private struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "The connection credential could not be accessed securely (Keychain \(status))." }
    }
}
