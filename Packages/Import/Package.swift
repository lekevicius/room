// swift-tools-version: 6.2
import PackageDescription

// Import from other browsers (Phase 4.3a): readers as pure functions over
// `Data` or a copied file, and the planner that maps their values into Room's
// model. Not MainActor by default: the readers and the planner are Sendable
// and run off the main thread; the store applies the plan on the main actor.
let package = Package(
    name: "Import",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Import", targets: ["Import"])],
    dependencies: [
        .package(path: "../Model"),
        .package(path: "../Engine"),
        // The same pin as Model's (PLAN §4 Persistence): the other browser's SQLite is read through GRDB.
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        // Tests only: the end-to-end test applies a plan to a store.
        .package(path: "../Store"),
    ],
    targets: [
        .target(name: "Import", dependencies: ["Model", "Engine", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "ImportTests", dependencies: ["Import", "Model", "Engine", "Store"]),
    ]
)
