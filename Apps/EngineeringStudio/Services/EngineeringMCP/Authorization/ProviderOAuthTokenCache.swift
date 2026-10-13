import Foundation
import Synchronization

/// A synchronous transport hook needs only a checked snapshot, not Keychain I/O or browser UI.
final class ProviderOAuthTokenCache: Sendable {
    private let value = Mutex<(token: String, expiresAt: Date?)?>(nil)

    func replace(with grant: ProviderOAuthStoredGrant?) {
        value.withLock { $0 = grant.map { ($0.accessToken, $0.expiresAt) } }
    }

    func token() -> String? {
        value.withLock { item in
            guard let item, item.expiresAt.map({ $0 > Date().addingTimeInterval(30) }) ?? true else { return nil }
            return item.token
        }
    }
}
