import EngineeringCore
import SwiftUI

struct TaskSummaryRow: View {
    let task: WorkTask
    let selected: Bool
    let compact: Bool
    let record: ExecutionRecord?
    let select: () -> Void

    private var observedStatus: ExecutionRecord.Status? { record?.task == task ? record?.status : nil }

    var body: some View {
        Button(action: select) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: StudioSpacing.small) {
                        Text(task.title).font(StudioTypography.heading)
                        ViewThatFits(in: .horizontal) {
                            HStack { owner; Spacer(); status }
                            VStack(alignment: .leading, spacing: StudioSpacing.small) { owner; status }
                        }.font(StudioTypography.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: StudioSpacing.medium) {
                        Text(task.title).frame(maxWidth: .infinity, alignment: .leading)
                        owner.frame(width: 130, alignment: .leading)
                        status.frame(width: 108, alignment: .leading)
                    }.font(StudioTypography.body)
                }
            }
            .padding(.horizontal, StudioSpacing.standard).padding(.vertical, StudioSpacing.medium)
            .frame(minHeight: 44).contentShape(.rect)
            .background(selected ? StudioStyle.accent.opacity(0.12) : .clear)
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(StudioStyle.accent).frame(width: 3).accessibilityHidden(true) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title), \(task.owner.title), \(ExecutionStatusView.title(for: observedStatus))")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint("Show scope, handoff and execution results in task details")
    }

    private var owner: some View { Text(task.owner.displayName).foregroundStyle(.secondary) }
    private var status: some View { ExecutionStatusView(status: observedStatus) }
}
