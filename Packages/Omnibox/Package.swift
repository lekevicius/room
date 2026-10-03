// swift-tools-version: 6.2
import PackageDescription

// Pure suggestion logic (PLAN §2.2): providers, the scorer, URL fixup. Not
// MainActor by default: the values are Sendable, and 2.4b's history and
// suggest providers query off the main thread.
let package = Package(
    name: "Omnibox",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Omnibox", targets: ["Omnibox"])],
    dependencies: [
        .package(path: "../Model"),
    ],
    targets: [
        .target(name: "Omnibox", dependencies: ["Model"]),
        .testTarget(name: "OmniboxTests", dependencies: ["Omnibox", "Model"]),
    ]
)
