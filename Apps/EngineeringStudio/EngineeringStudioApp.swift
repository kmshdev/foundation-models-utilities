import SwiftUI

@main
struct EngineeringStudioApp: App {
    @State private var store = StudioStore()
    var body: some Scene {
        WindowGroup {
            StudioRootView(store: store)
                .task { await store.load() }
        }
        #if os(macOS)
        .defaultSize(width: 1440, height: 960)
        .windowToolbarStyle(.unified)
        .commands { SidebarCommands() }
        #endif
    }
}
