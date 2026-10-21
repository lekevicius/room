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
        // The window-tier accessibility audit (5.3a) assembles the window from every package above Palette.
        .package(path: "../UIKitCore"),
        .package(path: "../Library"),
        .package(path: "../Chrome"),
    ],
    targets: [
        .target(name: "Palette", dependencies: ["Design", "Engine", "Model", "Store", "Sidebar", "Tabs", "Omnibox"],
                swiftSettings: mainActorByDefault),
        .testTarget(name: "PaletteTests",
                    dependencies: ["Palette", "Engine", .product(name: "FakeEngine", package: "Engine"), "Model", "Store", "Sidebar",
                                   "Tabs", "Omnibox"],
                    swiftSettings: mainActorByDefault),
        // 5.3a: the browser window assembled from the packages (sidebar, header, footer, Essentials, card,
        // palette, toasts, the Library) on FakeEngine, its accessibility tree audited and its Tab order walked.
        .testTarget(name: "AccessibilityAuditTests",
                    dependencies: ["Palette", "Engine", .product(name: "FakeEngine", package: "Engine"), "Model", "Store", "Sidebar",
                                   "Tabs", "Design", "UIKitCore", "Library", "Chrome"],
                    swiftSettings: mainActorByDefault),
    ]
)
