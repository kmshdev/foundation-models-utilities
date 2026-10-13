import StudioServices
import StudioWorkflows
import SwiftUI

@MainActor
public enum SettingsFeatureAPI {
    public static func settings(dependencies: StudioDependencies) -> some View {
        settings(store: dependencies.store, connections: dependencies.connections,
                 chatGPT: dependencies.chatGPT, runtime: dependencies.runtime)
    }

    package static func settings(store: StudioStore, connections: ServiceConnections,
                                 chatGPT: ChatGPTConnection, runtime: DeveloperRuntimeConnection) -> some View {
        StudioSettingsView(store: store, connections: connections, chatGPT: chatGPT, runtime: runtime)
    }
}
