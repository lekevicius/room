// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UIKitCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "UIKitCore", targets: ["UIKitCore"])],
    targets: [
        .target(name: "UIKitCore", swiftSettings: [.defaultIsolation(MainActor.self)]),
    ]
)
