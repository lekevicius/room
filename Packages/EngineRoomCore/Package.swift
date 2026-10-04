// swift-tools-version: 6.2
import PackageDescription

// RoomCore is not a package dependency: scripts/roomcore-package.sh stages
// RoomCore.framework (our Chromium fork, built in the Chromium checkout) in
// build/roomcore; this package compiles against its Clang module there. The
// app target (xcodegen/roomcore.yml) links and embeds the framework. CI never
// builds this package (xcodegen/ci.yml has no engine).
let stage = Context.packageDirectory + "/../../build/roomcore"

let package = Package(
    name: "EngineRoomCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EngineRoomCore", targets: ["EngineRoomCore"]),
    ],
    dependencies: [.package(path: "../Engine")],
    targets: [
        .target(
            name: "EngineRoomCore",
            dependencies: ["Engine"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .unsafeFlags(["-F", stage]),
            ],
            linkerSettings: [
                .unsafeFlags(["-F", stage]),
                .linkedFramework("RoomCore"),
            ]
        ),
    ]
)
