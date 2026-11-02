// swift-tools-version: 6.2
import PackageDescription

// RoomCore is not a package dependency: scripts/roomcore-package.sh stages
// RoomCore.framework (our Chromium fork, built in the Chromium checkout) in
// build/roomcore; this package compiles against its Clang module there, or
// against the stage in ROOMCORE_STAGE (the script's --release build:
// build/roomcore-release, whose headers can be newer than the dev stage's, as
// at the 157 rebase). The app target (xcodegen/roomcore.yml) links and embeds
// the framework. CI never builds this package (xcodegen/ci.yml has no engine).
let stage = Context.environment["ROOMCORE_STAGE"] ?? (Context.packageDirectory + "/../../build/roomcore")

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
