import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct EngineeringStudioApp: App {
    @State private var store = StudioStore()
    @State private var connections = ServiceConnections()
    @State private var chatGPT = ChatGPTConnection()
    @State private var runtime = DeveloperRuntimeConnection()
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            StudioRootView(store: store, connections: connections, chatGPT: chatGPT, runtime: runtime)
                .task {
                    #if os(macOS)
                    appDelegate.store = store
                    appDelegate.runtime = runtime
                    #endif
                    runtime.configure(store: store, connections: connections)
                    await runtime.load()
                    chatGPT.configureBeforeAccountChange {
                        store.cancelPlanning()
                        if runtime.needsAccountDisconnect { await runtime.disconnect() }
                    }
                    store.configurePlanPrepared { outcome in runtime.enqueue(outcome, store: store) }
                    store.configureSubscriptionPlanner { outcome, answers in
                        try await FoundationPlanner.subscription(outcome: outcome, answers: answers,
                                                                 client: chatGPT.responsesClient,
                                                                 modelName: chatGPT.requireSelectedModel())
                    }
                    await store.load()
                    async let serviceLoad: Void = connections.load()
                    async let accountLoad: Void = chatGPT.load()
                    _ = await (serviceLoad, accountLoad)
                }
                .onChange(of: chatGPT.activeAccount?.id) { _, _ in store.cancelPlanning() }
                .onChange(of: chatGPT.selectedModel) { _, _ in store.cancelPlanning() }
                .onChange(of: chatGPT.isSignedIn) { _, signedIn in if !signedIn { store.cancelPlanning() } }
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
            NavigationStack {
                StudioSettingsView(store: store, connections: connections, chatGPT: chatGPT, runtime: runtime)
            }
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
    var runtime: DeveloperRuntimeConnection?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.isLoaded else { return .terminateNow }
        Task {
            let saved = await store.flushPendingChanges()
            if saved { await runtime?.disconnect() }
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
#endif
