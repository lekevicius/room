// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Card",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Card", targets: ["Card"])],
    dependencies: [.package(path: "../Design")],
    targets: [
        .target(name: "Card", dependencies: ["Design"], swiftSettings: mainActorByDefault),
        .testTarget(name: "CardTests", dependencies: ["Card"], swiftSettings: mainActorByDefault),
    ]
)
