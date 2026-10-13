import EngineeringCore
import Foundation

/// Arbitrates explicit requests against initial restoration and later creation.
/// A consumed link must not be replayed when a new outcome is appended.
struct WorkspaceRouting {
    private let preservesInitialSelection: Bool
    private var previous: WorkspaceRoutingInput?
    private var appliedRequestID: UUID?

    init(preservesInitialSelection: Bool = false) {
        self.preservesInitialSelection = preservesInitialSelection
    }

    mutating func resolve(_ input: WorkspaceRoutingInput, request: StudioDeepLink?,
                          outcomes: [Outcome]) -> WorkspaceRoutingAction {
        let previous = self.previous
        self.previous = input
        guard input.isLoaded else { return .none }

        if let requestID = input.requestID, requestID != appliedRequestID, let request {
            appliedRequestID = requestID
            guard let outcome = outcomes.first(where: { $0.id == request.outcomeID }) else {
                return .missingOutcome
            }
            let taskID = outcome.plan?.tasks.first(where: { $0.id == request.taskID })?.id
            return .select(outcomeID: outcome.id, taskID: taskID)
        }

        // Keep intentional one-time preview seeds, but select the latest outcome
        // during normal initial loading and after subsequent additions.
        if previous == nil, preservesInitialSelection { return .none }
        if previous?.isLoaded != true || previous?.latestOutcomeID != input.latestOutcomeID,
           let outcomeID = input.latestOutcomeID {
            return .select(outcomeID: outcomeID, taskID: nil)
        }
        return .none
    }
}
