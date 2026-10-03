#if DEBUG
import AppKit
import FakeEngine
import Model
import Sidebar
import Store
import UIKitCore

/// `Room -RoomSidebarFixture demo|500 -RoomSnapshotDirectory <dir>` (Debug
/// builds): captures the sidebar in the Phase 2.2a row states as
/// `phase-2.2a-*.png`, writes main-thread timings of sidebar updates to
/// `states.txt`, and quits.
enum SidebarSnapshotRunner {
    static func run(_ controller: RoomWindowController, sidebar: SidebarController, pages: SidebarPages, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var report: [String] = []
        let store = sidebar.store
        guard let space = sidebar.activeSpace else { return }
        // By fixture title or URL host (FakeEngine replaces live titles with the host).
        func entry(_ key: String) -> Entry? {
            store.sidebar.entries.values.first {
                $0.storedTitle == key || $0.customLabel == key || $0.currentURL.flatMap { URL(string: $0)?.host() } == key
            }
        }
        func state(_ name: String, dark: Bool) -> SnapshotRunner.State {
            SnapshotRunner.State(name: name, dark: dark, sidebarOpen: true, contentSize: NSSize(width: 1100, height: 760),
                                 sidebarWidth: 260, prefix: "phase-2.2a")
        }

        if SidebarFixtures.requested == "500" {
            report.append(await SnapshotRunner.captureActive(state("500-entries", dark: false), controller, directory))
            report += timings(sidebar: sidebar, store: store, space: space.id)
        } else {
            // Rows in their states: the selected pinned entry changed (dot;
            // hovered: reset icon + live title), a Today tab loaded and
            // audible, one loading, one unloaded; an essential loaded and changed.
            if let selected = sidebar.selectedEntryID { _ = selected; pages.navigateSelected() }
            if let tab = entry("en.wikipedia.org") {
                pages.debugLoad(tab.id)
                (pages.page(tab.id) as? FakeWebContents)?.simulateAudio(true)
            }
            if let tab = entry("www.swift.org") { pages.debugLoad(tab.id, stalled: true) }
            if let mail = entry("Mail") {
                pages.debugLoad(mail.id)
                (pages.page(mail.id) as? FakeWebContents)?.simulateLinkClick(to: URL(string: "https://mail.google.com/mail/u/0/#inbox/1")!)
            }
            if let hn = entry("Hacker News") { pages.debugLoad(hn.id) }
            sidebar.pageStateDidChange(Set(store.sidebar.entries.keys))
            report.append(await SnapshotRunner.captureActive(state("light-active", dark: false), controller, directory))
            report.append(await SnapshotRunner.captureActive(state("dark-active", dark: true), controller, directory))
            sidebar.debugHover(sidebar.selectedEntryID)
            report.append(await SnapshotRunner.captureActive(state("light-hover-changed", dark: false), controller, directory))
            if let tab = entry("en.wikipedia.org") { sidebar.debugHover(tab.id) }
            report.append(await SnapshotRunner.captureActive(state("light-hover-today", dark: false), controller, directory))
            sidebar.debugHover(nil)
            // Collapse "Reading" with the selection moved inside: the selected entry peeks.
            if let reading = entry("Reading"), let inner = entry("The Economist") {
                sidebar.select(inner.id)
                try? store.sidebar.setFolderCollapsed(reading.id, true)
            }
            sidebar.toasts?.show(.init(id: "copy-url", symbol: .copyURL, message: "Copied URL"))
            report.append(await SnapshotRunner.captureActive(state("light-collapsed-toast", dark: false), controller, directory,
                                                              settle: .milliseconds(1200)))
            sidebar.toasts?.show(.init(id: "renamed", symbol: .rename, message: "Tab renamed"))
            report.append(await SnapshotRunner.captureActive(state("dark-collapsed-toast", dark: true), controller, directory,
                                                              settle: .milliseconds(1200)))
        }
        try? report.joined(separator: "\n").appending("\n")
            .write(to: directory.appending(path: "states.txt"), atomically: true, encoding: .utf8)
    }

    /// Main-thread cost of sidebar updates on the 500-entry fixture, in ms.
    private static func timings(sidebar: SidebarController, store: RoomStore, space: UUID) -> [String] {
        let clock = ContinuousClock()
        func ms(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        func stats(_ name: String, _ samples: [Double]) -> String {
            let sorted = samples.sorted()
            let median = sorted[sorted.count / 2]
            let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
            return String(format: "%@: n=%d median=%.2f ms p95=%.2f ms max=%.2f ms", name, samples.count, median, p95, sorted.last ?? 0)
        }
        var lines = ["entries: \(store.sidebar.entries.count) rows: \(sidebar.debugOutline.numberOfRows)"]
        var samples: [Double] = []
        for _ in 0..<20 { samples.append(ms(clock.measure { sidebar.debugReloadAll() })) }
        lines.append(stats("full reload", samples))
        samples = []
        var added: [UUID] = []
        for index in 0..<50 {
            samples.append(ms(clock.measure {
                if let entry = try? store.sidebar.addEntry(.today, url: "https://new\(index).example", space: space, at: 100) {
                    added.append(entry.id)
                }
            }))
        }
        lines.append(stats("insert one Today tab (row animation started)", samples))
        samples = []
        for id in added { samples.append(ms(clock.measure { try? store.sidebar.rename(id, to: "Renamed") })) }
        lines.append(stats("rename one row (reconfigure)", samples))
        samples = []
        let today = store.sidebar.today(space: space)
        for entry in today.prefix(50) { samples.append(ms(clock.measure { sidebar.select(entry.id) })) }
        lines.append(stats("select (pill + markActive)", samples))
        samples = []
        for id in added { samples.append(ms(clock.measure { try? store.sidebar.remove(id) })) }
        lines.append(stats("remove one Today tab", samples))
        return lines
    }
}
#endif
