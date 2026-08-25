// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacBrain",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacBrain", targets: ["MacBrain"])
    ],
    targets: [
        .executableTarget(
            name: "MacBrain",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("EventKit"),
                .linkedFramework("Contacts"),
                .linkedFramework("Photos"),
                .linkedFramework("PDFKit")
            ]
        ),
        .testTarget(name: "MacBrainTests", dependencies: ["MacBrain"])
    ]
)
