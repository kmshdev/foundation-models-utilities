import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
enum StudioSheet: String, Identifiable {
    case newOutcome, team, settings, connections, runtime
    var id: Self { self }
}
