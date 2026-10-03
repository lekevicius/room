// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

// Browser-chrome surfaces outside the sidebar and card: toasts (Phase 2.2),
// popovers, dialogs and downloads (Phase 2.6).
let package = Package(
    name: "Chrome",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Chrome", targets: ["Chrome"])],
    dependencies: [.package(path: "../Design")],
    targets: [
        .target(name: "Chrome", dependencies: ["Design"], swiftSettings: mainActorByDefault),
        .testTarget(name: "ChromeTests", dependencies: ["Chrome"], swiftSettings: mainActorByDefault),
    ]
)
