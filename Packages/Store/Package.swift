// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Store",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Store", targets: ["Store"]),
        // Kill -9 test of the persistence pipeline (Phase 2.1 exit criterion).
        .executable(name: "room-persistence-harness", targets: ["PersistenceHarness"]),
    ],
    dependencies: [.package(path: "../Model")],
    targets: [
        .target(name: "Store", dependencies: ["Model"], swiftSettings: mainActorByDefault),
        .executableTarget(name: "PersistenceHarness", dependencies: ["Store", "Model"]),
        .testTarget(name: "StoreTests", dependencies: ["Store", "Model"], swiftSettings: mainActorByDefault),
    ]
)
