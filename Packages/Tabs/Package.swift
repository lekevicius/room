// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Tabs",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Tabs", targets: ["Tabs"])],
    dependencies: [
        .package(path: "../Design"),
        .package(path: "../Engine"),
        .package(path: "../Model"),
        .package(path: "../Store"),
        .package(path: "../Sidebar"),
    ],
    targets: [
        .target(name: "Tabs", dependencies: ["Design", "Engine", "Model", "Store", "Sidebar"], resources: [.copy("Resources/public_suffix_list.dat")],
                swiftSettings: mainActorByDefault),
        .testTarget(name: "TabsTests",
                    dependencies: ["Tabs", "Engine", .product(name: "FakeEngine", package: "Engine"), "Model", "Store", "Sidebar"],
                    swiftSettings: mainActorByDefault),
    ]
)
