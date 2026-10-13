import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct ExecutionResultRow: View {
    let record: ExecutionRecord
    var inspect: ((String) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.small) {
            if let inspect {
                Button { inspect(record.key.taskID) } label: {
                    Label(record.task.title, systemImage: record.task.owner.symbol)
                        .font(StudioTypography.heading).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Show this task’s scope, handoff and execution results")
            } else {
                Label(record.task.title, systemImage: record.task.owner.symbol)
                    .font(StudioTypography.heading)
            }
            metadata
            if !record.summary.isEmpty {
                Text(record.summary).font(StudioTypography.body).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let blocker = record.blocker, !blocker.isEmpty {
                Label(blocker, systemImage: "exclamationmark.triangle")
                    .font(StudioTypography.body).foregroundStyle(.orange).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let commit = record.commitSHA {
                Text("Local commit \(commit.prefix(12))")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    .help(commit).accessibilityLabel("Local commit \(commit)")
            }
            Text("Updated \(record.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                .font(StudioTypography.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, StudioSpacing.medium)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var metadata: some View {
        if dynamicType.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { owner; status }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: StudioSpacing.medium) { owner; status }
                VStack(alignment: .leading, spacing: 4) { owner; status }
            }
        }
    }

    private var owner: some View {
        Text(record.task.owner.title).font(StudioTypography.caption).foregroundStyle(.secondary)
    }
    private var status: some View {
        ExecutionStatusView(status: record.status).font(StudioTypography.caption)
    }
}
