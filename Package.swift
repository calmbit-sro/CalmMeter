// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CalmMeter",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: models, API client, keychain, polling store.
        // Kept separate from the app target so it can be unit-tested.
        .target(
            name: "CalmMeterCore"
        ),
        // The SwiftUI menu-bar app. Thin; depends on Core.
        .executableTarget(
            name: "CalmMeter",
            dependencies: ["CalmMeterCore"]
        ),
        .testTarget(
            name: "CalmMeterCoreTests",
            dependencies: ["CalmMeterCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
