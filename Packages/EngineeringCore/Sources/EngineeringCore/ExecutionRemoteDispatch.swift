import Foundation

/// Only an outcome and its bounded work plan cross the bridge. The host owns its repository configuration.
public struct ExecutionRemoteDispatch: Codable, Sendable, Equatable {
    public let outcomeID: UUID
    public let outcome: String
    public let plan: WorkPlan

    public init(outcomeID: UUID, outcome: String, plan: WorkPlan) {
        self.outcomeID = outcomeID
        self.outcome = outcome
        self.plan = plan
    }
}
