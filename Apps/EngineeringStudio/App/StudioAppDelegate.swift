#if os(macOS)
import AppKit
import StudioWorkflows

/// Normal Mac termination waits for the workflow's durable save and shutdown.
@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    var dependencies: StudioDependencies?
    private var terminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let dependencies else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            let saved = await dependencies.prepareForTermination()
            terminating = false
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
#endif
