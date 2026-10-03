// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Sidebar",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Sidebar", targets: ["Sidebar"])],
    dependencies: [
        .package(path: "../Design"),
        .package(path: "../Model"),
        .package(path: "../Store"),
        .package(path: "../Chrome"),
    ],
    targets: [
        .target(name: "Sidebar", dependencies: ["Design", "Model", "Store", "Chrome"], swiftSettings: mainActorByDefault),
        .testTarget(name: "SidebarTests", dependencies: ["Sidebar", "Store", "Model", "Chrome"], swiftSettings: mainActorByDefault),
    ]
)
