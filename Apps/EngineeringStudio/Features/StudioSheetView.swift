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
                case .team: TeamView(runtime: runtime)
                case .settings: StudioSettingsView(store: store, connections: connections, chatGPT: chatGPT, runtime: runtime)
                case .connections: ServiceConnectionsView(connections: connections, store: store)
                case .runtime: DeveloperRuntimeView(runtime: runtime, account: chatGPT)
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
