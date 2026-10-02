// swift-tools-version: 6.2
import PackageDescription

let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Design",
    platforms: [.macOS(.v26)],
    products: [.library(name: "Design", targets: ["Design"])],
    targets: [
        .target(name: "Design", resources: [.process("Resources")], swiftSettings: mainActorByDefault),
        .testTarget(name: "DesignTests", dependencies: ["Design"], swiftSettings: mainActorByDefault),
    ]
)
