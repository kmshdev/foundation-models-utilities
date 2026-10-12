import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ServicePage<Item: Sendable>: Sendable {
    public let items: [Item]
    /// True means the bounded request stopped before the service's final page.
    public let isTruncated: Bool

    public init(items: [Item], isTruncated: Bool) {
        self.items = items
        self.isTruncated = isTruncated
    }
}
