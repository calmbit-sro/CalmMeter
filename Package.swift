// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: models, API client, keychain, polling store.
        // Kept separate from the app target so it can be unit-tested.
        .target(
            name: "ClaudeUsageCore"
        ),
        // The SwiftUI menu-bar app. Thin; depends on Core.
        .executableTarget(
            name: "ClaudeUsage",
            dependencies: ["ClaudeUsageCore"]
        ),
        .testTarget(
            name: "ClaudeUsageCoreTests",
            dependencies: ["ClaudeUsageCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
