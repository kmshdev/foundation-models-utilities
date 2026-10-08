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
                let store = StudioStore(preview: Workspace())
                try await capture(StudioRootView(store: store), name: "01-engineering", height: 820, output: output)
                try await capture(StudioRootView(store: store, initialSection: .team), name: "02-team", height: 1060, output: output)
                let plan = WorkPlan(summary: "Example assignment plan for the native engineering workspace. Preview data only.", tasks: [
                    WorkTask(id: "ui-01", title: "Build the engineering conversation", owner: .interface,
                             paths: ["Apps/EngineeringStudio/Features/EngineeringRoomView.swift"],
                             acceptance: ["Compose and save an outcome on iPhone and Mac.", "Keep text readable with larger Dynamic Type settings."],
                             dependencies: [], handoff: "Share the commit, changed view, accessibility checks and test results with the testing specialist."),
                    WorkTask(id: "qa-01", title: "Verify the outcome workflow", owner: .quality,
                             paths: ["Tests/EngineeringStudioUITests"],
                             acceptance: ["Verify persistence after relaunch and report any blockers."],
                             dependencies: ["ui-01"], handoff: "Provide the tested commit, reproducible test commands and results to integration.")
                ])
                try PlanValidator.validate(plan)
                try await capture(NavigationStack { PlanDetailView(plan: plan) }, name: "03-assignments", height: 1120, output: output)
                print("Captured three native SwiftUI previews. No model, developer or repository service was connected.")
                NSApp.terminate(nil)
            } catch {
                fputs("Screenshot capture failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private func capture<Content: View>(_ content: Content, name: String, height: CGFloat, output: URL) async throws {
        let root = VStack(spacing: 0) {
            HStack {
                Text("NATIVE SWIFTUI PREVIEW").font(.caption.monospaced().weight(.semibold))
                Spacer()
                Text("macOS 26 · Services disabled").font(.caption.monospaced())
            }
            .foregroundStyle(.white).padding(.horizontal, 20).padding(.vertical, 12)
            .background(Color.black)
            content
        }
        .frame(width: 1120, height: height)
        .preferredColorScheme(.light)
        .tint(StudioStyle.accent)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: height),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Engineering Studio — UI Preview"
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        try await Task.sleep(for: .seconds(2))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        // AppKit's view bitmap cache omits composited sidebar/control layers.
        // Capture the real window through macOS so those layers are included.
        let destination = output.appendingPathComponent(name + ".png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), destination.path]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0,
              let bitmap = NSBitmapImageRep(data: try Data(contentsOf: destination)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        print("Captured \(name): \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
        window.close()
    }
}
