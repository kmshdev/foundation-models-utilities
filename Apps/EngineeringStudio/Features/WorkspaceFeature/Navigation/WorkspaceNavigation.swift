import EngineeringCore
import Foundation
import Observation

/// A feature navigation API lets the scene deliver a deep link without owning
/// the feature's column or task-selection implementation.
@MainActor @Observable
public final class WorkspaceNavigation {
    package private(set) var request: StudioDeepLink?
    package private(set) var requestID: UUID?
    public init() {}
    public func activate(_ route: StudioDeepLink) {
        request = route
        requestID = UUID()
    }
}
