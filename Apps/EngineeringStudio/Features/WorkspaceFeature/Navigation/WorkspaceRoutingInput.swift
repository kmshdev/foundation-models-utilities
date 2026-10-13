import Foundation

/// Restore and URL delivery are observed as one event, regardless of update order.
struct WorkspaceRoutingInput: Equatable {
    let isLoaded: Bool
    let latestOutcomeID: UUID?
    let requestID: UUID?
}
