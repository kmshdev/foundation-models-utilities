import Foundation

enum WorkspaceRoutingAction: Equatable {
    case none
    case select(outcomeID: UUID, taskID: String?)
    case missingOutcome
}
