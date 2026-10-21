#if DEBUG
import AppKit
import Design
import Engine
import Model
import Sidebar
import Store

/// `motion` (5.1a): the motion harness. Builds its own sidebar on an empty
/// throwaway state (two themed spaces, essentials, a folder, pinned entries
/// and Today tabs on the local test server :8766), then runs each named
/// sidebar animation through the code a click or a store change runs (the
/// sixth Essential starts a second row of tiles, so the list moves too), and
/// per animation records:
/// - the frames: a display link on the window (visible, key) from 150 ms
///   before the trigger until the animation's end; a frame the main thread
///   missed shows as an interval of two or more display intervals, and the
///   missed frames are counted against `display_frame_interval` (one less
///   than the interval's whole multiple of it);
/// - the trigger's own main-thread cost (`sync_ms`) and the first frame after it;
/// - what Core Animation was given: every animation on the window's layers
///   right after the trigger and on the next three frames, read back from
///   the layer (key path, duration, timing curve or the spring's perceptual
///   duration and bounce, begin offset), grouped by the view that owns it.
/// The main thread's frames are what our code can drop; the render server's
/// own frames are not visible here. A spike, never a test: timing is not an
/// assertion. `-RoomReduceMotion YES` runs it on the Reduce Motion variants.
/// `scripts/motion-check.sh` runs it on a throwaway state.
extension SpikeRunner.Context {
    func motionChecks() async {
        if UserDefaults.standard.bool(forKey: "RoomSuggestionsOff") { AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false } }
        let base = "http://127.0.0.1:8766/find.html"
        let screen = window.screen ?? NSScreen.main
        SpikeRunner.record("display", "\(screen?.localizedName ?? "none") max_fps=\(screen?.maximumFramesPerSecond ?? 0) "
            + "main=\(screen == NSScreen.screens.first) asleep=\(CGDisplayIsAsleep(CGMainDisplayID()) != 0)")
        SpikeRunner.record("window", "key=\(window.isKeyWindow) main=\(window.isMainWindow) visible=\(window.occlusionState.contains(.visible)) "
            + "frame=\(Int(window.frame.width))x\(Int(window.frame.height)) sidebar_width=\(Int(controller.sidebarWidth))")
        SpikeRunner.record("reduce_motion", Motion.reduceMotion)

        // The sidebar: built here so every row is a local page.
        guard let first = store.spaces.first else { return SpikeRunner.record("error", "motion: no space") }
        var fixture: MotionFixture
        do {
            fixture = try MotionFixture(store: store, first: first, base: base, window: sidebar.windowID)
        } catch {
            return SpikeRunner.record("error", "motion: fixture \(error)")
        }
        try? await Task.sleep(for: .seconds(1))
        sidebar.select(fixture.today[2])
        if let page = tabs.contents(for: fixture.today[2]) { await waitLoaded(page, timeout: 15) }
        _ = await waitUntil(10) { self.sidebar.debugPreparedSpaces == self.store.spaces.count }
        try? await Task.sleep(for: .seconds(1))
        await activate()

        guard let root = window.contentView else { return }
        let probe = MotionProbe(view: root)
        var rows: [MotionProbe.Result] = []
        func run(_ name: String, _ trigger: () -> Void) async {
            let result = await probe.measure(name, trigger: trigger)
            SpikeRunner.record("motion_\(name)", result.line)
            rows.append(result)
            try? await Task.sleep(for: .milliseconds(500))
        }

        // The pill follows its row as a row inserts above it, and as it leaves.
        var above: UUID?
        await run("pill_follow_insert") { above = try? store.addEntry(.today, url: "\(base)?above", title: "Above", space: first.id, at: 0).id }
        SpikeRunner.record("pill_after_insert", sidebar.debugPillAndRow.map { "pill y=\(Int($0.pill.minY)) row y=\(Int($0.row.minY))" } ?? "none")
        await run("pill_follow_remove") { if let above { _ = try? store.remove(above) } }
        // A Today tab below the selection: the rows' own insert and remove.
        var below: UUID?
        let count = store.today(space: first.id).count
        await run("row_insert") { below = try? store.addEntry(.today, url: "\(base)?below", title: "Below", space: first.id, at: count).id }
        await run("row_remove") { if let below { _ = try? store.remove(below) } }

        // The folder with its selected child peeking out of it (spec §A.6).
        sidebar.select(fixture.folderChildren[1])
        if let page = tabs.contents(for: fixture.folderChildren[1]) { await waitLoaded(page, timeout: 15) }
        try? await Task.sleep(for: .milliseconds(400))
        await run("folder_collapse_peek") { try? store.setFolderCollapsed(fixture.folder, true) }
        SpikeRunner.record("folder_rows_collapsed", sidebar.debugRowKinds.joined(separator: ","))
        await run("folder_expand") { try? store.setFolderCollapsed(fixture.folder, false) }

        // The Essentials grid: a tile that needs a new row, and its removal.
        var essential: UUID?
        let width = sidebar.debugEssentialsWidth
        let tilesBefore = EssentialsLayout.rowCounts(count: store.essentials(profile: first.profileID).count, width: width)
        await run("essentials_add_reflow") {
            essential = try? store.addEntry(.essential, url: "\(base)?essential-new", title: "New essential", space: first.id).id
        }
        let tilesAfter = EssentialsLayout.rowCounts(count: store.essentials(profile: first.profileID).count, width: width)
        SpikeRunner.record("essentials_rows", "\(tilesBefore) → \(tilesAfter) at width \(Int(width))")
        await run("essentials_remove_reflow") { if let essential { _ = try? store.remove(essential) } }

        // The changed dot and the reset icon (a pinned entry whose page left its URL).
        sidebar.select(fixture.pinned[0])
        if let page = tabs.contents(for: fixture.pinned[0]) {
            await waitLoaded(page, timeout: 15)
            page.load(URL(string: "\(base)?pinned-elsewhere")!)
            await waitLoaded(page, timeout: 15)
        }
        _ = await waitUntil(5) { self.store.isChanged(fixture.pinned[0]) }
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("pinned_changed", store.isChanged(fixture.pinned[0]))
        await run("hover_reset_icon_in") { sidebar.debugHover(fixture.pinned[0]) }
        await run("hover_reset_icon_out") { sidebar.debugHover(nil) }
        await run("reset_crossfade") { sidebar.resetSelected() }
        if let page = tabs.contents(for: fixture.pinned[0]) { await waitLoaded(page, timeout: 15) }
        try? await Task.sleep(for: .milliseconds(400))
        // The dot as the page's commit away from the pinned URL reaches the store.
        await run("changed_dot_in") { try? store.setLivePage(fixture.pinned[0], url: "\(base)?pinned-elsewhere", title: "Elsewhere") }
        // The reset's own cost in two parts: the store's change (the row's crossfade included) and the engine's load.
        if let page = tabs.contents(for: fixture.pinned[0]), let stored = URL(string: "\(base)?pinned-0") {
            var storeMs: [Double] = [], loadMs: [Double] = []
            for _ in 0..<5 {
                try? store.setLivePage(fixture.pinned[0], url: "\(base)?pinned-elsewhere", title: "Elsewhere")
                try? await Task.sleep(for: .milliseconds(200))
                var start = CACurrentMediaTime()
                try? store.resetToStoredURL(fixture.pinned[0])
                storeMs.append((CACurrentMediaTime() - start) * 1000)
                start = CACurrentMediaTime()
                page.load(stored, transition: .bookmark, fromAddressBar: false)
                loadMs.append((CACurrentMediaTime() - start) * 1000)
                await waitLoaded(page, timeout: 10)
            }
            SpikeRunner.record("reset_parts", "store_change \(SpikeRunner.stats(storeMs)); engine_load \(SpikeRunner.stats(loadMs))")
        }

        // The rename pulse (spec §I.9), through the inline field's commit.
        sidebar.select(fixture.today[2])
        try? await Task.sleep(for: .milliseconds(400))
        await run("rename_pulse") { sidebar.debugRenameEnded(fixture.today[2], label: "Renamed tab") }

        // The space slide with the tint crossfade, and back.
        await run("space_slide_tint") { sidebar.showSpace(fixture.second) }
        await run("space_slide_back") { sidebar.showSpace(first.id) }

        // Clear (spec §A.7): the Today rows slide out one after another.
        await run("clear_today") { sidebar.clearTodayTabs() }

        probe.stop()
        SpikeRunner.record("display_frame_interval", probe.intervalDescription)
        for line in MotionProbe.table(rows) { SpikeRunner.record("motion_table", line) }
    }
}

/// The harness's own sidebar (all URLs on the local test server).
@MainActor
struct MotionFixture {
    let folder: UUID
    let folderChildren: [UUID]
    let pinned: [UUID]
    let today: [UUID]
    let second: UUID

    init(store: SidebarStore, first: Space, base: String, window: UUID) throws {
        try store.updateSpace(first.id) { $0.themeColors = ["#3E9B5B"] }
        for index in 0..<5 {
            try store.addEntry(.essential, url: "\(base)?essential-\(index)", title: "Essential \(index)", space: first.id)
        }
        let folder = try store.addFolder(name: "Reading", space: first.id)
        self.folder = folder.id
        folderChildren = try (0..<3).map {
            try store.addEntry(.pinned, url: "\(base)?folder-\($0)", title: "In folder \($0)", space: first.id, folder: folder.id).id
        }
        pinned = try (0..<2).map { try store.addEntry(.pinned, url: "\(base)?pinned-\($0)", title: "Pinned \($0)", space: first.id).id }
        today = try (0..<5).map { try store.addEntry(.today, url: "\(base)?today-\($0)", title: "Today \($0)", space: first.id, window: window).id }
        let work = try store.createSpace(name: "Work", profile: first.profileID, icon: "briefcase", themeColors: ["#3B6FD8"])
        second = work.id
        for index in 0..<2 { try store.addEntry(.pinned, url: "\(base)?work-pinned-\(index)", title: "Work pinned \(index)", space: work.id) }
        for index in 0..<3 {
            try store.addEntry(.today, url: "\(base)?work-today-\(index)", title: "Work today \(index)", space: work.id, window: window)
        }
    }
}

/// A display link on the window for the whole run, and the read-back of
/// the animations Core Animation holds on the window's layers.
@MainActor
final class MotionProbe: NSObject {
    struct Result {
        let name: String
        let line: String
        let animations: [String]
        let frames: Int
        let dropped: Int
        let maxIntervalMs: Double
        let durationMs: Double
        let syncMs: Double
    }

    private let view: NSView
    private var link: CADisplayLink?
    private var stamps: [CFTimeInterval] = []
    private var nominals: [Double] = []
    private var scansLeft = 0
    private var found: [String: Int] = [:]
    private var seen: Set<String> = []
    private var order: [String] = []
    private var longest: CFTimeInterval = 0
    private var scanBase: CFTimeInterval = 0

    init(view: NSView) {
        self.view = view
        super.init()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// The display's frame interval as the link reported it over the run.
    var intervalDescription: String {
        guard !nominals.isEmpty else { return "no frames (window occluded or display asleep)" }
        let sorted = nominals.sorted()
        return String(format: "median %.2f ms (min %.2f, max %.2f, %d frames)", sorted[sorted.count / 2], sorted.first!, sorted.last!, sorted.count)
    }

    @objc private func tick(_ link: CADisplayLink) {
        stamps.append(link.timestamp)
        nominals.append((link.targetTimestamp - link.timestamp) * 1000)
        if stamps.count > 4000 { stamps.removeFirst(2000) }
        if nominals.count > 4000 { nominals.removeFirst(2000) }
        if scansLeft > 0 {
            scansLeft -= 1
            scan()
        }
    }

    func measure(_ name: String, trigger: () -> Void) async -> Result {
        found = [:]
        seen = []
        order = []
        longest = 0
        try? await Task.sleep(for: .milliseconds(150))
        let start = CACurrentMediaTime()
        trigger()
        let end = CACurrentMediaTime()
        scanBase = start
        scan()
        scansLeft = 3
        // Long enough for every animation it found (and a minimum, so an instant variant still shows its frames).
        try? await Task.sleep(for: .milliseconds(80))
        let window = max(longest, 0.1)
        try? await Task.sleep(for: .milliseconds(Int((window + 0.1) * 1000)))
        let recent = nominals.suffix(60).sorted()
        let nominal = recent.isEmpty ? 1.0 / 60 : recent[recent.count / 2] / 1000
        let last = stamps.last(where: { $0 < start }) ?? start
        let ticks = [last] + stamps.filter { $0 >= start && $0 <= start + window + nominal }
        var dropped = 0
        var maxInterval: Double = 0
        for (a, b) in zip(ticks, ticks.dropFirst()) {
            let interval = b - a
            maxInterval = max(maxInterval, interval)
            dropped += max(0, Int((interval / nominal).rounded()) - 1)
        }
        let firstFrame = stamps.first(where: { $0 >= end }).map { ($0 - start) * 1000 } ?? -1
        let animations = order.map { key in (found[key] ?? 1) > 1 ? "\(key) ×\(found[key]!)" : key }
        let line = String(format: "frames=%d dropped=%d max_interval_ms=%.1f window_ms=%.0f sync_ms=%.2f first_frame_ms=%.1f animations=[%@]",
                          ticks.count - 1, dropped, maxInterval * 1000, window * 1000, (end - start) * 1000, firstFrame,
                          animations.isEmpty ? "none" : animations.joined(separator: "; "))
        return Result(name: name, line: line, animations: animations, frames: ticks.count - 1, dropped: dropped,
                      maxIntervalMs: maxInterval * 1000, durationMs: longest * 1000, syncMs: (end - start) * 1000)
    }

    /// Every animation on the window's layers now.
    private func scan() {
        guard let layer = view.window?.contentView?.superview?.layer ?? view.layer else { return }
        walk(layer)
    }

    private func walk(_ layer: CALayer) {
        for key in layer.animationKeys() ?? [] {
            // One sighting per layer and key: a later scan sees the same animation again.
            let id = "\(ObjectIdentifier(layer).hashValue).\(key)"
            guard !seen.contains(id), let animation = layer.animation(forKey: key) else { continue }
            seen.insert(id)
            let text = "\(Self.owner(of: layer)).\(key): \(describe(animation))"
            if found[text] == nil { order.append(text) }
            found[text, default: 0] += 1
        }
        for sublayer in layer.sublayers ?? [] { walk(sublayer) }
    }

    /// The view that owns the layer, or the plain layer inside its nearest view.
    static func owner(of layer: CALayer) -> String {
        if let view = layer.delegate as? NSView { return String(describing: type(of: view)) }
        var parent = layer.superlayer
        while let current = parent, !(current.delegate is NSView) { parent = current.superlayer }
        let inside = (parent?.delegate as? NSView).map { " in \(String(describing: type(of: $0)))" } ?? ""
        return (layer.name ?? String(describing: type(of: layer))) + inside
    }

    private func describe(_ animation: CAAnimation) -> String {
        let begin = animation.beginTime > 0 ? max(0, animation.beginTime - scanBase) : 0
        let total = begin + animation.duration * Double(max(1, animation.repeatCount.isFinite ? animation.repeatCount : 1))
        if animation.repeatCount.isFinite, animation.repeatCount < 1000 { longest = max(longest, total) }
        var text: String
        switch animation {
        case let spring as CASpringAnimation:
            text = String(format: "spring %@ perceptual=%.3fs bounce=%.2f (mass %.1f stiffness %.1f damping %.1f) settling=%.3fs",
                          spring.keyPath ?? "?", spring.perceptualDuration, spring.bounce, spring.mass, spring.stiffness, spring.damping,
                          spring.settlingDuration)
        case let basic as CABasicAnimation:
            text = String(format: "basic %@ %.3fs %@", basic.keyPath ?? "?", basic.duration, Self.curve(basic.timingFunction))
        case let keyframe as CAKeyframeAnimation:
            text = String(format: "keyframe %@ %.3fs %d values %@", keyframe.keyPath ?? "?", keyframe.duration, keyframe.values?.count ?? 0,
                          Self.curve(keyframe.timingFunction))
        case let group as CAAnimationGroup:
            let children = (group.animations ?? []).map { ($0 as? CAPropertyAnimation)?.keyPath ?? "?" }.joined(separator: "+")
            text = String(format: "group(%@) %.3fs %@", children, group.duration, Self.curve(group.timingFunction))
        case let transition as CATransition:
            text = String(format: "transition %@ %.3fs %@", transition.type.rawValue, transition.duration, Self.curve(transition.timingFunction))
        default:
            text = String(format: "%@ %.3fs", String(describing: type(of: animation)), animation.duration)
        }
        // Implicit animations get the commit's time as their begin; only a later start is a delay.
        if begin > 0.03 { text += String(format: " begins +%.3fs", begin) }
        if !animation.repeatCount.isFinite || animation.repeatCount >= 1000 { text += " repeats" }
        return text
    }

    /// The curve's name from its control points.
    static func curve(_ function: CAMediaTimingFunction?) -> String {
        guard let function else { return "linear(default)" }
        var a = [Float](repeating: 0, count: 2), b = [Float](repeating: 0, count: 2)
        function.getControlPoint(at: 1, values: &a)
        function.getControlPoint(at: 2, values: &b)
        let points = (a[0], a[1], b[0], b[1])
        let known: [(String, (Float, Float, Float, Float))] = [
            ("linear", (0, 0, 1, 1)), ("easeIn", (0.42, 0, 1, 1)), ("easeOut", (0, 0, 0.58, 1)),
            ("easeInEaseOut", (0.42, 0, 0.58, 1)), ("default", (0.25, 0.1, 0.25, 1)),
        ]
        for (name, p) in known where abs(p.0 - points.0) < 0.01 && abs(p.1 - points.1) < 0.01 && abs(p.2 - points.2) < 0.01
            && abs(p.3 - points.3) < 0.01 {
            return name
        }
        return String(format: "cubic(%.2f,%.2f,%.2f,%.2f)", points.0, points.1, points.2, points.3)
    }

    /// One Markdown table for the run.
    static func table(_ rows: [Result]) -> [String] {
        var lines = ["| animation | frames | dropped | max interval ms | sync ms | longest animation ms | read back |", "|---|---|---|---|---|---|---|"]
        for row in rows {
            lines.append(String(format: "| %@ | %d | %d | %.1f | %.2f | %.0f | %@ |", row.name, row.frames, row.dropped, row.maxIntervalMs, row.syncMs,
                                row.durationMs, row.animations.isEmpty ? "none" : row.animations.joined(separator: "<br>")))
        }
        return lines
    }
}
#endif
