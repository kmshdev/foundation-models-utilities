import EngineeringCore
import SwiftUI

struct TaskInspectorColumn: View {
    let task: WorkTask
    let outcomeID: UUID
    let store: StudioStore
    let runtime: DeveloperRuntimeConnection

    var body: some View {
        TaskDetailView(task: task, issueBinding: store.issueBinding(outcomeID: outcomeID, taskID: task.id),
                       record: runtime.record(outcomeID: outcomeID, taskID: task.id), runtime: runtime)
            .id(ExecutionTaskKey(outcomeID: outcomeID, taskID: task.id))
    }
}
