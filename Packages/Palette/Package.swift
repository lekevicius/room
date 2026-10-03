// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Palette",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Palette", targets: ["Palette"])],
    dependencies: [
        .package(path: "../Design"),
        .package(path: "../Engine"),
        .package(path: "../Model"),
        .package(path: "../Store"),
        .package(path: "../Sidebar"),
        .package(path: "../Tabs"),
        .package(path: "../Omnibox"),
    ],
    targets: [
        .target(name: "Palette", dependencies: ["Design", "Engine", "Model", "Store", "Sidebar", "Tabs", "Omnibox"],
                swiftSettings: mainActorByDefault),
        .testTarget(name: "PaletteTests",
                    dependencies: ["Palette", "Engine", .product(name: "FakeEngine", package: "Engine"), "Model", "Store", "Sidebar",
                                   "Tabs", "Omnibox"],
                    swiftSettings: mainActorByDefault),
    ]
)
