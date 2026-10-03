// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

// Browser-chrome surfaces outside the sidebar and card: toasts (Phase 2.2),
// the page's prompts, menus and file choosers (2.6a), downloads, find and
// the site panel (2.6b).
let package = Package(
    name: "Chrome",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Chrome", targets: ["Chrome"])],
    dependencies: [.package(path: "../Design"), .package(path: "../Engine")],
    targets: [
        .target(name: "Chrome", dependencies: ["Design", "Engine"], swiftSettings: mainActorByDefault),
        .testTarget(name: "ChromeTests",
                    dependencies: ["Chrome", "Engine", .product(name: "FakeEngine", package: "Engine")],
                    swiftSettings: mainActorByDefault),
    ]
)
