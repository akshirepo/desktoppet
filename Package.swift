// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopPet",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CorgiCore"),
        .executableTarget(name: "DesktopPet", dependencies: ["CorgiCore"]),
        .testTarget(name: "CorgiCoreTests", dependencies: ["CorgiCore"]),
    ]
)
