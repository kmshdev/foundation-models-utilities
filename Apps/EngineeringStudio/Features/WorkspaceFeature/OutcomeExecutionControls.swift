import RuntimeFeature
import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct OutcomeExecutionControls: View {
    let outcome: Outcome
    let store: StudioStore
    let runtime: DeveloperRuntimeConnection
    let openRuntime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.medium) {
            Label(runtime.outcomeStatus(outcome), systemImage: runtime.state.connected ? "terminal" : "network.slash")
                .font(StudioTypography.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !runtime.state.connected {
                RuntimeFeatureAPI.control(runtime: runtime, openRuntime: openRuntime)
                    .controlSize(.large)
            } else if !runtime.hasDelivered(outcome) {
                Button("Run Team", systemImage: "play.fill") { Task { await runtime.run(outcome, store: store) } }
                    .buttonStyle(.glassProminent).tint(.green).controlSize(.large)
                    .disabled(runtime.isDispatching || runtime.isControlling || runtime.isDisconnecting || store.isPlanning)
            }
            if let error = runtime.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }
}
