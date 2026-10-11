// Actual production-target launch smoke checks; no preview fixtures or service stubs.
import AppKit
import Foundation

@discardableResult
func run(_ executable: String, _ arguments: [String], capture: Bool = false) throws -> Data {
    FileHandle.standardOutput.write(Data("Running: \(executable) \(arguments.joined(separator: " "))\n".utf8))
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    if capture { process.standardOutput = pipe }
    try process.run()
    let output = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "NativeSmoke", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: "Failed: \(executable) \(arguments.joined(separator: " "))"])
    }
    return output
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let results = root.appendingPathComponent("Results/Launch")
try FileManager.default.createDirectory(at: results, withIntermediateDirectories: true)
let products = root.appendingPathComponent("DerivedData/Build/Products")
let macApp = products.appendingPathComponent("Debug/EngineeringStudioMac.app")
try run("/usr/bin/open", ["-n", macApp.path])
try await Task.sleep(for: .seconds(5))
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "dev.kmsh.engineeringstudio.mac" }) else {
    throw NSError(domain: "NativeSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mac app did not remain running"])
}
app.activate(options: [.activateAllWindows])
try await Task.sleep(for: .seconds(2))
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
guard let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }),
      let windowID = window[kCGWindowNumber as String] as? Int else {
    throw NSError(domain: "NativeSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mac app has no visible main window"])
}
try run("/usr/sbin/screencapture", ["-x", "-o", "-l", String(windowID), results.appendingPathComponent("macos-27.png").path])
print("Production Mac app launched with visible window \(windowID).")

let data = try run("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "--json"], capture: true)
let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
let runtimes = json?["devices"] as? [String: [[String: Any]]] ?? [:]
let devices = runtimes.filter { $0.key.contains("iOS-27") }.sorted { $0.key < $1.key }.flatMap(\.value)
guard let device = devices.first(where: { ($0["name"] as? String)?.contains("iPhone") == true }),
      let id = device["udid"] as? String else {
    throw NSError(domain: "NativeSmoke", code: 3, userInfo: [NSLocalizedDescriptionKey: "No available iOS 27 iPhone simulator"])
}
if device["state"] as? String != "Booted" { try run("/usr/bin/xcrun", ["simctl", "boot", id]) }
try run("/usr/bin/xcrun", ["simctl", "bootstatus", id, "-b"])
try run("/usr/bin/xcrun", ["simctl", "install", id, products.appendingPathComponent("Debug-iphonesimulator/EngineeringStudioiOS.app").path])
try run("/usr/bin/xcrun", ["simctl", "launch", "--terminate-running-process", id, "dev.kmsh.engineeringstudio"])
try await Task.sleep(for: .seconds(5))
try run("/usr/bin/xcrun", ["simctl", "io", id, "screenshot", results.appendingPathComponent("ios-27.png").path])
print("Production iOS app launch requested and simulator screenshot captured on \(id). Inspect the image for startup success.")
