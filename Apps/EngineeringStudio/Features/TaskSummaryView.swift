import EngineeringCore
import SwiftUI

struct TaskSummaryView: View {
    let tasks: [WorkTask]
    let selectedTaskID: String?
    let records: [ExecutionRecord]
    let inspectTask: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType

    init(tasks: [WorkTask], selectedTaskID: String?, records: [ExecutionRecord] = [], inspectTask: @escaping (String) -> Void) {
        self.tasks = tasks
        self.selectedTaskID = selectedTaskID
        self.records = records
        self.inspectTask = inspectTask
    }

    var body: some View {
        Group {
            if dynamicType.isAccessibilitySize { compactRows }
            else {
                ViewThatFits(in: .horizontal) {
                    wideRows.frame(minWidth: 500)
                    compactRows
                }
            }
        }
        .background(.thinMaterial, in: .rect(cornerRadius: StudioRadius.control))
        .compositingGroup().clipShape(.rect(cornerRadius: StudioRadius.control))
        .overlay { RoundedRectangle(cornerRadius: StudioRadius.control).strokeBorder(.primary.opacity(0.10)) }
        .accessibilityElement(children: .contain).accessibilityLabel("Assignment plan")
    }

    private var wideRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: StudioSpacing.medium) {
                Text("Task").frame(maxWidth: .infinity, alignment: .leading)
                Text("Owner").frame(width: 130, alignment: .leading)
                Text("Status").frame(width: 108, alignment: .leading)
            }.font(StudioTypography.secondary).foregroundStyle(.secondary)
                .padding(.horizontal, StudioSpacing.standard).frame(minHeight: 44)
            rows(compact: false)
        }
    }

    private var compactRows: some View {
        VStack(spacing: 0) { rows(compact: true) }
    }

    private func rows(compact: Bool) -> some View {
        ForEach(tasks) { task in
            VStack(spacing: 0) {
                Divider()
                TaskSummaryRow(task: task, selected: selectedTaskID == task.id, compact: compact,
                               record: records.first { $0.task == task }) {
                    inspectTask(task.id)
                }
            }
        }
    }
}
