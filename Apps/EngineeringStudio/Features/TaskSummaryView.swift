import EngineeringCore
import SwiftUI

struct TaskSummaryView: View {
    let tasks: [WorkTask]
    let selectedTaskID: String?
    let inspectTask: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType

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
                TaskSummaryRow(task: task, selected: selectedTaskID == task.id, compact: compact) {
                    inspectTask(task.id)
                }
            }
        }
    }
}

private struct TaskSummaryRow: View {
    let task: WorkTask
    let selected: Bool
    let compact: Bool
    let select: () -> Void

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
        .accessibilityLabel("\(task.title), \(task.owner.title), planned")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityHint("Show scope and handoff in task details")
    }
    private var owner: some View { Text(task.owner.displayName).foregroundStyle(.secondary) }
    private var status: some View { Label("Planned", systemImage: "circle.dashed").foregroundStyle(.secondary) }
}
