#if DEBUG
import AppKit
import Design
import Engine
import ImageIO
import Model
import Sidebar
import Store
import Tabs
import UIKitCore

/// Phase 5.13 spike `redesign513` (`ROOM_FIXES_SPIKE=redesign513 scripts/fixes-check.sh`) on a throwaway
/// state, the pages on the test servers (:8766). Sections (`-RoomSpikeOnly` picks):
/// - `bar`: three spaces, the fixture extension pinned, Forward after Back: the top bar's and the footer's glass;
/// - `player`: the mini-player with a fixture's content, collapsed and expanded, its progress moving;
/// - `banner`: the update banner (Sparkle's ready-to-install, as the app hears it);
/// - `overflow`: the selected tab scrolled out of view: the pill with its icon, then a click brings it back;
/// - `narrow`: the top bar at the narrowest sidebar (Reload and the toggle go, the puzzle piece stays);
/// - `peek`: a Peek opened after a click low on the page: the card grows from there, the page behind fades.
/// - `polish` (not by default): a full sidebar (five Essentials, folders, a split, long titles) and each 5.13
///   surface over it, the window with its child windows and popovers at full scale
///   (`phase-5.13-polish-<surface>-<appearance>.png`), for the review of the whole look.
/// - `playermotion` (not by default): the mini-player's expansion and collapse as the window server drew them,
///   a capture every ~25 ms (`phase-5.13-playermotion-<n>-<appearance>.png`), for a contact sheet.
/// `-RoomSpikeCaptureDirectory` keeps captures named `phase-5.13-<name>-<appearance>.png`.
extension SpikeRunner.Context {
    func redesign513Checks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false }
        NSApp.appearance = NSAppearance(named: r513Appearance == "dark" ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 1200, height: 780))
        window.center()
        controller.sidebarWidth = SidebarMetrics.defaultWidth
        controller.activityOverride = true
        await activate()
        SpikeRunner.record("conditions", "load=\(SpikeRunner.loadAverage()) appearance=\(r513Appearance) app=\(Bundle.main.bundlePath)")
        if runs("bar") { await r513Bar() }
        if runs("player") { await r513Player() }
        if runs("banner") { await r513Banner() }
        if runs("overflow") { await r513Overflow() }
        if runs("narrow") { await r513Narrow() }
        if runs("peek") { await r513Peek() }
        if only.contains("playermotion") { await r513PlayerMotion() }
        if only.contains("polish") { await r513Polish() }
    }

    private var r513Appearance: String { UserDefaults.standard.string(forKey: "RoomSpikeAppearance") == "dark" ? "dark" : "light" }
    private static let r513Base = "http://127.0.0.1:8766/"

    private func r513Capture(_ name: String) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        window.displayIfNeeded()
        let url = URL(fileURLWithPath: directory).appending(path: "phase-5.13-\(name)-\(r513Appearance).png")
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(window, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    private func r513Frame(_ identifier: String) -> String {
        guard let view = Self.f512View(in: controller.rootView, identifier: identifier), !view.isHiddenOrHasHiddenAncestor else { return "hidden" }
        return NSStringFromRect(view.convert(view.bounds, to: nil))
    }

    // MARK: bar

    private func r513Bar() async {
        guard let store = AppDelegate.current?.store, let profile = store.sidebar.profiles.first else { return SpikeRunner.record("error", "bar: no store") }
        for (name, icon) in [("Work", "suitcase"), ("Reading", "book")] where !store.sidebar.spaces.contains(where: { $0.name == name }) {
            _ = try? store.sidebar.createSpace(name: name, profile: profile.id, icon: icon)
        }
        try? await Task.sleep(for: .milliseconds(400))
        if let center = AppDelegate.current?.extensions, let section = center.sections.first {
            _ = await waitUntil(10) { section.extensions.isReady }
            let fixture = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-3.6/extension", directoryHint: .isDirectory)
            if let id = try? await section.extensions.loadUnpacked(at: fixture) {
                _ = await waitUntil(5) { center.sections.first?.installed.first { $0.id == id }?.action?.icon != nil }
                if let item = center.sections.first?.installed.first(where: { $0.id == id }) { center.setPinned(true, item, in: section) }
            }
        }
        guard let page = await open(URL(string: Self.r513Base + "find.html?bar-a")!) else { return SpikeRunner.record("error", "bar: no page") }
        page.load(URL(string: Self.r513Base + "find.html?bar-b")!)
        _ = await waitUntil(5) { page.url?.query == "bar-b" && !page.isLoading }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("bar_back_only", "back=\(r513Frame("nav-back")) forward=\(r513Frame("nav-forward")) reload=\(r513Frame("nav-reload")) "
            + "toggle=\(r513Frame("sidebar-toggle")) extensions=\(sidebar.extensionBar.shownActionIDs.count) puzzle=\(r513Frame("extension-overflow"))")
        r513Capture("bar-back")
        page.goBack()
        _ = await waitUntil(5) { page.canGoForward }
        try? await Task.sleep(for: .milliseconds(600))
        SpikeRunner.record("bar_forward", "back=\(r513Frame("nav-back")) forward=\(r513Frame("nav-forward")) reload=\(r513Frame("nav-reload")) "
            + "extensions_shown=\(sidebar.extensionBar.shownActionIDs.count) puzzle=\(r513Frame("extension-overflow")) spaces=\(r513Frame("space-icons"))")
        r513Capture("bar-forward")
    }

    // MARK: player

    private func r513Player() async {
        guard let page = await open(URL(string: Self.r513Base + "find.html?player")!), let entry = tabs.entryID(for: page) else {
            return SpikeRunner.record("error", "player: no page")
        }
        let artwork = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSGradient(colors: [.systemIndigo, .systemPink])?.draw(in: rect, angle: 45)
            return true
        }
        let content = MediaRowContent(entry: entry, title: "Human After All (Official Music Video) — a long title that scrolls",
                                      subtitle: "Daft Punk", image: artwork, isPlaying: true, canGoNext: true, canGoPrevious: true,
                                      position: .init(duration: 156, elapsed: 22, rate: 1, date: Date()))
        sidebar.setMediaRow(content)
        try? await Task.sleep(for: .milliseconds(600))
        SpikeRunner.record("player_collapsed", "frame=\(r513Frame("media-row"))")
        r513Capture("player-collapsed")
        sidebar.debugExpandMediaRow(true)
        try? await Task.sleep(for: .milliseconds(Int(Motion.medium * 1000 / 3)))
        SpikeRunner.record("player_mid", "presented=\(NSStringFromRect(sidebar.debugMediaRowPresentedFrame)) "
            + "between=\(sidebar.debugMediaRowPresentedFrame.height > MediaRowMetrics.height + 1 && sidebar.debugMediaRowPresentedFrame.height < MediaRowMetrics.expandedHeight - 1)")
        try? await Task.sleep(for: .milliseconds(1600))
        SpikeRunner.record("player_expanded", "frame=\(r513Frame("media-row")) pip=\(r513Frame("media-row-pip")) previous=\(r513Frame("media-row-previous"))")
        r513Capture("player-expanded")
        sidebar.debugExpandMediaRow(false)
        try? await Task.sleep(for: .milliseconds(400))
        sidebar.setMediaRow(nil)
    }

    private func r513PlayerMotion() async {
        guard let page = await open(URL(string: Self.r513Base + "find.html?playermotion")!), let entry = tabs.entryID(for: page) else {
            return SpikeRunner.record("error", "playermotion: no page")
        }
        let artwork = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSGradient(colors: [.systemIndigo, .systemPink])?.draw(in: rect, angle: 45)
            return true
        }
        sidebar.setMediaRow(MediaRowContent(entry: entry, title: "Human After All", subtitle: "Daft Punk", image: artwork, isPlaying: true,
                                            canGoNext: true, canGoPrevious: true, position: .init(duration: 156, elapsed: 22, rate: 1, date: Date())))
        try? await Task.sleep(for: .milliseconds(800))
        var index = 0
        for expanded in [true, false] {
            let start = Date()
            sidebar.debugExpandMediaRow(expanded)
            while Date().timeIntervalSince(start) < Motion.medium + 0.15 {
                try? await Task.sleep(for: .milliseconds(25))
                r513Capture(String(format: "playermotion-%02d", index))
                SpikeRunner.record("playermotion_\(index)", String(format: "t=%.0fms presented=%@", Date().timeIntervalSince(start) * 1000,
                                                                     NSStringFromRect(sidebar.debugMediaRowPresentedFrame)))
                index += 1
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        sidebar.setMediaRow(nil)
    }

    // MARK: polish

    /// The window with its popovers and child windows, full scale.
    private func r513Shot(_ name: String) async {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory"),
              let image = await matrixShot(scale: 1) else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "phase-5.13-polish-\(name)-\(r513Appearance).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        SpikeRunner.record("polish_\(name)", CGImageDestinationFinalize(destination) ? url.lastPathComponent : "failed")
    }

    private func r513Polish() async {
        let space = sidebar.activeSpaceID
        let base = Self.r513Base + "find.html?"
        for (index, title) in ["Mail", "Calendar", "Figma", "Linear", "Notion"].enumerated() {
            _ = try? store.addEntry(.essential, url: base + "essential-\(index)", title: title, space: space)
        }
        let reading = try? store.addFolder(name: "Reading list for the long weekend", space: space)
        let design = try? store.addFolder(name: "Design", space: space)
        let titles = ["Liquid Glass — Human Interface Guidelines — Apple Developer Documentation",
                      "Designing for macOS Tahoe: windows, toolbars and sidebars", "A short one"]
        for (index, title) in titles.enumerated() {
            _ = try? store.addEntry(.pinned, url: base + "reading-\(index)", title: title, space: space, folder: reading?.id)
            _ = try? store.addEntry(.pinned, url: base + "design-\(index)", title: "Design \(title)", space: space, folder: design?.id)
        }
        if let design { try? store.setFolderCollapsed(design.id, true) }
        var today: [UUID] = []
        for title in ["1Password on the Mac: a new look for passkeys and everything else", "NVIDIA/cuda-samples: Samples for CUDA developers",
                      "mantrakp04/agentic-browser", "A farewell to the old web, and what comes next", "Amazon.co.uk: Low Prices in Electronics, Books",
                      "Hacker News", "The Verge"] {
            if let entry = try? store.addEntry(.today, url: base + "today-\(today.count)", title: title, space: space, window: sidebar.windowID) {
                today.append(entry.id)
            }
        }
        try? await Task.sleep(for: .milliseconds(600))
        if today.count > 3 {
            sidebar.select(today[0])
            try? await Task.sleep(for: .milliseconds(800))
            sidebar.joinIntoSplit(today[1], with: today[0])
            try? await Task.sleep(for: .milliseconds(600))
            sidebar.select(today[2])
            try? await Task.sleep(for: .milliseconds(800))
            sidebar.joinIntoSplit(today[3], with: today[2])
            try? await Task.sleep(for: .milliseconds(600))
            sidebar.select(today[5])
        }
        try? await Task.sleep(for: .milliseconds(1200))
        await r513Shot("sidebar")

        if let design {
            sidebar.showFolderPreview(design.id)
            _ = await waitUntil(2) { self.sidebar.debugFolderPreviewWindow?.isVisible == true }
            try? await Task.sleep(for: .milliseconds(500))
            await r513Shot("folder-preview")
            sidebar.debugFolderPreviewWindow?.orderOut(nil)
            try? await Task.sleep(for: .milliseconds(300))
        }

        if let switcher = AppDelegate.current?.activeWindow?.switcher {
            switcher.debugShow()
            try? await Task.sleep(for: .milliseconds(900))
            await r513Shot("switcher")
            switcher.debugEnd()
            try? await Task.sleep(for: .milliseconds(300))
        }

        if let page = tabs.current, let entry = tabs.entryID(for: page) {
            let artwork = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
                NSGradient(colors: [.systemIndigo, .systemPink])?.draw(in: rect, angle: 45)
                return true
            }
            sidebar.setMediaRow(MediaRowContent(entry: entry, title: "Human After All (Official Music Video)", subtitle: "Daft Punk", image: artwork,
                                                isPlaying: true, canGoNext: true, canGoPrevious: true,
                                                position: .init(duration: 156, elapsed: 22, rate: 0, date: Date())))
            try? await Task.sleep(for: .milliseconds(600))
            await r513Shot("player")
            sidebar.debugExpandMediaRow(true)
            try? await Task.sleep(for: .milliseconds(700))
            await r513Shot("player-expanded")
            sidebar.debugExpandMediaRow(false)
            AppDelegate.current?.showUpdateReady(version: "0.3.1") {}
            try? await Task.sleep(for: .milliseconds(800))
            await r513Shot("banner-player")
            // The hovered space's name over the cards (5.13: it was hidden behind them).
            if let profile = store.profiles.first, let work = try? store.createSpace(name: "Work", profile: profile.id, icon: "suitcase") {
                try? await Task.sleep(for: .milliseconds(500))
                sidebar.debugHoverSpaceIcon(work.id)
                try? await Task.sleep(for: .milliseconds(500))
                await r513Shot("space-name-over-player")
                sidebar.debugHoverSpaceIcon(nil)
            }
            sidebar.setMediaRow(nil)
        }

        for index in 0..<30 {
            _ = try? store.addEntry(.today, url: base + "more-\(index)", title: "More reading \(index)", space: space, window: sidebar.windowID)
        }
        try? await Task.sleep(for: .milliseconds(600))
        sidebar.debugOutline.scrollRowToVisible(sidebar.debugOutline.numberOfRows - 1)
        try? await Task.sleep(for: .milliseconds(700))
        await r513Shot("overflow")
        sidebar.debugOutline.scrollRowToVisible(0)

        if let page = tabs.current {
            tabs.openPeek(URL(string: base + "peeked")!, from: page)
            try? await Task.sleep(for: .milliseconds(1200))
            await r513Shot("peek")
            _ = tabs.closeShownPeek()
            try? await Task.sleep(for: .milliseconds(600))
        }

        if let palette = AppDelegate.current?.palette {
            palette.toggleNew()
            palette.setText("design")
            try? await Task.sleep(for: .milliseconds(900))
            await r513Shot("palette")
            palette.escape()
            palette.escape()
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    // MARK: banner

    private func r513Banner() async {
        var restarted = false
        AppDelegate.current?.showUpdateReady(version: "0.3.1") { restarted = true }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("banner", "shown=\(sidebar.isShowingUpdateBanner) frame=\(r513Frame("update-banner")) restart=\(r513Frame("update-restart"))")
        r513Capture("banner")
        (Self.f512View(in: controller.rootView, identifier: "update-restart") as? NSButton)?.performClick(nil)
        SpikeRunner.record("banner_restart", "install_called=\(restarted)")
    }

    // MARK: overflow

    private func r513Overflow() async {
        let space = sidebar.activeSpaceID
        guard let page = await open(URL(string: Self.r513Base + "find.html?overflow")!), let selected = tabs.entryID(for: page) else {
            return SpikeRunner.record("error", "overflow: no page")
        }
        for index in 0..<40 {
            _ = try? store.addEntry(.today, url: Self.r513Base + "find.html?row=\(index)", title: "Row \(index)", space: space, window: sidebar.windowID)
        }
        sidebar.select(selected)
        try? await Task.sleep(for: .milliseconds(600))
        let outline = sidebar.debugOutline
        outline.scrollRowToVisible(outline.numberOfRows - 1)
        try? await Task.sleep(for: .milliseconds(400))
        if sidebar.debugRowVisible(selected) {
            outline.scrollRowToVisible(0)
            try? await Task.sleep(for: .milliseconds(400))
        }
        let shown = sidebar.bodyView.debugOverflow
        SpikeRunner.record("overflow", "top=\(shown.top) bottom=\(shown.bottom) pill=\(r513Frame("overflow-top")) \(r513Frame("overflow-bottom"))")
        r513Capture("overflow")
        sidebar.bodyView.debugClickOverflow()
        try? await Task.sleep(for: .milliseconds(700))
        let after = sidebar.bodyView.debugOverflow
        SpikeRunner.record("overflow_click", "top=\(after.top) bottom=\(after.bottom) visible=\(sidebar.debugRowVisible(selected))")
    }

    // MARK: peek

    private func r513Peek() async {
        guard let session = AppDelegate.current?.activeWindow, let peek = session.peek,
              let page = await open(URL(string: Self.r513Base + "find.html?peek")!) else { return SpikeRunner.record("error", "peek: no page") }
        let root = controller.rootView
        let card = root.currentLayout.card
        // A click at the content area's lower left, as on a link there.
        let click = CGPoint(x: card.minX + card.width * 0.25, y: card.minY + card.height * 0.8)
        session.lastClick = (click, ProcessInfo.processInfo.systemUptime)
        tabs.openPeek(URL(string: Self.r513Base + "find.html?peeked")!, from: page)
        try? await Task.sleep(for: .milliseconds(30))
        // The first frame's card, back in the overlay's view space: its centre should be the click.
        let presented = peek.overlay.card.layer?.presentation()?.frame ?? .zero
        let shown = peek.overlay.convertFromLayer(presented)
        let origin = peek.lastOpenOrigin ?? .zero
        let start = peek.lastOpenStart.map { peek.overlay.convertFromLayer($0) } ?? .zero
        try? await Task.sleep(for: .milliseconds(900))
        let rest = peek.overlay.card.frame
        SpikeRunner.record("peek_open", "click=\(Int(origin.x)),\(Int(origin.y)) start_rect_centre=\(Int(start.midX)),\(Int(start.midY)) "
            + "first_frame_centre=\(Int(shown.midX)),\(Int(shown.midY)) size=\(Int(shown.width))x\(Int(shown.height)) rest=\(NSStringFromRect(rest)) "
            + "from_click=\(abs(start.midX - origin.x) < 2 && abs(start.midY - origin.y) < 2) "
            + "first_frame_towards_click=\(abs(shown.midY - origin.y) < abs(rest.midY - origin.y) && abs(shown.midX - origin.x) < abs(rest.midX - origin.x))")
        SpikeRunner.record("peek_layout", "background_alpha=\(String(format: "%.2f", peek.debugBackgroundAlpha)) scale=\(String(format: "%.2f", peek.debugBackgroundScale)) close=\(r513Frame("peek-close")) "
            + "open_as_tab=\(r513Frame("peek-open-as-tab")) split=\(r513Frame("peek-split"))")
        r513Capture("peek")
        _ = tabs.closeShownPeek()
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("peek_closed", "background_alpha=\(String(format: "%.2f", peek.debugBackgroundAlpha)) scale=\(String(format: "%.2f", peek.debugBackgroundScale))")
    }

    // MARK: narrow

    private func r513Narrow() async {
        controller.sidebarWidth = SidebarMetrics.minWidth
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("narrow", "toggle=\(r513Frame("sidebar-toggle")) reload=\(r513Frame("nav-reload")) back=\(r513Frame("nav-back")) "
            + "puzzle=\(r513Frame("extension-overflow")) shown=\(sidebar.extensionBar.shownActionIDs.count)")
        r513Capture("narrow")
        controller.sidebarWidth = 250
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("width_250", "toggle=\(r513Frame("sidebar-toggle")) reload=\(r513Frame("nav-reload")) puzzle=\(r513Frame("extension-overflow"))")
        r513Capture("width-250")
        controller.sidebarWidth = SidebarMetrics.defaultWidth
    }
}
#endif
