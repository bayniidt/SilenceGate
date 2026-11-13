// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SilenceGate",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SilenceGate",
            path: "Sources/SilenceGate"
        )
    ],
    swiftLanguageVersions: [.v5]
)
