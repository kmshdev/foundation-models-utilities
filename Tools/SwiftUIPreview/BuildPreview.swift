// Run with `swift Tools/SwiftUIPreview/BuildPreview.swift` on macOS 26+.
// Builds a disposable screenshot host. Production project/SDK settings are not changed.
import Foundation

func run(_ arguments: [String], capture: Bool = false) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = arguments
    let pipe = Pipe()
    if capture { process.standardOutput = pipe }
    try process.run()
    let data = capture ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "PreviewBuild", code: Int(process.terminationStatus)) }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent(".preview-build", isDirectory: true)
let bundle = output.appendingPathComponent("SwiftUIPreview.app", isDirectory: true)
let executables = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let sdk = try run(["--sdk", "macosx", "--show-sdk-path"], capture: true)
#if arch(arm64)
let target = "arm64-apple-macos26.0"
#else
let target = "x86_64-apple-macos26.0"
#endif
let common = ["-sdk", sdk, "-target", target, "-swift-version", "6", "-D", "DEBUG"]
func sources(_ path: String) throws -> [String] {
    try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(path), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }.map(\.path).sorted()
}
let library = output.appendingPathComponent("libEngineeringCore.a").path
try run(["swiftc"] + common + ["-parse-as-library", "-emit-library", "-static", "-emit-module", "-module-name", "EngineeringCore",
        "-emit-module-path", output.appendingPathComponent("EngineeringCore.swiftmodule").path, "-o", library]
        + sources("Packages/EngineeringCore/Sources/EngineeringCore"))
let appSources = try sources("Apps/EngineeringStudio/Features") + sources("Apps/EngineeringStudio/Models")
try run(["swiftc"] + common + ["-parse-as-library", "-I", output.path, "-L", output.path, "-lEngineeringCore",
        "-o", executables.appendingPathComponent("SwiftUIPreview").path] + appSources + [
        root.appendingPathComponent("Tools/SwiftUIPreview/PreviewPlanner.swift").path,
        root.appendingPathComponent("Tools/SwiftUIPreview/PreviewHost.swift").path])
try run(["actool", root.appendingPathComponent("Apps/EngineeringStudio/Assets.xcassets").path,
        "--compile", resources.path, "--platform", "macosx", "--minimum-deployment-target", "26.0"])
let info: [String: Any] = ["CFBundleExecutable": "SwiftUIPreview", "CFBundleIdentifier": "dev.kmsh.engineeringstudio.preview",
                         "CFBundleName": "Engineering Studio Preview", "CFBundlePackageType": "APPL",
                         "LSMinimumSystemVersion": "26.0", "NSHighResolutionCapable": true]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
print("Built native UI-only preview host at \(bundle.path)")
