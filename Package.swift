// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopCorgi",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CorgiCore"),
        .executableTarget(name: "DesktopCorgi", dependencies: ["CorgiCore"]),
        .testTarget(name: "CorgiCoreTests", dependencies: ["CorgiCore"]),
    ]
)
