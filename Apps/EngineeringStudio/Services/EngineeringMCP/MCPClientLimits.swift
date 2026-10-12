import Foundation

/// Application-level bounds supplement URLSession's network timeouts.
public struct MCPClientLimits: Sendable {
    public let requestDeadline: Duration
    public let initializationDeadline: Duration
    public let maximumCatalogPages: Int
    public let maximumCatalogTools: Int
    public let maximumArgumentsBytes: Int
    public let maximumResponseBytes: Int

    public init(requestDeadline: Duration = .seconds(30),
                initializationDeadline: Duration = .seconds(180),
                maximumCatalogPages: Int = 16,
                maximumCatalogTools: Int = 256,
                maximumArgumentsBytes: Int = 65_536,
                maximumResponseBytes: Int = 1_048_576) {
        self.requestDeadline = requestDeadline
        self.initializationDeadline = initializationDeadline
        self.maximumCatalogPages = maximumCatalogPages
        self.maximumCatalogTools = maximumCatalogTools
        self.maximumArgumentsBytes = maximumArgumentsBytes
        self.maximumResponseBytes = maximumResponseBytes
    }

    func validate() throws {
        guard requestDeadline > .zero, initializationDeadline > .zero,
              maximumCatalogPages > 0, maximumCatalogTools > 0,
              maximumArgumentsBytes > 0, maximumResponseBytes > 0 else {
            throw MCPClientError.invalidLimits
        }
    }
}
