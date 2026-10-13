import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct PlanPublishingControls: View {
    let outcome: Outcome
    let store: StudioStore
    let connections: ServiceConnections
    let openConnections: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if connections.hasLinearCredential {
                Button("Publish tasks to Linear", systemImage: "arrow.up.doc") {
                    Task { await connections.publishPlan(for: outcome, store: store) }
                }
                .disabled(connections.publishingOutcomeID != nil || store.isPlanning)
                if connections.publishingOutcomeID == outcome.id {
                    ProgressView(connections.publicationStatus ?? "Publishing…").controlSize(.small)
                }
                if connections.lastPublicationOutcomeID == outcome.id, let error = connections.publicationError {
                    Text(error).foregroundStyle(.red)
                }
            } else {
                Button("Connect Linear to publish tasks", systemImage: "link", action: openConnections)
            }
            if let plan = outcome.plan {
                let linkedCount = plan.tasks.filter {
                    store.issueBinding(outcomeID: outcome.id, taskID: $0.id)?.publishedTask == $0
                }.count
                if linkedCount > 0 {
                    Text("\(linkedCount) of \(plan.tasks.count) tasks published to Linear. Developer execution is separate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
