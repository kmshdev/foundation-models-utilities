import EngineeringCore
import StudioWorkflows
import SwiftUI
import WorkspaceFeature

/// Each WindowGroup instance owns navigation while sharing application services.
struct StudioWindow: View {
    let dependencies: StudioDependencies
    @State private var navigation = WorkspaceNavigation()

    init(dependencies: StudioDependencies) { self.dependencies = dependencies }

    var body: some View {
        WorkspaceFeatureAPI.workspace(dependencies: dependencies, navigation: navigation)
            .onOpenURL { url in
                if let route = StudioDeepLink(url: url) { navigation.activate(route) }
            }
    }
}
