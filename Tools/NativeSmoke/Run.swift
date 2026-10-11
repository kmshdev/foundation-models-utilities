// Launch production targets without preview fixtures or service stubs.
import Foundation
#if os(macOS)
import AppKit
import ImageIO
#endif

@main
enum NativeSmoke {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let results = root.appendingPathComponent("Results/Launch")
        let selfTest = CommandLine.arguments.contains("--self-test")
        let runner = try NativeCommandRunner(directory: results.appendingPathComponent(selfTest ? "CommandChecks" : "Commands"))
        if selfTest {
            try checkCommandRunner(runner)
            return
        }
        #if os(macOS)
        do { try await captureApplications(root: root, results: results, runner: runner) }
        catch {
            try? Data("\(error)\n".utf8).write(to: results.appendingPathComponent("failure.txt"), options: .atomic)
            throw error
        }
        #else
        throw NativeCommandError.invalidOutput("Production launch capture requires macOS and Xcode 27")
        #endif
    }

    private static func checkCommandRunner(_ runner: NativeCommandRunner) throws {
        let output = try runner.run("large-output", "/bin/sh", ["-c", "head -c 1048576 /dev/zero; head -c 1048576 /dev/zero >&2"], timeout: 5)
        guard output.count == 1_048_576 else { throw NativeCommandError.invalidOutput("large-output") }
        do {
            try runner.run("nonzero-exit", "/bin/sh", ["-c", "printf 'expected failure' >&2; exit 17"], timeout: 5)
            throw NativeCommandError.invalidOutput("nonzero-exit was accepted")
        } catch NativeCommandError.failed(_, let status, _) where status == 17 { }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            try runner.run("deadline", "/bin/sh", ["-c", "trap '' TERM; while :; do :; done"], timeout: 0.2)
            throw NativeCommandError.invalidOutput("deadline did not stop the process")
        } catch NativeCommandError.timedOut { }
        guard ProcessInfo.processInfo.systemUptime - started < 4,
              runner.receipts.last?.timedOut == true,
              runner.receipts.last?.exitStatus != nil else {
            throw NativeCommandError.invalidOutput("deadline did not retain a terminated-process receipt")
        }
        print("Command checks passed: large stdout/stderr, nonzero exit, and SIGTERM-resistant deadline.")
    }

    #if os(macOS)
    @MainActor
    private static func captureApplications(root: URL, results: URL, runner: NativeCommandRunner) async throws {
        let products = root.appendingPathComponent("DerivedData/Build/Products")
        let macApp = products.appendingPathComponent("Debug/EngineeringStudioMac.app")
        try runner.run("toolchain", "/usr/bin/xcodebuild", ["-version"])
        try runner.run("swift-version", "/usr/bin/xcrun", ["swift", "--version"])
        try runner.run("simctl-help", "/usr/bin/xcrun", ["simctl", "help"])
        for subcommand in ["create", "bootstatus", "install", "launch", "spawn", "io"] {
            try runner.run("simctl-help-" + subcommand, "/usr/bin/xcrun", ["simctl", "help", subcommand])
        }
        try runner.run("open-mac", "/usr/bin/open", ["-n", macApp.path])
        try await Task.sleep(for: .seconds(5))
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "dev.kmsh.engineeringstudio.mac" }) else {
            throw NativeCommandError.invalidOutput("Mac app did not remain running")
        }
        app.activate(options: [.activateAllWindows])
        try await Task.sleep(for: .seconds(2))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let windowID = window[kCGWindowNumber as String] as? Int else {
            throw NativeCommandError.invalidOutput("Mac app has no visible main window")
        }
        let macImage = results.appendingPathComponent("macos-27.png")
        try runner.run("mac-screenshot", "/usr/sbin/screencapture", ["-x", "-o", "-l", String(windowID), macImage.path])
        try verifyImage(macImage)
        print("Production Mac app is running with visible window \(windowID).")

        let data = try runner.run("available-devices", "/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let runtimes = json?["devices"] as? [String: [[String: Any]]] ?? [:]
        let candidates = runtimes.filter { $0.key.contains("iOS-27") }.sorted { $0.key < $1.key }
        guard let runtime = candidates.first(where: { $0.value.contains(where: { ($0["name"] as? String)?.contains("iPhone") == true }) }),
              let device = runtime.value.first(where: { ($0["name"] as? String)?.contains("iPhone") == true }),
              let type = device["deviceTypeIdentifier"] as? String else {
            throw NativeCommandError.invalidOutput("No available iOS 27 iPhone simulator device type")
        }
        let created = try runner.run("create-isolated-simulator", "/usr/bin/xcrun", ["simctl", "create", "Engineering Studio smoke \(UUID().uuidString)", type, runtime.key])
        let deviceID = String(decoding: created, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: deviceID) != nil else { throw NativeCommandError.invalidOutput("create-isolated-simulator") }
        defer {
            try? runner.run("shutdown-isolated-simulator", "/usr/bin/xcrun", ["simctl", "shutdown", deviceID], timeout: 20)
            try? runner.run("delete-isolated-simulator", "/usr/bin/xcrun", ["simctl", "delete", deviceID], timeout: 20)
        }
        do {
            try runner.run("boot-simulator", "/usr/bin/xcrun", ["simctl", "boot", deviceID], timeout: 30)
            let developerDirectory: String
            if let selected = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
                developerDirectory = selected
            } else {
                developerDirectory = String(decoding: try runner.run("developer-directory", "/usr/bin/xcode-select", ["-p"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let applications = URL(fileURLWithPath: developerDirectory).appendingPathComponent("Applications")
            if let host = ["Simulator.app", "DeviceHub.app"].map({ applications.appendingPathComponent($0) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                let arguments = host.lastPathComponent == "Simulator.app" ? [host.path, "--args", "-CurrentDeviceUDID", deviceID] : [host.path]
                try runner.run("open-simulator-host", "/usr/bin/open", arguments)
            }
            try runner.run("await-boot", "/usr/bin/xcrun", ["simctl", "bootstatus", deviceID, "-b"], timeout: 180)
            let iosApp = products.appendingPathComponent("Debug-iphonesimulator/EngineeringStudioiOS.app")
            try runner.run("install-ios", "/usr/bin/xcrun", ["simctl", "install", deviceID, iosApp.path], timeout: 60)
            let container = try runner.run("installed-app-container", "/usr/bin/xcrun", ["simctl", "get_app_container", deviceID, "dev.kmsh.engineeringstudio", "app"])
            let launch = try runner.run("launch-ios", "/usr/bin/xcrun", ["simctl", "launch", "--terminate-running-process", deviceID, "dev.kmsh.engineeringstudio"], timeout: 45)
            let launchText = String(decoding: launch, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pidText = launchText.split(separator: ":").last,
                  let pid = Int32(pidText.trimmingCharacters(in: .whitespaces)), pid > 0 else {
                throw NativeCommandError.invalidOutput("launch-ios process receipt")
            }
            try await Task.sleep(for: .seconds(5))
            let processData = try runner.run("ios-process-alive", "/bin/ps", ["-p", String(pid), "-o", "command="])
            guard String(decoding: processData, as: UTF8.self).contains("EngineeringStudioiOS") else {
                throw NativeCommandError.invalidOutput("iOS app did not remain running")
            }
            let iosImage = results.appendingPathComponent("ios-27.png")
            try runner.run("ios-screenshot", "/usr/bin/xcrun", ["simctl", "io", deviceID, "screenshot", iosImage.path])
            try verifyImage(iosImage)
            let evidence: [String: Any] = [
                "commit": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local",
                "macProcessID": app.processIdentifier, "macWindowID": windowID,
                "simulatorID": deviceID, "simulatorRuntime": runtime.key,
                "iosProcessID": pid, "iosInstalledContainer": String(decoding: container, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                "images": [macImage.lastPathComponent, iosImage.lastPathComponent], "usesProductionTargets": true
            ]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: results.appendingPathComponent("launch-evidence.json"), options: .atomic)
            print("Production iOS app remains running as process \(pid) on isolated \(runtime.key). Inspect both screenshots for startup UI.")
        } catch {
            try? runner.run("diagnostic-devices", "/usr/bin/xcrun", ["simctl", "list", "devices", "--json"], timeout: 15)
            try? runner.run("diagnostic-simulator-processes", "/usr/bin/xcrun", ["simctl", "spawn", deviceID, "launchctl", "list"], timeout: 15)
            try? runner.run("diagnostic-app-log", "/usr/bin/xcrun", ["simctl", "spawn", deviceID, "log", "show", "--last", "2m", "--style", "compact", "--predicate", "process == \"EngineeringStudioiOS\""], timeout: 20)
            try? runner.run("diagnostic-host-processes", "/bin/ps", ["-axo", "pid,ppid,stat,etime,command"], timeout: 10)
            throw error
        }
    }

    private static func verifyImage(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 100, image.height > 100 else {
            throw NativeCommandError.invalidOutput("Screenshot \(url.lastPathComponent) is missing or invalid")
        }
    }
    #endif
}
