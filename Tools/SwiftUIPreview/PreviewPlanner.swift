// Compiled only by the isolated screenshot host, never by either app target.
// The host renders real screen source on the available macOS 26 runner without
// linking the unavailable SDK 27 Foundation Models integration.
import EngineeringCore
import Foundation

struct PlanningResult {
    let plan: WorkPlan?
    let questions: [Question]
}

@MainActor enum FoundationPlanner {
    static let availabilityDescription = "Disabled in screenshot preview"
    static func onDevice(outcome: String, answers: String) async throws -> PlanningResult {
        throw CocoaError(.featureUnsupported)
    }
}
