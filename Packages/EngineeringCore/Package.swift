// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "EngineeringCore",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [.library(name: "EngineeringCore", targets: ["EngineeringCore"])],
    targets: [
        .target(name: "EngineeringCore"),
        .testTarget(name: "EngineeringCoreTests", dependencies: ["EngineeringCore"])
    ],
    swiftLanguageModes: [.v6]
)
