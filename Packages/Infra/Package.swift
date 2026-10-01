// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Infra",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Infra", targets: ["Infra"])],
    targets: [
        .target(name: "Infra"),
    ]
)
