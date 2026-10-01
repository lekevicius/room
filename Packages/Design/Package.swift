// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Design",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Design", targets: ["Design"])],
    targets: [
        .target(name: "Design", swiftSettings: [.defaultIsolation(MainActor.self)]),
    ]
)
