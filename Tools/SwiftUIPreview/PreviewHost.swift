import AppKit
import EngineeringCore
import SwiftUI

@main
struct PreviewHost {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = CaptureDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class CaptureDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                var workspace = Workspace()
                _ = try workspace.recordOutcome("Native navigation")
                _ = try workspace.recordOutcome("Model access")
                let outcomeID = try workspace.recordOutcome("Build coordinator")
                let plan = WorkPlan(summary: "Intake and ownership can proceed together.", tasks: [
                    WorkTask(id: "ui-01", title: "Outcome intake", owner: .interface,
                             paths: ["Apps/EngineeringStudio/Features/EngineeringRoomView.swift"],
                             acceptance: ["Save messages with the selected outcome."],
                             dependencies: [], handoff: "Share the conversation flow and accessibility checks with Testing."),
                    WorkTask(id: "core-01", title: "Task ownership", owner: .architecture,
                             paths: ["Packages/EngineeringCore/Sources/EngineeringCore/TaskOwnership.swift"],
                             acceptance: ["Assign one active owner to each task.", "Reject duplicate claims."],
                             dependencies: [], handoff: "Architecture → Testing. Share the ownership contract, changed files and test commands."),
                    WorkTask(id: "qa-01", title: "Handoff validation", owner: .quality,
                             paths: ["Tests/EngineeringStudioUITests"],
                             acceptance: ["Validate the ownership contract."],
                             dependencies: ["core-01"], handoff: "Provide reproducible test commands and results to Integration."),
                    WorkTask(id: "nav-01", title: "Native navigation", owner: .platforms,
                             paths: ["Apps/EngineeringStudio/Features/StudioRootView.swift"],
                             acceptance: ["Preserve selection as columns resize."],
                             dependencies: [], handoff: "Share Mac and iPhone navigation captures with Testing.")
                ])
                try workspace.attach(plan, to: outcomeID)
                workspace.messages = [
                    RoomMessage(author: .user, text: "Start with outcome intake and task ownership.", outcomeID: outcomeID),
                    RoomMessage(author: .coordinator, text: plan.summary, outcomeID: outcomeID)
                ]
                let store = StudioStore(preview: workspace)
                try await capture(StudioRootView(store: store, initialOutcomeID: outcomeID, initialTaskID: "core-01", initialDraft: "Prioritize handoff validation next."),
                                  name: "01-workspace", width: 1280, height: 858, output: output)
                try await capture(StudioRootView(store: store, initialOutcomeID: outcomeID, initialTaskID: "core-01"),
                                  name: "02-compact-workspace", width: 1100, height: 758, output: output)
                try await capture(StudioRootView(store: StudioStore(preview: Workspace())),
                                  name: "03-empty-workspace", width: 1280, height: 820, output: output)
                try await capture(StudioRootView(store: store, initialOutcomeID: outcomeID, initialTaskID: "core-01"),
                                  name: "04-increased-contrast", width: 1280, height: 858, output: output, highContrast: true)
                print("Captured real native SwiftUI views with preview data. Services disabled.")
                NSApp.terminate(nil)
            } catch {
                fputs("Screenshot capture failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private func capture<Content: View>(_ content: Content, name: String, width: CGFloat, height: CGFloat, output: URL, highContrast: Bool = false) async throws {
        let root = content
            .frame(width: width, height: height)
            .preferredColorScheme(.dark)
            .tint(.blue)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Engineering Studio — Preview data · Services disabled"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: highContrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        try await Task.sleep(for: .seconds(2))
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .seconds(1))
        print("Window active: \(NSApp.isActive), key: \(window.isKeyWindow), reduced transparency: \(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)")
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        window.makeFirstResponder(nil)
        let destination = output.appendingPathComponent(name + ".png")
        // Launch Services gives this app a real foreground window. The CI shell
        // performs screen capture using its existing screen-recording access.
        if CommandLine.arguments.contains("--external-capture") {
            try String(window.windowNumber).write(to: output.appendingPathComponent(name + ".window-id"), atomically: true, encoding: .utf8)
            for _ in 0..<150 {
                if FileManager.default.fileExists(atPath: destination.path) { break }
                try await Task.sleep(for: .milliseconds(200))
            }
        } else {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), destination.path]
            try capture.run()
            capture.waitUntilExit()
            guard capture.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: destination)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        print("Captured \(name): \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
        window.close()
    }
}
