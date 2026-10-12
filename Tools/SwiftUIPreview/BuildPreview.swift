// Run with `swift Tools/SwiftUIPreview/BuildPreview.swift` using Xcode 27 / Swift 6.4.
// Builds a disposable screenshot host. Production project/SDK settings are not changed.
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
let sdk = try run(["--sdk", "macosx", "--show-sdk-path"], capture: true)
let compilerVersion = try run(["swift", "--version"], capture: true)
let macSDKVersion = try run(["--sdk", "macosx", "--show-sdk-version"], capture: true)
let iosSDKVersion = try run(["--sdk", "iphonesimulator", "--show-sdk-version"], capture: true)
guard compilerVersion.contains("Swift version 6.4"), macSDKVersion.hasPrefix("27."), iosSDKVersion.hasPrefix("27.") else {
    throw NSError(domain: "PreviewBuild", code: 1, userInfo: [NSLocalizedDescriptionKey:
        "Select Xcode 27 with Swift 6.4 and iOS/macOS 27 SDKs before capturing previews."])
}
print("Preview toolchain: \(compilerVersion); macOS SDK \(macSDKVersion); iOS SDK \(iosSDKVersion)")
#if arch(arm64)
let target = "arm64-apple-macos27.0"
#else
let target = "x86_64-apple-macos27.0"
#endif
let common = ["-sdk", sdk, "-target", target, "-swift-version", "6", "-D", "DEBUG"]
func sources(_ path: String) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent(path),
        includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
        throw CocoaError(.fileReadNoSuchFile)
    }
    return enumerator.compactMap { item -> String? in
        guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
        return url.path
    }.sorted()
}
let library = output.appendingPathComponent("libEngineeringCore.a").path
try run(["swiftc"] + common + ["-parse-as-library", "-emit-library", "-static", "-emit-module", "-module-name", "EngineeringCore",
        "-emit-module-path", output.appendingPathComponent("EngineeringCore.swiftmodule").path, "-o", library]
        + sources("Packages/EngineeringCore/Sources/EngineeringCore"))
let utilitiesSources = try sources("Apps/EngineeringStudio/Core/FoundationModelsUtilities")
let utilitiesFlags = ["-enable-experimental-feature", "InternalImportsByDefault",
                      "-enable-experimental-feature", "NonisolatedNonsendingByDefault",
                      "-enable-upcoming-feature", "MemberImportVisibility"]
try run(["swiftc"] + common + utilitiesFlags + ["-parse-as-library", "-emit-library", "-static", "-emit-module",
        "-module-name", "FoundationModelsUtilities", "-emit-module-path",
        output.appendingPathComponent("FoundationModelsUtilities.swiftmodule").path, "-o",
        output.appendingPathComponent("libFoundationModelsUtilities.a").path] + utilitiesSources)
let appSources = try sources("Apps/EngineeringStudio/Features") + sources("Apps/EngineeringStudio/Models")
    + sources("Apps/EngineeringStudio/Services")
// Check the shared views against the installed iOS SDK as well. This does not
// replace the production Swift 6.4 / SDK 27 build or execute the model service.
let iosOutput = output.appendingPathComponent("ios", isDirectory: true)
try FileManager.default.createDirectory(at: iosOutput, withIntermediateDirectories: true)
let iosSDK = try run(["--sdk", "iphonesimulator", "--show-sdk-path"], capture: true)
let iosCommon = ["-sdk", iosSDK, "-target", "arm64-apple-ios27.0-simulator", "-swift-version", "6", "-D", "DEBUG"]
try run(["swiftc"] + iosCommon + ["-parse-as-library", "-emit-module", "-module-name", "EngineeringCore",
        "-emit-module-path", iosOutput.appendingPathComponent("EngineeringCore.swiftmodule").path]
        + sources("Packages/EngineeringCore/Sources/EngineeringCore"))
try run(["swiftc"] + iosCommon + utilitiesFlags + ["-parse-as-library", "-emit-module", "-module-name", "FoundationModelsUtilities",
        "-emit-module-path", iosOutput.appendingPathComponent("FoundationModelsUtilities.swiftmodule").path] + utilitiesSources)
try run(["swiftc"] + iosCommon + ["-typecheck", "-parse-as-library", "-I", iosOutput.path] + appSources + [
        root.appendingPathComponent("Apps/EngineeringStudio/EngineeringStudioApp.swift").path])
try run(["swiftc"] + common + ["-typecheck", "-parse-as-library", "-I", output.path] + appSources + [
        root.appendingPathComponent("Apps/EngineeringStudio/EngineeringStudioApp.swift").path])
try run(["swiftc"] + common + ["-parse-as-library", "-I", output.path, "-L", output.path, "-lEngineeringCore", "-lFoundationModelsUtilities",
        "-o", executables.appendingPathComponent("SwiftUIPreview").path] + appSources + [
        root.appendingPathComponent("Tools/SwiftUIPreview/PreviewHost.swift").path,
        root.appendingPathComponent("Tools/SwiftUIPreview/StoreChecks.swift").path,
        root.appendingPathComponent("Tools/SwiftUIPreview/ServiceChecks.swift").path,
        root.appendingPathComponent("Tools/SwiftUIPreview/SubscriptionModelChecks.swift").path,
        root.appendingPathComponent("Tools/SwiftUIPreview/AuthenticationChecks.swift").path,
        root.appendingPathComponent("Tools/SwiftUIPreview/ChatGPTConnectionChecks.swift").path,
        root.appendingPathComponent("Tools/SwiftUIPreview/RemoteExecutionChecks.swift").path,
        root.appendingPathComponent("Tools/SwiftUIPreview/RuntimeConnectionChecks.swift").path])
try run(["actool", root.appendingPathComponent("Apps/EngineeringStudio/Assets.xcassets").path,
        "--compile", resources.path, "--platform", "macosx", "--minimum-deployment-target", "27.0"])
let info: [String: Any] = ["CFBundleExecutable": "SwiftUIPreview", "CFBundleIdentifier": "dev.kmsh.engineeringstudio.preview",
                         "CFBundleName": "Engineering Studio Preview", "CFBundlePackageType": "APPL",
                         "LSMinimumSystemVersion": "27.0", "NSHighResolutionCapable": true]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    .write(to: bundle.appendingPathComponent("Contents/Info.plist"))
print("Built native UI-only preview host at \(bundle.path)")
