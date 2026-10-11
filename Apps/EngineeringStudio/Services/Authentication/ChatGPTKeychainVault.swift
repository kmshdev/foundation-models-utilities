import Foundation
import Security
import EngineeringCore

/// One Keychain item makes rotating token and registration replacement atomic.
actor ChatGPTKeychainVault: ChatGPTCredentialVault {
    private let service: String
    private let account: String

    init(service: String = "dev.kmsh.engineeringstudio.chatgpt", account: String = "subscription-registrations") {
        self.service = service; self.account = account
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ChatGPTAuthenticationError.persistenceFailed }
    }

    func load() throws -> ChatGPTCredentialState? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw ChatGPTAuthenticationError.persistenceFailed }
        do { return try JSONDecoder().decode(ChatGPTCredentialState.self, from: data) }
        catch { throw ChatGPTAuthenticationError.persistenceFailed }
    }

    func save(_ state: ChatGPTCredentialState) throws {
        let data: Data
        do { data = try JSONEncoder().encode(state) } catch { throw ChatGPTAuthenticationError.persistenceFailed }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw ChatGPTAuthenticationError.persistenceFailed }
        let added = SecItemAdd(baseQuery.merging(attributes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
        guard added == errSecSuccess else { throw ChatGPTAuthenticationError.persistenceFailed }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
}
