// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Card",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Card", targets: ["Card"])],
    targets: [
        .target(name: "Card", swiftSettings: [.defaultIsolation(MainActor.self)]),
    ]
)
