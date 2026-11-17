// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LidPulse",
    platforms: [.macOS("14.2")],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .executableTarget(name: "LidPulse", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "LidPulseTests", dependencies: ["LidPulse"])
    ]
)
