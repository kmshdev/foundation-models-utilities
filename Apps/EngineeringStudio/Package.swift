// swift-tools-version: 6.4
import PackageDescription

var products: [Product] = [
    .library(name: "EngineeringCore", targets: ["EngineeringCore"]),
    .library(name: "EngineeringServices", targets: ["EngineeringServices"]),
    .library(name: "EngineeringWorkflows", targets: ["EngineeringWorkflows"]),
    .library(name: "EngineeringMCP", targets: ["EngineeringMCP"])
]
var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")
]
var targets: [Target] = [
    .target(name: "EngineeringCore", path: "Core/EngineeringCore"),
    .target(name: "EngineeringServices", dependencies: ["EngineeringCore"], path: "Services/EngineeringServices"),
    .target(name: "EngineeringWorkflows", dependencies: ["EngineeringCore", "EngineeringServices"], path: "Workflows/EngineeringWorkflows"),
    .target(name: "EngineeringMCP", dependencies: [.product(name: "MCP", package: "swift-sdk")], path: "Services/EngineeringMCP"),
    .testTarget(name: "EngineeringSystemTests", dependencies: ["EngineeringCore", "EngineeringServices", "EngineeringWorkflows"],
                path: "Tests/EngineeringSystemTests"),
    .testTarget(name: "EngineeringMCPTests", dependencies: ["EngineeringMCP", .product(name: "MCP", package: "swift-sdk")],
                path: "Tests/EngineeringMCPTests")
]

// Linux validates portable contracts, services and workflows. Apple-only targets
// retain the required SDKs instead of substituting unavailable frameworks.
#if !os(Linux)
dependencies.append(.package(name: "FoundationModelsUtilitiesPackage", path: "../.."))
let utilities: Target.Dependency = .product(name: "FoundationModelsUtilities", package: "FoundationModelsUtilitiesPackage")
let nativeProducts = ["StudioUI", "StudioServices", "StudioWorkflows", "IntegrationFeature", "RuntimeFeature", "SettingsFeature", "WorkspaceFeature"]
products += nativeProducts.map { .library(name: $0, targets: [$0]) }
targets += [
    .target(name: "StudioUI", dependencies: ["EngineeringCore"], path: "Core/StudioUI"),
    .target(name: "StudioServices", dependencies: ["EngineeringCore", "EngineeringServices", "EngineeringMCP", utilities],
            path: "Services/StudioServices"),
    .target(name: "StudioWorkflows", dependencies: ["EngineeringCore", "EngineeringServices", "EngineeringWorkflows", "StudioServices"],
            path: "Workflows/StudioWorkflows"),
    .target(name: "IntegrationFeature", dependencies: ["EngineeringCore", "StudioUI", "StudioServices", "StudioWorkflows"],
            path: "Features/IntegrationFeature"),
    .target(name: "RuntimeFeature", dependencies: ["EngineeringCore", "StudioUI", "StudioServices", "StudioWorkflows"],
            path: "Features/RuntimeFeature"),
    .target(name: "SettingsFeature", dependencies: ["EngineeringCore", "StudioUI", "StudioServices", "StudioWorkflows", "IntegrationFeature", "RuntimeFeature"],
            path: "Features/SettingsFeature"),
    .target(name: "WorkspaceFeature", dependencies: ["EngineeringCore", "EngineeringWorkflows", "StudioUI", "StudioServices", "StudioWorkflows",
                                                   "IntegrationFeature", "RuntimeFeature", "SettingsFeature"],
            path: "Features/WorkspaceFeature")
]
#endif

#if os(macOS)
products.append(.executable(name: "EngineeringPreviewHost", targets: ["EngineeringPreviewHost"]))
targets.append(.executableTarget(name: "EngineeringPreviewHost",
    dependencies: ["EngineeringCore", "EngineeringServices", "EngineeringWorkflows", "EngineeringMCP", "StudioUI", "StudioServices", "StudioWorkflows", "IntegrationFeature", "WorkspaceFeature", utilities],
    path: "Tests/NativePreviewHost"))
#endif

let package = Package(name: "EngineeringStudio", platforms: [.iOS("27.0"), .macOS("27.0")],
                      products: products, dependencies: dependencies, targets: targets, swiftLanguageModes: [.v6])
