// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

// Room as a Mac app among others (ROADMAP 2.8 tasks 3–5): links handed to it
// by the system, the default-browser setting, the first run, and the two
// services that would talk to the network on their own (updates, crash
// reports), each behind the user's opt-in. `Integration` holds the rules and
// is what the tests build; `Updates` (Sparkle) and `CrashReports` (Sentry)
// are thin adapters the app links.
let package = Package(
    name: "Integration",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Integration", targets: ["Integration"]),
        .library(name: "Updates", targets: ["Updates"]),
        .library(name: "CrashReports", targets: ["CrashReports"]),
    ],
    dependencies: [
        .package(path: "../Model"),
        // Pinned exactly, as GRDB is; bump deliberately (PLAN §4 Distribution).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.30.0"),
    ],
    targets: [
        .target(name: "Integration", dependencies: ["Model"], swiftSettings: mainActorByDefault),
        .target(name: "Updates", dependencies: ["Integration", .product(name: "Sparkle", package: "Sparkle")],
                swiftSettings: mainActorByDefault),
        .target(name: "CrashReports", dependencies: ["Integration", .product(name: "Sentry", package: "sentry-cocoa")],
                swiftSettings: mainActorByDefault),
        .testTarget(name: "IntegrationTests", dependencies: ["Integration", "Model"], swiftSettings: mainActorByDefault),
    ]
)
