// swift-tools-version: 6.2
import PackageDescription

// Not MainActor by default: the values are Sendable and the database is
// written from the persistence queue, never from the main thread's hot path.
let package = Package(
    name: "Model",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Model", targets: ["Model"])],
    dependencies: [
        // Pinned exactly; bump deliberately (PLAN §4 Persistence).
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "Model", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "ModelTests", dependencies: ["Model", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
