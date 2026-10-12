import StudioWorkflows
import SwiftUI

@MainActor
public enum WorkspaceFeatureAPI {
    public static func workspace(dependencies: StudioDependencies, navigation: WorkspaceNavigation) -> some View {
        StudioRootView(store: dependencies.store, connections: dependencies.connections,
                       chatGPT: dependencies.chatGPT, runtime: dependencies.runtime, navigation: navigation)
    }
}
