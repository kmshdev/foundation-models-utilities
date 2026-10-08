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
        .defaultSize(width: 1120, height: 780)
        #endif
    }
}
