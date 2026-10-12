import EngineeringCore
import Foundation
import FoundationModels
import FoundationModelsUtilities

@Generable
struct GeneratedAssignment {
    var id: String
    var title: String
    @Guide(description: "One of architecture, models, authentication, interface, platforms, cloud, quality, integration")
    var owner: String
    @Guide(description: "Exact relative file or directory paths. No globs or trailing slashes.")
    var paths: [String]
    var acceptance: [String]
    var dependencies: [String]
    @Guide(description: "What context, commit, tests and results the next developer needs.")
    var handoff: String
}
