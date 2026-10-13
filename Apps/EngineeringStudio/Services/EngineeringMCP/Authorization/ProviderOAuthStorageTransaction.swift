import Synchronization

/// A cancellation fence shared with secure storage. A late write cannot recreate a disconnected grant.
public final class ProviderOAuthStorageTransaction: Sendable {
    private let active = Mutex(true)

    public init() {}

    public func invalidate() { active.withLock { $0 = false } }

    public var isActive: Bool { active.withLock { $0 } }

    /// The supplied synchronous mutation and its liveness check share one lock.
    public func commit<Value>(_ mutation: () throws -> Value) throws -> Value {
        try active.withLock { valid in
            guard valid else { throw ProviderOAuthError.canceled }
            return try mutation()
        }
    }
}
