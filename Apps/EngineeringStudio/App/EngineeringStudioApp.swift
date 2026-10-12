import EngineeringCore
import SettingsFeature
import StudioWorkflows
import SwiftUI
import WorkspaceFeature

@main
struct EngineeringStudioApp: App {
    @State private var dependencies = StudioDependencies()
    @State private var navigation = WorkspaceNavigation()
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            WorkspaceFeatureAPI.workspace(dependencies: dependencies, navigation: navigation)
                .task {
                    #if os(macOS)
                    appDelegate.dependencies = dependencies
                    #endif
                    await dependencies.start()
                }
                .onChange(of: dependencies.planningIdentity) { _, _ in dependencies.modelContextChanged() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { Task { await dependencies.flush() } }
                }
                .onOpenURL { url in
                    if let route = StudioDeepLink(url: url) { navigation.activate(route) }
                }
                #if os(macOS)
                .frame(minWidth: 1040, minHeight: 640)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 858)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        #endif

        #if os(macOS)
        Settings {
            NavigationStack { SettingsFeatureAPI.settings(dependencies: dependencies) }
                .frame(width: 560, height: 620)
        }
        #endif
    }
}
