// swift-tools-version: 6.0
import PackageDescription

// `room-record`: records Room's window alone (ScreenCaptureKit, no system cursor) and the
// pointer's path and clicks beside it, so the website can draw its own cursor over the clip.
// Optionally plays a choreography (moves, clicks, drags, keys) so a recording can be redone.
let package = Package(
    name: "RoomRecorder",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "room-record", path: "Sources")
    ]
)
