// Launch production targets without preview fixtures or service stubs.
import Foundation
#if os(macOS)
import AppKit
import ImageIO
import Darwin
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
            FileHandle.standardError.write(Data("Native launch check failed: \(error)\n".utf8))
            exit(1)
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
        try runner.run("host-capacity", "/usr/sbin/sysctl", ["hw.memsize", "hw.ncpu"])
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
        var evidence: [String: Any] = [
            "commit": ProcessInfo.processInfo.environment["GITHUB_SHA"] ?? "local",
            "macProcessID": app.processIdentifier, "macWindowID": windowID,
            "images": [macImage.lastPathComponent], "verifiedPlatforms": ["macOS"],
            "usesProductionTargets": true
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: results.appendingPathComponent("launch-evidence.json"), options: .atomic)
        // Release the Mac UI before starting the simulator on small CI hosts.
        _ = app.terminate()
        for _ in 0..<5 {
            if app.isTerminated { break }
            try await Task.sleep(for: .seconds(1))
        }
        if !app.isTerminated { _ = app.forceTerminate() }

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
            _ = try? runner.run("shutdown-isolated-simulator", "/usr/bin/xcrun", ["simctl", "shutdown", deviceID], timeout: 20)
            _ = try? runner.run("delete-isolated-simulator", "/usr/bin/xcrun", ["simctl", "delete", deviceID], timeout: 20)
        }
        do {
            try runner.run("boot-simulator", "/usr/bin/xcrun", ["simctl", "boot", deviceID], timeout: 30)
            let developerDirectory: String
            if let selected = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
                developerDirectory = selected
            } else {
                developerDirectory = String(decoding: try runner.run("developer-directory", "/usr/bin/xcode-select", ["-p"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let developer = URL(fileURLWithPath: developerDirectory)
            let directories = [developer.appendingPathComponent("Applications"), developer.deletingLastPathComponent().appendingPathComponent("Applications"), URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications")]
            let applications = directories.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }.filter { $0.pathExtension == "app" }
            try Data(applications.map(\.path).sorted().joined(separator: "\n").utf8).write(to: results.appendingPathComponent("installed-apple-apps.txt"), options: .atomic)
            let matchingHosts = applications.filter {
                let name = $0.deletingPathExtension().lastPathComponent.lowercased().filter(\.isLetter)
                return name == "simulator" || name == "devicehub"
            }
            let selectedXcodeContents = developer.deletingLastPathComponent().resolvingSymlinksInPath().path + "/"
            let host = matchingHosts.first(where: { $0.resolvingSymlinksInPath().path.hasPrefix(selectedXcodeContents) }) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator") ?? matchingHosts.first
            guard let host else { throw NativeCommandError.invalidOutput("Simulator/Device Hub GUI host was not found; inspect installed-apple-apps.txt") }
            let arguments = host.lastPathComponent == "Simulator.app" ? [host.path, "--args", "-CurrentDeviceUDID", deviceID] : [host.path]
            try runner.run("open-simulator-host", "/usr/bin/open", arguments, timeout: 90)
            try runner.run("await-boot", "/usr/bin/xcrun", ["simctl", "bootstatus", deviceID, "-b"], timeout: 180)
            let iosApp = products.appendingPathComponent("Debug-iphonesimulator/EngineeringStudioiOS.app")
            try runner.run("install-ios", "/usr/bin/xcrun", ["simctl", "install", deviceID, iosApp.path], timeout: 120)
            let launch = try runner.run("launch-ios", "/usr/bin/xcrun", ["simctl", "launch", "--terminate-running-process", deviceID, "dev.kmsh.engineeringstudio"], timeout: 120)
            let launchText = String(decoding: launch, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pidText = launchText.split(separator: ":").last,
                  let pid = Int32(pidText.trimmingCharacters(in: .whitespaces)), pid > 0 else {
                throw NativeCommandError.invalidOutput("launch-ios process receipt")
            }
            try await Task.sleep(for: .seconds(5))
            let processData = try runner.run("ios-process-alive", "/bin/ps", ["-p", String(pid), "-o", "command="], timeout: 45)
            guard String(decoding: processData, as: UTF8.self).contains("EngineeringStudioiOS") else {
                throw NativeCommandError.invalidOutput("iOS app did not remain running")
            }
            let iosImage = results.appendingPathComponent("ios-27.png")
            try runner.run("ios-screenshot", "/usr/bin/xcrun", ["simctl", "io", deviceID, "screenshot", iosImage.path], timeout: 60)
            try verifyImage(iosImage)
            evidence["simulatorID"] = deviceID
            evidence["simulatorRuntime"] = runtime.key
            evidence["iosProcessID"] = pid
            evidence["iosInstalledBundleIdentifier"] = "dev.kmsh.engineeringstudio"
            evidence["images"] = [macImage.lastPathComponent, iosImage.lastPathComponent]
            evidence["verifiedPlatforms"] = ["macOS", "iOS"]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]).write(to: results.appendingPathComponent("launch-evidence.json"), options: .atomic)
            print("Production iOS app remains running as process \(pid) on isolated \(runtime.key). Inspect both screenshots for startup UI.")
        } catch {
            _ = try? runner.run("diagnostic-devices", "/usr/bin/xcrun", ["simctl", "list", "devices", "--json"], timeout: 15)
            _ = try? runner.run("diagnostic-simulator-processes", "/usr/bin/xcrun", ["simctl", "spawn", deviceID, "launchctl", "list"], timeout: 15)
            _ = try? runner.run("diagnostic-app-log", "/usr/bin/xcrun", ["simctl", "spawn", deviceID, "log", "show", "--last", "2m", "--style", "compact", "--predicate", "process == \"EngineeringStudioiOS\""], timeout: 20)
            _ = try? runner.run("diagnostic-host-processes", "/bin/ps", ["-axo", "pid,ppid,stat,etime,command"], timeout: 10)
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
