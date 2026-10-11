import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct EngineeringStudioApp: App {
    @State private var store = StudioStore()
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            StudioRootView(store: store)
                .task {
                    #if os(macOS)
                    appDelegate.store = store
                    #endif
                    await store.load()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { Task { await store.flushPendingChanges() } }
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
            StudioSettingsView(store: store)
                .frame(width: 560, height: 620)
        }
        #endif
    }
}

#if os(macOS)
/// SwiftUI has no asynchronous quit callback. Defer normal Mac termination until
/// the latest workspace and drafts reach disk; a failure keeps the app open.
@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    var store: StudioStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.isLoaded else { return .terminateNow }
        Task {
            let saved = await store.flushPendingChanges()
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
#endif
