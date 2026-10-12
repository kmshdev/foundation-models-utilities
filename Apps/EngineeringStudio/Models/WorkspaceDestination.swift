import Foundation

enum WorkspaceDestination: Hashable {
    case all, needsInput, outcome(UUID)
}
