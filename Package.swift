// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchBrain",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchBrain", targets: ["NotchBrain"])
    ],
    targets: [
        .executableTarget(name: "NotchBrain"),
        .testTarget(name: "NotchBrainTests", dependencies: ["NotchBrain"])
    ]
)
