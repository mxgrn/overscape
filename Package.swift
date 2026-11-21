// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Overscape",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Overscape", resources: [.copy("Resources/AppIcon.png")]),
        .testTarget(name: "OverscapeTests", dependencies: ["Overscape"]),
    ]
)
