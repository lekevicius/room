// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Store",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Store", targets: ["Store"])],
    dependencies: [.package(path: "../Model")],
    targets: [
        .target(name: "Store", dependencies: ["Model"], swiftSettings: mainActorByDefault),
        .testTarget(name: "StoreTests", dependencies: ["Store", "Model"], swiftSettings: mainActorByDefault),
    ]
)
