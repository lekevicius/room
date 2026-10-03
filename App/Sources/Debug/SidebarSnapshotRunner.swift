#if DEBUG
import AppKit
import Design
import FakeEngine
import Model
import Sidebar
import Store
import UIKitCore

/// `Room -RoomSidebarFixture demo|500 -RoomSnapshotDirectory <dir>` (Debug
/// builds). `demo`: captures the sidebar's rows in every state (light and
/// dark, active and inactive, hover, ⌘-hover, rename, multi-selection,
/// keyboard focus, a drag in progress, Clear mid-animation, the overflow
/// indicator, the full and empty Essentials grid) as `phase-2.2b-*.png`,
/// cropped to the sidebar. `500`: one capture, main-thread timings of
/// sidebar updates and a scripted scroll measured frame by frame. Writes
/// `states.txt` and quits.
enum SidebarSnapshotRunner {
    static let prefix = "phase-2.2b"
    static let windowSize = NSSize(width: 1100, height: 760)
    static let sidebarWidth: CGFloat = 260

    static func run(_ controller: RoomWindowController, sidebar: SidebarController, pages: SidebarPages, into directory: URL) async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var report: [String] = []
        let store = sidebar.store
        guard let space = sidebar.activeSpace else { return }
        let shooter = Shooter(controller: controller, directory: directory)

        if SidebarFixtures.requested == "500" {
            report.append(await shooter.shot("500-entries", dark: false, crop: false))
            report += timings(sidebar: sidebar, store: store, space: space.id)
            report += await ScrollProbe(outline: sidebar.debugOutline).measure()
        } else {
            report += await rowStates(sidebar: sidebar, pages: pages, store: store, space: space, shooter: shooter)
        }
        try? report.joined(separator: "\n").appending("\n")
            .write(to: directory.appending(path: "states.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Row states (demo fixture)

    private static func rowStates(sidebar: SidebarController, pages: SidebarPages, store: RoomStore, space: Space,
                                  shooter: Shooter) async -> [String] {
        var report: [String] = []
        // By fixture title or URL host (FakeEngine replaces live titles with the host).
        func entry(_ key: String) -> Entry? {
            store.sidebar.entries.values.first {
                $0.storedTitle == key || $0.customLabel == key || $0.currentURL.flatMap { URL(string: $0)?.host() } == key
            }
        }
        func fake(_ key: String) -> FakeWebContents? { entry(key).flatMap { pages.page($0.id) as? FakeWebContents } }

        // Every row state at once: the selected pinned entry changed (dot), a
        // Today tab audible, one muted, one loading, unloaded rows, an
        // essential changed, another audible, two Today tabs multi-selected,
        // the keyboard focus ring on a pinned row.
        pages.navigateSelected()
        for key in ["en.wikipedia.org", "arc.net", "Mail", "GitHub", "Hacker News"] {
            if let id = entry(key)?.id { pages.debugLoad(id) }
        }
        if let id = entry("www.swift.org")?.id { pages.debugLoad(id, stalled: true) }
        fake("en.wikipedia.org")?.simulateAudio(true)
        fake("arc.net")?.simulateAudio(true)
        if let id = entry("arc.net")?.id { pages.setMuted(true, entry: id) }
        fake("GitHub")?.simulateAudio(true)
        fake("Mail")?.simulateLinkClick(to: URL(string: "https://mail.google.com/mail/u/0/#inbox/1")!)
        sidebar.pageStateDidChange(Set(store.sidebar.entries.keys))
        if let arc = entry("arc.net"), let zen = entry("zen-browser.app") {
            sidebar.debugToggleSelection(arc.id)
            sidebar.debugToggleSelection(zen.id)
        }
        sidebar.debugFocus(entry("Hacker News")?.id)
        report.append(await shooter.shot("rows-light-active", dark: false))
        report.append(await shooter.shot("rows-dark-active", dark: true))

        // Hover: changed row (live title as sublabel), over its reset icon,
        // the same with ⌘ held, a Today row (×).
        let selected = sidebar.selectedEntryID
        sidebar.debugHover(selected)
        report.append(await shooter.shot("hover-changed-light", dark: false))
        report.append(await shooter.shot("hover-changed-dark", dark: true))
        sidebar.debugHover(selected, onIcon: true)
        report.append(await shooter.shot("hover-reset-icon-light", dark: false))
        sidebar.debugHover(selected, onIcon: true, command: true)
        report.append(await shooter.shot("hover-reset-command-light", dark: false))
        sidebar.debugHover(entry("en.wikipedia.org")?.id)
        report.append(await shooter.shot("hover-today-light", dark: false))
        report.append(await shooter.shot("hover-today-dark", dark: true))
        sidebar.debugHover(nil)

        // Inline rename (cancelled afterwards, so nothing is renamed).
        if let id = entry("Hacker News")?.id {
            sidebar.beginRename(id)
            report.append(await shooter.shot("rename-light", dark: false))
            if let editor = sidebar.debugOutline.window?.firstResponder as? NSTextView {
                editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
            }
        }
        sidebar.debugFocus(entry("Hacker News")?.id)

        // The same rows in an inactive window (another window has main).
        report.append(await shooter.shotInactive("rows-light-inactive", dark: false))
        report.append(await shooter.shotInactive("rows-dark-inactive", dark: true))
        sidebar.debugFocus(nil)
        sidebar.debugClearMultiSelection()

        // A drag in progress: Literary Hub lifted over the top edge of Hacker
        // News (insertion line); a Today tab held over the middle of a folder.
        // (The lifted image is drawn for the appearance at drag start, as in a real drag.)
        if let lithub = entry("Literary Hub"), let hn = entry("Hacker News") {
            for dark in [false, true] {
                await shooter.prepare(dark: dark)
                sidebar.debugShowDrag([lithub.id], over: hn.id, fraction: 0.15)
                report.append(await shooter.shot("drag-insertion-\(dark ? "dark" : "light")", dark: dark))
            }
        }
        if let zen = entry("zen-browser.app"), let archive = entry("Archive") {
            await shooter.prepare(dark: false)
            sidebar.debugShowDrag([zen.id], over: archive.id, fraction: 0.5, held: true)
            report.append(await shooter.shot("drag-onto-folder-light", dark: false))
        }
        sidebar.debugShowDrag(nil)

        // Collapsed folder with the selection inside: the selected entry peeks.
        if let reading = entry("Reading"), let inner = entry("The Economist") {
            sidebar.select(inner.id)
            try? store.sidebar.setFolderCollapsed(reading.id, true)
            report.append(await shooter.shot("collapsed-peek-light", dark: false))
            report.append(await shooter.shot("collapsed-peek-dark", dark: true))
            try? store.sidebar.setFolderCollapsed(reading.id, false)
            if let selected { sidebar.select(selected) }
        }

        // Overflow: a short window scrolled so the selected row is above the list.
        if let scrollView = sidebar.debugOutline.enclosingScrollView {
            let short = NSSize(width: windowSize.width, height: 460)
            let outline = sidebar.debugOutline
            report.append(await shooter.shot("overflow-light", dark: false, size: short) {
                outline.scrollRowToVisible(outline.numberOfRows - 1)
            } + " outline=\(NSStringFromRect(outline.frame)) clip=\(NSStringFromRect(scrollView.contentView.bounds))")
            outline.scrollRowToVisible(0)
        }

        // Essentials: a full grid during a drag shows "12/12".
        var extra: [UUID] = []
        for index in 0..<(EntryRules.essentialsCap - store.sidebar.essentials(profile: space.profileID).count) {
            if let added = try? store.sidebar.addEntry(.essential, url: "https://example\(index).com", space: space.id) { extra.append(added.id) }
        }
        sidebar.debugShowEssentialsFull(true)
        report.append(await shooter.shot("essentials-full-light", dark: false))
        sidebar.debugShowEssentialsFull(false)
        for id in extra { _ = try? store.sidebar.remove(id) }

        // Clear mid-animation (slowed 8×), then the Undo toast.
        sidebar.debugSetClearSlowdown(8)
        await shooter.prepare(dark: false)
        sidebar.clearTodayTabs()
        try? await Task.sleep(for: .milliseconds(900))
        report.append(shooter.grab("clear-mid-light"))
        try? await Task.sleep(for: .milliseconds(2500))
        report.append(await shooter.shot("clear-toast-light", dark: false, settle: .milliseconds(900)))
        sidebar.debugSetClearSlowdown(1)

        // No essentials: the drop slot a drag reveals.
        for essential in store.sidebar.essentials(profile: space.profileID) {
            try? store.sidebar.move(essential.id, to: .today(space: space.id), at: 0)
        }
        sidebar.debugShowDropSlot(true)
        report.append(await shooter.shot("essentials-drop-slot-light", dark: false))
        sidebar.debugShowDropSlot(false)
        return report
    }

    // MARK: Timings (500 fixture)

    /// Main-thread cost of sidebar updates on the 500-entry fixture, in ms.
    private static func timings(sidebar: SidebarController, store: RoomStore, space: UUID) -> [String] {
        let clock = ContinuousClock()
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
        // A drop: one Today tab moved 200 rows up (the store move and the outline's remove + insert).
        for entry in today.suffix(50) {
            samples.append(ms(clock.measure { try? store.sidebar.move([entry.id], to: .today(space: space), insertingAt: 100) }))
        }
        lines.append(stats("drop: move one Today tab 200 rows", samples))
        samples = []
        let group = Array(today.prefix(10).map(\.id))
        for _ in 0..<20 {
            samples.append(ms(clock.measure { try? store.sidebar.move(group, to: .today(space: space), insertingAt: 300) }))
            try? store.sidebar.move(group, to: .today(space: space), insertingAt: 0)
        }
        lines.append(stats("drop: move a 10-tab group 300 rows", samples))
        samples = []
        for _ in 0..<50 { samples.append(ms(clock.measure { _ = store.sidebar.canMove(group, to: .pinned(space: space, folder: nil)) })) }
        lines.append(stats("drag validation (canMove, 10 tabs)", samples))
        samples = []
        for id in added { samples.append(ms(clock.measure { _ = try? store.sidebar.remove(id) })) }
        lines.append(stats("remove one Today tab", samples))
        return lines
    }

    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func stats(_ name: String, _ samples: [Double]) -> String {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return "\(name): no samples" }
        let median = sorted[sorted.count / 2]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return String(format: "%@: n=%d median=%.2f ms p95=%.2f ms max=%.2f ms", name, samples.count, median, p95, sorted.last ?? 0)
    }
}

/// Window captures cropped to the sidebar (plus the card's edge).
@MainActor
private final class Shooter {
    let controller: RoomWindowController
    let directory: URL

    init(controller: RoomWindowController, directory: URL) {
        self.controller = controller
        self.directory = directory
    }

    private var isFrontmost: Bool { NSApp.isActive && controller.window?.isMainWindow == true }

    /// Appearance, window size and sidebar width for the next capture.
    func prepare(dark: Bool, size: NSSize = SidebarSnapshotRunner.windowSize) async {
        guard let window = controller.window else { return }
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(size)
        controller.sidebarWidth = SidebarSnapshotRunner.sidebarWidth
        controller.isSidebarOpen = true
        window.layoutIfNeeded()
        window.displayIfNeeded()
    }

    /// An active-window capture (retried until the window stays main, as
    /// `SnapshotRunner.captureActive` does).
    func shot(_ name: String, dark: Bool, size: NSSize = SidebarSnapshotRunner.windowSize, settle: Duration = .milliseconds(700),
              crop: Bool = true, after prepared: () -> Void = {}) async -> String {
        var line = "\(name): not captured"
        for _ in 0..<40 {
            for _ in 0..<50 where !isFrontmost {
                NSApp.activate()
                controller.window?.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard isFrontmost else { continue }
            await prepare(dark: dark, size: size)
            prepared()
            try? await Task.sleep(for: settle)
            line = grab(name, crop: crop)
            if isFrontmost { break }
        }
        return line
    }

    /// The window inactive: a helper window of ours takes main.
    func shotInactive(_ name: String, dark: Bool) async -> String {
        let sink = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        sink.isReleasedWhenClosed = false
        defer { sink.close() }
        var line = "\(name): not captured"
        for _ in 0..<40 {
            sink.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(200))
            guard controller.window?.isMainWindow == false else { continue }
            await prepare(dark: dark)
            try? await Task.sleep(for: .milliseconds(700))
            line = grab(name)
            if controller.window?.isMainWindow == false { break }
        }
        return line
    }

    /// Captures now, without settling (mid-animation frames).
    func grab(_ name: String, crop: Bool = true) -> String {
        guard let window = controller.window, let image = WindowSnapshot.capture(window) else { return "\(name): no image" }
        var output = image
        if crop {
            let scale = window.backingScaleFactor
            let width = Int((SidebarSnapshotRunner.sidebarWidth + CardMetrics.inset * 3) * scale)
            output = image.cropping(to: CGRect(x: 0, y: 0, width: min(width, image.width), height: image.height)) ?? image
        }
        let url = directory.appending(path: "\(SidebarSnapshotRunner.prefix)-\(name).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return "\(name): cannot write"
        }
        CGImageDestinationAddImage(destination, output, nil)
        CGImageDestinationFinalize(destination)
        return "\(name): active=\(window.isMainWindow) dark=\(NSApp.appearance?.isDark == true) image=\(output.width)x\(output.height)"
    }
}

/// The 500-entry scroll check (ROADMAP 2.2 exit): the list is scrolled by a
/// display link at a fixed speed, bouncing between the ends; every frame
/// records the display link's frame interval (a late or skipped frame shows
/// as an interval over 1.5× nominal) and the main-thread cost of that frame's
/// scroll step including layout, drawing and the Core Animation commit
/// (which must stay under 8.33 ms for 120 Hz).
@MainActor
private final class ScrollProbe: NSObject {
    let outline: NSOutlineView
    private var link: CADisplayLink?
    private var began: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0
    private var intervals: [Double] = []
    private var work: [Double] = []
    private var nominal: Double = 0
    private var y: CGFloat = 0
    private var direction: CGFloat = 1
    private var speed: CGFloat = 0
    private var seconds: Double = 0
    private var continuation: CheckedContinuation<Void, Never>?

    init(outline: NSOutlineView) {
        self.outline = outline
    }

    /// Runs at 1500 / 4000 / 9000 pt/s (a steady scroll, a brisk one, a
    /// fling). `native`: the list moves speed × the display's frame time
    /// per frame. `proxy120`: it moves speed / 120 per frame, the step a
    /// 120 Hz panel asks for, so its cost is the 120 Hz per-frame cost on
    /// this 60 Hz display.
    func measure() async -> [String] {
        try? await Task.sleep(for: .seconds(1))
        _ = await run(speed: 3000, seconds: 1, label: "warm-up")
        var lines: [String] = []
        for speed in [1500.0, 4000.0, 9000.0] {
            lines.append(await run(speed: speed, seconds: 4, label: "native"))
            lines.append(await run(speed: speed, seconds: 4, label: "proxy120", step: 1.0 / 120))
        }
        return lines
    }

    /// Seconds of travel per frame (`nil`: the display's frame time).
    private var step: Double?

    private func run(speed: CGFloat, seconds: Double, label: String, step: Double? = nil) async -> String {
        self.step = step
        guard let scrollView = outline.enclosingScrollView else { return "scroll: no scroll view" }
        self.speed = speed
        self.seconds = seconds
        intervals = []
        work = []
        lastTimestamp = 0
        y = scrollView.contentView.bounds.minY
        direction = 1
        began = CACurrentMediaTime()
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let link = outline.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        let late = intervals.filter { $0 > nominal * 1.5 }.count
        let overBudget = work.filter { $0 > 1000.0 / 120 }.count
        let frame = SidebarSnapshotRunner.stats("frame interval", intervals)
        let cost = SidebarSnapshotRunner.stats("main-thread scroll step", work)
        return String(format: "scroll %@ %.0f pt/s for %.0f s, %d rows, display %.1f Hz: %@; late frames (>1.5× nominal) %d; %@; steps over 8.33 ms %d",
                      label, speed, seconds, outline.numberOfRows, nominal > 0 ? 1000 / nominal : 0, frame, late, cost, overBudget)
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let scrollView = outline.enclosingScrollView else { return }
        let start = CACurrentMediaTime()
        nominal = (link.targetTimestamp - link.timestamp) * 1000
        if lastTimestamp > 0 { intervals.append((link.timestamp - lastTimestamp) * 1000) }
        lastTimestamp = link.timestamp
        let clip = scrollView.contentView
        let maxY = max(0, outline.frame.height - clip.bounds.height)
        y += direction * speed * CGFloat(step ?? (link.targetTimestamp - link.timestamp))
        if y >= maxY { y = maxY; direction = -1 }
        if y <= 0 { y = 0; direction = 1 }
        clip.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(clip)
        outline.window?.displayIfNeeded()
        CATransaction.flush()
        work.append((CACurrentMediaTime() - start) * 1000)
        if start - began >= seconds {
            link.invalidate()
            self.link = nil
            continuation?.resume()
            continuation = nil
        }
    }
}
#endif
