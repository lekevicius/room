import AppKit
import Testing
import Design
import Engine
import FakeEngine
@testable import UIKitCore

/// Window captures in every Phase 1.3 state, written as PNGs (to
/// `$ROOM_SNAPSHOT_DIR`, else a temporary directory) for review by eye
/// against `research/screenshots/dia-window.jpg`. No pixel assertions
/// (AGENTS.md "Testing"): the material depends on what is behind the window.
/// Test-process windows never become main, so "active" is forced with
/// `activityOverride` (the material and sidebar follow it; the traffic
/// lights stay grey).
@Suite("Window snapshots", .serialized, .tags(.window), .localOnly, .enabled("window capture unavailable") { await SnapshotSupport.canCapture })
struct WindowSnapshotTests {
    nonisolated struct State: CustomTestStringConvertible, Sendable {
        var dark: Bool
        var active: Bool
        var sidebarOpen: Bool
        var fakePage = false

        var name: String {
            [dark ? "dark" : "light", active ? "active" : "inactive", sidebarOpen ? "open" : "closed"]
                .joined(separator: "-") + (fakePage ? "-fake-engine-page" : "")
        }
        var testDescription: String { name }
    }

    nonisolated static let states: [State] = [true, false].flatMap { dark in
        [true, false].flatMap { active in
            [true, false].map { open in State(dark: dark, active: active, sidebarOpen: open) }
        }
    } + [State(dark: false, active: true, sidebarOpen: true, fakePage: true),
         State(dark: true, active: true, sidebarOpen: true, fakePage: true)]

    @Test("Window state", arguments: states)
    func snapshot(_ state: State) async throws {
        let size = NSSize(width: 1000, height: 640)
        let controller = RoomWindowController(contentSize: size)
        defer { controller.close() }
        let window = try #require(controller.window)
        window.appearance = NSAppearance(named: state.dark ? .darkAqua : .aqua)
        controller.spaceTitle = "Personal"
        controller.isSidebarOpen = state.sidebarOpen
        controller.activityOverride = state.active

        var page: (any WebContents)?
        if state.fakePage {
            let engine = FakeApplication()
            try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
            let contents = try engine.profile(named: "Default").createWebContents(WebContentsConfiguration())
            contents.load(URL(string: "https://example.com/")!, transition: .typed, fromAddressBar: true)
            controller.cardView.contentView = contents.nativeView
            if let background = contents.rootBackgroundColor { controller.cardView.backgroundColor = background }
            page = contents
        }

        window.orderFrontRegardless()
        window.layoutIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(400))

        let url = SnapshotSupport.directory.appending(path: "phase-1.3-test-\(state.name).png")
        try #require(try WindowSnapshot.writePNG(window, to: url) != nil, "no capture")
        withExtendedLifetime(page) {}
    }
}

enum SnapshotSupport {
    static let directory: URL = {
        let path = ProcessInfo.processInfo.environment["ROOM_SNAPSHOT_DIR"]
        let url = path.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appending(path: "room-snapshots", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    @MainActor static var canCapture: Bool { WindowSnapshot.isAvailable }
}
