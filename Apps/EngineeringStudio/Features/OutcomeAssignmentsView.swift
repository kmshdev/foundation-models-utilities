import EngineeringCore
import SwiftUI

struct OutcomeAssignmentsView: View {
    let outcomeID: UUID
    let tasks: [WorkTask]
    let selectedTaskID: String?
    let showsHandoff: Bool
    let runtime: DeveloperRuntimeConnection
    let inspectTask: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.section) {
            TaskSummaryView(tasks: tasks, selectedTaskID: selectedTaskID,
                            records: runtime.state.records.filter { $0.key.outcomeID == outcomeID },
                            inspectTask: inspectTask)
            if showsHandoff, let task = tasks.first(where: { $0.id == selectedTaskID }) {
                ProposedHandoffView(task: task, record: runtime.record(outcomeID: outcomeID, taskID: task.id))
            }
        }
    }
}
