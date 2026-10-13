import EngineeringCore
import Foundation
import FoundationModels
import FoundationModelsUtilities

@Generable
struct GeneratedPlan {
    var summary: String
    var tasks: [GeneratedAssignment]
    @Guide(description: "Only genuinely blocking questions. Return all of them together; none for preferences already supplied.")
    var questions: [GeneratedQuestion]
}
