// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Engine",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "Engine", targets: ["Engine"]),
        // Pure-Swift engine for unit tests and UI previews.
        .library(name: "FakeEngine", targets: ["FakeEngine"]),
    ],
    targets: [
        .target(name: "Engine", swiftSettings: mainActorByDefault),
        .target(name: "FakeEngine", dependencies: ["Engine"], swiftSettings: mainActorByDefault),
        .testTarget(name: "EngineTests", dependencies: ["Engine", "FakeEngine"], swiftSettings: mainActorByDefault),
    ]
)
