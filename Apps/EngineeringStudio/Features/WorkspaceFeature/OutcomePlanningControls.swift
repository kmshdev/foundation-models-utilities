import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct OutcomePlanningControls: View {
    let outcome: Outcome
    let store: StudioStore
    let openSettings: () -> Void
    private var waiting: Bool {
        store.workspace.questions.contains { $0.outcomeID == outcome.id && !$0.isComplete }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.medium) {
            if store.planningOutcomeID == outcome.id {
                HStack { ProgressView().controlSize(.small); Text("Preparing assignments…") }
                Button("Cancel Planning", systemImage: "stop.fill") { store.cancelPlanning() }
                    .buttonStyle(.glass).tint(.orange).controlSize(.large)
            } else if waiting {
                Label("Waiting for your answers", systemImage: "bubble.left.and.text.bubble.right")
            } else if store.isQueuedForPlanning(outcome.id) {
                Label("Planning queued", systemImage: "clock")
            } else if store.isPlanningEnabled {
                Button(outcome.plan == nil ? "Prepare Plan" : "Update Plan", systemImage: "play.fill") { store.plan(outcome) }
                    .buttonStyle(.glassProminent).tint(.green).controlSize(.large).disabled(store.isPlanning)
            } else {
                Text("Choose a model to prepare or update assignments.").foregroundStyle(.secondary)
                Button("Choose Planning Model", systemImage: "sparkles") { openSettings() }
                    .buttonStyle(.glass).controlSize(.large)
            }
        }
    }
}
