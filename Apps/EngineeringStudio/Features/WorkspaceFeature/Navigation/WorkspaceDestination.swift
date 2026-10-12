import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import Foundation

enum WorkspaceDestination: Hashable {
    case all, needsInput, outcome(UUID)
}
