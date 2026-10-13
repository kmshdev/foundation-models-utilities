import SettingsFeature
import RuntimeFeature
import IntegrationFeature
import StudioWorkflows
import StudioServices
import StudioUI
import EngineeringCore
import SwiftUI

struct StudioSheetView: View {
    let kind: StudioSheet
    let store: StudioStore
    let connections: ServiceConnections
    let chatGPT: ChatGPTConnection
    let runtime: DeveloperRuntimeConnection
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                switch kind {
                case .newOutcome: NewOutcomeView(store: store)
                case .team: RuntimeFeatureAPI.developers(runtime: runtime)
                case .settings: SettingsFeatureAPI.settings(store: store, connections: connections, chatGPT: chatGPT, runtime: runtime)
                case .connections: IntegrationFeatureAPI.connections(store: store, connections: connections)
                case .runtime: RuntimeFeatureAPI.configuration(runtime: runtime, account: chatGPT)
                }
            }
            .toolbar {
                if kind != .newOutcome {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 480, idealHeight: 620)
        #endif
    }
}
