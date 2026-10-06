// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

// The Library in the sidebar (Phase 4.1a, ⇧⌘L): Archive, Downloads and
// History as collapsible sections under a search field. AppKit rows.
let package = Package(
    name: "Library",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Library", targets: ["Library"])],
    dependencies: [
        .package(path: "../Design"),
        .package(path: "../Model"),
        .package(path: "../Store"),
        .package(path: "../UIKitCore"),
        .package(path: "../Chrome"),
        .package(path: "../Engine"),
    ],
    targets: [
        .target(name: "Library", dependencies: ["Design", "Model", "Store", "UIKitCore", "Chrome", "Engine"],
                swiftSettings: mainActorByDefault),
        .testTarget(name: "LibraryTests", dependencies: ["Library", "Model", "Engine"], swiftSettings: mainActorByDefault),
    ]
)
