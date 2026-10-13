import EngineeringMCP
import Foundation
import LocalAuthentication
import Security

/// Per-provider/slot protected records; complete rotating grants use one atomic Keychain replacement.
package final class ProviderOAuthKeychainVault: ProviderOAuthVault, Sendable {
    private let service: String

    package init(service: String = "dev.kmsh.engineeringstudio.provider-oauth") { self.service = service }

    package func read(_ record: ProviderOAuthVaultRecord, for identity: MCPConnectionIdentity) async throws -> Data? {
        var query = key(record, identity)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 65_536 else {
            throw ProviderOAuthError.secureStorageUnavailable
        }
        return data
    }

    package func write(_ data: Data?, record: ProviderOAuthVaultRecord, for identity: MCPConnectionIdentity,
                       transaction: ProviderOAuthStorageTransaction) async throws {
        try transaction.commit {
            let query = key(record, identity)
            guard let data else {
                let status = SecItemDelete(query as CFDictionary)
                guard status == errSecSuccess || status == errSecItemNotFound else {
                    throw ProviderOAuthError.secureStorageUnavailable
                }
                return
            }
            guard data.count <= 65_536 else { throw ProviderOAuthError.secureStorageUnavailable }
            let values = [kSecValueData as String: data] as CFDictionary
            let status = SecItemUpdate(query as CFDictionary, values)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                    throw ProviderOAuthError.secureStorageUnavailable
                }
            } else if status != errSecSuccess { throw ProviderOAuthError.secureStorageUnavailable }
        }
    }

    private func key(_ record: ProviderOAuthVaultRecord, _ identity: MCPConnectionIdentity) -> [String: Any] {
        let slot = Data(identity.accountID.utf8).base64EncodedString()
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "\(identity.provider.rawValue)|\(slot)|\(record.rawValue)",
                kSecAttrSynchronizable as String: false]
    }
}
