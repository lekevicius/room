// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Engine",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Engine", targets: ["Engine"])],
    targets: [
        .target(name: "Engine", swiftSettings: [.defaultIsolation(MainActor.self)]),
    ]
)
