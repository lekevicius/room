// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "UIKitCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "UIKitCore", targets: ["UIKitCore"])],
    dependencies: [
        .package(path: "../Design"),
        .package(path: "../Card"),
        // Tests only: a FakeEngine page in the card.
        .package(path: "../Engine"),
    ],
    targets: [
        .target(name: "UIKitCore", dependencies: ["Design", "Card"], swiftSettings: mainActorByDefault),
        .testTarget(
            name: "UIKitCoreTests",
            dependencies: ["UIKitCore", .product(name: "FakeEngine", package: "Engine")],
            swiftSettings: mainActorByDefault
        ),
    ]
)
