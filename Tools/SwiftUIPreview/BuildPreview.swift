// Build the native regression/capture executable through the app's real module graph.
import Foundation

@discardableResult
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
let compilerVersion = try run(["swift", "--version"], capture: true)
let macSDKVersion = try run(["--sdk", "macosx", "--show-sdk-version"], capture: true)
let iosSDKVersion = try run(["--sdk", "iphonesimulator", "--show-sdk-version"], capture: true)
guard compilerVersion.contains("Swift version 6.4"), macSDKVersion.hasPrefix("27."), iosSDKVersion.hasPrefix("27.") else {
    throw NSError(domain: "PreviewBuild", code: 1, userInfo: [NSLocalizedDescriptionKey:
        "Select Xcode 27 with Swift 6.4 and iOS/macOS 27 SDKs before capturing previews."])
}
print("Preview toolchain: \(compilerVersion); macOS SDK \(macSDKVersion); iOS SDK \(iosSDKVersion)")
let packagePath = root.appendingPathComponent("Apps/EngineeringStudio").path
let scratchPath = output.appendingPathComponent("package").path
let build = ["swift", "build", "--package-path", packagePath, "--scratch-path", scratchPath,
             "--configuration", "debug", "--product", "EngineeringPreviewHost", "--jobs", "2",
             "-Xswiftc", "-enable-testing"]
try run(build)
let binaries = try run(["swift", "build", "--package-path", packagePath, "--scratch-path", scratchPath,
                        "--configuration", "debug", "--show-bin-path"], capture: true)
let source = URL(fileURLWithPath: binaries).appendingPathComponent("EngineeringPreviewHost")
let destination = executables.appendingPathComponent("SwiftUIPreview")
if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
try FileManager.default.copyItem(at: source, to: destination)
try run(["actool", root.appendingPathComponent("Apps/EngineeringStudio/App/Assets.xcassets").path,
         "--compile", resources.path, "--platform", "macosx", "--minimum-deployment-target", "27.0"])
let info: [String: Any] = ["CFBundleExecutable": "SwiftUIPreview", "CFBundleIdentifier": "dev.kmsh.engineeringstudio.preview",
                         "CFBundleName": "Engineering Studio Preview", "CFBundlePackageType": "APPL",
                         "LSMinimumSystemVersion": "27.0", "NSHighResolutionCapable": true]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
print("Built native capture host through compiler-enforced Core/Services/Workflows/Feature modules.")
