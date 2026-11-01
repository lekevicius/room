// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

// Room as a Mac app among others (ROADMAP 2.8 tasks 3–5): links handed to it
// by the system, the default-browser setting, the first run, and the two
// services that would talk to the network on their own (updates, crash
// reports), each behind the user's opt-in. `Integration` holds the rules and
// is what the tests build; `Updates` (Sparkle) is a thin adapter the app
// links. Crash reports are the engine's Crashpad (6.3: Sentry Cocoa went).
let package = Package(
    name: "Integration",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Integration", targets: ["Integration"]),
        .library(name: "Updates", targets: ["Updates"]),
    ],
    dependencies: [
        .package(path: "../Model"),
        // Pinned exactly, as GRDB is; bump deliberately (PLAN §4 Distribution).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "Integration", dependencies: ["Model"], swiftSettings: mainActorByDefault),
        .target(name: "Updates", dependencies: ["Integration", .product(name: "Sparkle", package: "Sparkle")],
                swiftSettings: mainActorByDefault),
        .testTarget(name: "IntegrationTests", dependencies: ["Integration", "Model"], swiftSettings: mainActorByDefault),
    ]
)
