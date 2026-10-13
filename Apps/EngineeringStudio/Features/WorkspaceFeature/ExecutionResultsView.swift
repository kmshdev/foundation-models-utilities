import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

/// Separates receipts for the current assignment from retained execution history.
struct ExecutionResultsView: View {
    let outcomeID: UUID
    let tasks: [WorkTask]
    let runtime: DeveloperRuntimeConnection
    var inspect: ((String) -> Void)? = nil

    private var records: [ExecutionRecord] {
        runtime.state.records.filter { $0.key.outcomeID == outcomeID }
    }
    private var currentRecords: [ExecutionRecord] {
        records.filter { tasks.contains($0.task) }
    }
    private var previousRecords: [ExecutionRecord] {
        records.filter { !tasks.contains($0.task) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.standard) {
            if !currentRecords.isEmpty {
                Text("Developer progress").font(StudioTypography.heading).accessibilityAddTraits(.isHeader)
                ForEach(currentRecords) { record in
                    ExecutionResultRow(record: record, inspect: inspect)
                }
            }
            if !previousRecords.isEmpty {
                DisclosureGroup("Previous executions") {
                    VStack(alignment: .leading, spacing: StudioSpacing.standard) {
                        Text("These receipts belong to earlier assignments and do not describe the current plan.")
                            .font(StudioTypography.caption).foregroundStyle(.secondary)
                        ForEach(previousRecords) { record in
                            ExecutionResultRow(record: record)
                        }
                    }.padding(.top, StudioSpacing.medium)
                }
                .font(StudioTypography.secondary)
            }
        }
    }
}
