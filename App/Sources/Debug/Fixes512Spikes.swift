#if DEBUG
import AppKit
import Design
import Engine
import Model
import Sidebar
import Store
import UIKitCore
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
import RoomCore
#endif

/// Phase 5.12 spike `fixes512` (`scripts/fixes-check.sh` with `-RoomSpike fixes512` through ROOM_SPIKE) on a
/// throwaway state, the pages on the test servers (:8766). Sections (`-RoomSpikeOnly` picks):
/// - `reveal`: the hidden sidebar's overlay slides in (its presentation between away and rest at mid-slide);
/// - `forward`: Forward hidden with nothing ahead, shown after Back;
/// - `switcher`: three tabs visited, each pictured as it was left; the ⌃Tab cards with their pictures;
/// - `extmenu`: the fixture extension's item in the extensions menu has its icon; the menu captured open;
/// - `picker`: Change Icon…'s picker (every emoji, the symbols) captured; an emoji typed in its field sets it;
/// - `folder`: the folder preview's rows have their pages' favicons;
/// - `press`: a press on Reload held through AppKit's tracking: the button's pressed state and its scale animation;
/// - `pip`: video picture-in-picture's window with Room's controls (patch 0029), shown by a pointer move, captured;
/// - `shots`: the selected split row (no divider), the palette's glass, the address field.
/// `-RoomSpikeCaptureDirectory` keeps captures named `phase-5.12-<name>-<appearance>.png`.
extension SpikeRunner.Context {
    func fixes512Checks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false }
        NSApp.appearance = NSAppearance(named: f512Appearance == "dark" ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 1200, height: 780))
        window.center()
        controller.sidebarWidth = SidebarMetrics.defaultWidth
        controller.activityOverride = true
        await activate()
        SpikeRunner.record("conditions", "load=\(SpikeRunner.loadAverage()) appearance=\(f512Appearance) app=\(Bundle.main.bundlePath)")
        if runs("reveal") { await f512Reveal() }
        if runs("forward") { await f512Forward() }
        if runs("switcher") { await f512Switcher() }
        if runs("extmenu") { await f512ExtensionMenu() }
        if runs("picker") { await f512Picker() }
        if runs("folder") { await f512Folder() }
        if runs("press") { await f512Press() }
        if runs("pip") { await f512PictureInPicture() }
        if runs("shots") { await f512Shots() }
        controller.isSidebarOpen = true
    }

    private var f512Appearance: String { UserDefaults.standard.string(forKey: "RoomSpikeAppearance") == "dark" ? "dark" : "light" }
    private static let f512Base = "http://127.0.0.1:8766/"

    private func f512Capture(_ name: String, of target: NSWindow? = nil) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let target = target ?? window
        target.displayIfNeeded()
        let url = URL(fileURLWithPath: directory).appending(path: "phase-5.12-\(name)-\(f512Appearance).png")
        SpikeRunner.record("capture_\(name)", (try? WindowSnapshot.writePNG(target, to: url)) != nil ? url.lastPathComponent : "failed")
    }

    // MARK: reveal

    private func f512Reveal() async {
        guard await open(URL(string: Self.f512Base + "find.html?reveal")!) != nil else { return SpikeRunner.record("error", "reveal: no page") }
        let root = controller.rootView
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(400))
        for shown in [true, false] {
            root.setOverlayShown(shown)
            try? await Task.sleep(for: .milliseconds(Int(Motion.revealIn * 1000 / 2)))
            let mid = root.overlayView.layer?.presentation()?.frame ?? .zero
            _ = await waitUntil(2) { !root.isOverlayAnimating }
            let rest = root.overlayView.frame
            SpikeRunner.record(shown ? "reveal_in" : "reveal_out", "mid_x=\(Int(mid.minX)) rest_x=\(Int(rest.minX)) width=\(Int(rest.width)) "
                + "sliding=\(shown ? mid.minX < rest.minX - 4 : mid.minX > -rest.width + 4 && mid.minX < 0) shown=\(root.isOverlayShown)")
            try? await Task.sleep(for: .milliseconds(300))
        }
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(300))
    }

    // MARK: forward

    private func f512Forward() async {
        guard let page = await open(URL(string: Self.f512Base + "find.html?forward-a")!) else { return SpikeRunner.record("error", "forward: no page") }
        page.load(URL(string: Self.f512Base + "find.html?forward-b")!)
        _ = await waitUntil(5) { page.url?.query == "forward-b" && !page.isLoading }
        try? await Task.sleep(for: .milliseconds(400))
        let forward = { Self.f512View(in: self.controller.rootView, identifier: "nav-forward") }
        let back = { Self.f512View(in: self.controller.rootView, identifier: "nav-back") }
        let before = "forward_hidden=\(forward()?.isHidden ?? true) back_x=\(Int(back()?.frame.minX ?? -1))"
        page.goBack()
        _ = await waitUntil(5) { page.canGoForward }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("forward", "\(before) | after back: forward_hidden=\(forward()?.isHidden ?? true) alpha=\(forward()?.alphaValue ?? -1) "
            + "back_x=\(Int(back()?.frame.minX ?? -1)) forward_x=\(Int(forward()?.frame.minX ?? -1)) can_go_forward=\(page.canGoForward)")
        f512Capture("forward")
    }

    static func f512View(in view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for sub in view.subviews { if let hit = f512View(in: sub, identifier: identifier) { return hit } }
        return nil
    }

    // MARK: switcher

    private func f512Switcher() async {
        var ids: [UUID] = []
        for name in ["switch-a", "switch-b", "switch-c"] {
            guard let page = await open(URL(string: Self.f512Base + "find.html?\(name)")!), let id = tabs.entryID(for: page) else { continue }
            ids.append(id)
            try? await Task.sleep(for: .milliseconds(500))
        }
        for id in ids { sidebar.select(id); try? await Task.sleep(for: .milliseconds(500)) }
        try? await Task.sleep(for: .milliseconds(500))
        let pictured = ids.filter { tabs.thumbnail(for: $0) != nil }.count
        let size = ids.compactMap { tabs.thumbnail(for: $0) }.first.map { NSStringFromSize($0.size) } ?? "none"
        guard let switcher = AppDelegate.current?.activeWindow?.switcher else { return SpikeRunner.record("error", "switcher: none") }
        switcher.debugShow()
        try? await Task.sleep(for: .milliseconds(700))
        SpikeRunner.record("switcher", "tabs=\(ids.count) pictured=\(pictured) size=\(size) panel=\(switcher.debugPanelFrame.map(NSStringFromRect) ?? "nil")")
        f512Capture("switcher")
        switcher.debugEnd()
    }

    // MARK: extmenu

    private func f512ExtensionMenu() async {
        guard let center = AppDelegate.current?.extensions, let section = center.sections.first else {
            return SpikeRunner.record("extmenu", "skipped: the engine has no extensions")
        }
        _ = await waitUntil(10) { section.extensions.isReady }
        let fixture = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-3.6/extension", directoryHint: .isDirectory)
        guard let id = try? await section.extensions.loadUnpacked(at: fixture) else { return SpikeRunner.record("error", "extmenu: not loaded") }
        _ = await waitUntil(5) { center.sections.first?.installed.first { $0.id == id }?.action?.icon != nil }
        _ = await open(URL(string: Self.f512Base + "find.html?ext")!)
        try? await Task.sleep(for: .milliseconds(800))
        let menu = sidebar.extensionBar.overflowMenu()
        if UserDefaults.standard.bool(forKey: "RoomSpikeMenuVariants"), let real = menu.items.first, let icon = real.image {
            // AppKit's own choice on macOS 27 (no preferredImageVisibility): the image hidden.
            let a = NSMenuItem(title: "Plain + symbol", action: nil, keyEquivalent: "")
            a.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
            let b = NSMenuItem(title: "Plain + icon", action: nil, keyEquivalent: "")
            b.image = icon
            let c = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            c.attributedTitle = NSAttributedString(string: "Attributed + icon")
            c.image = icon
            let d = NSMenuItem(title: "Enabled plain + icon", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
            d.image = icon
            for item in [a, b, c, d] { menu.addItem(item) }
        }
        let items = menu.items.filter { !$0.isSeparatorItem }
        SpikeRunner.record("extmenu_items", "count=\(items.count) images=\(items.map { $0.image.map { NSStringFromSize($0.size) } ?? "none" })")
        // The menu as it shows: captured from inside its own tracking loop, then dismissed.
        guard let button = sidebar.extensionBar.overflowButtonView else { return SpikeRunner.record("extmenu_open", "no overflow button") }
        let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory")
        let appearance = f512Appearance
        let timer = Timer(timeInterval: 0.5, repeats: false) { [weakMenu = MainActorWeak(menu)] _ in
            MainActor.assumeIsolated {
                let numbers = WindowSnapshot.ownWindowNumbers(layer: 101)
                var result = "menu_windows=\(numbers.count)"
                if let directory, let number = numbers.first, let image = WindowSnapshot.capture(windowNumber: number),
                   let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    let url = URL(fileURLWithPath: directory).appending(path: "phase-5.12-extmenu-\(appearance).png")
                    result += " capture=\((try? data.write(to: url)) != nil ? url.lastPathComponent : "failed") size=\(image.width)x\(image.height)"
                }
                SpikeRunner.record("extmenu_open", result)
                weakMenu.value?.cancelTracking()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 4), in: button)
    }

    // MARK: picker

    private func f512Picker() async {
        guard await open(URL(string: Self.f512Base + "find.html?picker")!) != nil, let id = sidebar.selectedEntryID else {
            return SpikeRunner.record("error", "picker: no page")
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard let menu = sidebar.debugContextMenu(for: id), let index = menu.items.firstIndex(where: { $0.title == "Change Icon…" }) else {
            return SpikeRunner.record("picker", "no Change Icon… item")
        }
        menu.performActionForItem(at: index)
        _ = await waitUntil(3) { self.sidebar.debugIconPopoverWindow != nil }
        try? await Task.sleep(for: .milliseconds(600))
        guard let popover = sidebar.debugIconPopoverWindow else { return SpikeRunner.record("picker", "not shown") }
        SpikeRunner.record("picker", "shown size=\(Int(popover.frame.width))x\(Int(popover.frame.height))")
        f512Capture("picker", of: popover)
        if let field = Self.f512Field(in: sidebar.debugIconPopoverView), popover.makeFirstResponder(field), let editor = field.currentEditor() {
            editor.insertText("🦊")
            _ = await waitUntil(3) { self.store.entry(id)?.customIcon != nil }
        }
        SpikeRunner.record("picker_typed", "icon=\(store.entry(id)?.customIcon ?? "nil")")
        sidebar.debugIconPopoverWindow?.close()
    }

    static func f512Field(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for sub in view.subviews { if let hit = f512Field(in: sub) { return hit } }
        return nil
    }

    // MARK: folder

    private func f512Folder() async {
        let space = sidebar.activeSpaceID
        guard let folder = try? store.addFolder(name: "Icons", space: space) else { return SpikeRunner.record("error", "folder: fixture") }
        for url in ["https://example.com/", "https://www.wikipedia.org/"] {
            if let entry = try? store.addEntry(.pinned, url: url, space: space, folder: folder.id) { _ = tabs.loadInBackground(entry) }
        }
        try? await Task.sleep(for: .seconds(4))
        try? store.setFolderCollapsed(folder.id, true)
        try? await Task.sleep(for: .milliseconds(600))
        sidebar.showFolderPreview(folder.id)
        _ = await waitUntil(2) { sidebar.debugFolderPreviewWindow?.isVisible == true }
        try? await Task.sleep(for: .milliseconds(400))
        let favicons = store.entries(in: .pinned(space: space, folder: folder.id)).map { tabs.pageState(for: $0.id).favicon != nil }
        SpikeRunner.record("folder_favicons", "rows_with_favicon=\(favicons)")
        if let preview = sidebar.debugFolderPreviewWindow { f512Capture("folder", of: preview) }
        sidebar.debugFolderPreviewWindow?.close()
    }

    // MARK: press

    private func f512Press() async {
        guard await open(URL(string: Self.f512Base + "find.html?press")!) != nil,
              let reload = Self.f512View(in: controller.rootView, identifier: "nav-reload") as? HoverButton else {
            return SpikeRunner.record("error", "press: no page or button")
        }
        let point = controller.rootView.convert(NSPoint(x: reload.bounds.midX, y: reload.bounds.midY), from: reload)
        var highlighted = false
        let original = reload.cell?.isHighlighted ?? false
        post(.mouseMoved, at: point)
        post(.leftMouseDown, at: point, clickCount: 1)
        try? await Task.sleep(for: .milliseconds(120))
        let pressed = reload.feedback.isPressed
        highlighted = reload.cell?.isHighlighted ?? false
        let keys = reload.layer?.animationKeys() ?? []
        let scale = reload.layer?.presentation()?.transform.m11 ?? 1
        post(.leftMouseUp, at: point, clickCount: 1)
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("press", "during: pressed=\(pressed) cell_highlighted=\(highlighted) (before \(original)) animations=\(keys) "
            + String(format: "scale=%.3f", scale) + " | after: pressed=\(reload.feedback.isPressed) cell_highlighted=\(reload.cell?.isHighlighted ?? false)")
    }

    // MARK: pip

    private func f512PictureInPicture() async {
        let url = URL(string: "\(Self.mediaBase)/phase-3.7/pip.html")!
        guard let video = await open(url) else { return SpikeRunner.record("error", "pip: no page") }
        try? await Task.sleep(for: .milliseconds(500))
        await click(video, "#video-pip")
        guard await waitUntil(5, { self.overlayWindow() != nil }), let overlay = overlayWindow() else {
            return SpikeRunner.record("pip", "no overlay window")
        }
        try? await Task.sleep(for: .milliseconds(600))
        #if ROOM_ENGINE_ROOMCORE
        let browser = tabs.engineProfiles.values.compactMap { ($0 as? RoomCoreProfile)?.spikeBrowsers.first }.first
        let shown = browser.flatMap { SpikeRunner.spikeHook($0, "roomSpikeAction:", "pip-show-controls" as NSString)?.intValue } ?? -99
        SpikeRunner.record("pip_controls_shown", "\(shown)")
        #endif
        // The controls show while the pointer is over the window.
        let inside = NSPoint(x: overlay.frame.width / 2, y: overlay.frame.height / 2)
        for offset in [CGFloat(0), 4, 8] {
            if let move = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: inside.x + offset, y: inside.y), modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: overlay.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 0, pressure: 0) {
                overlay.sendEvent(move)
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("pip", "window=\(NSStringFromRect(overlay.frame))")
        if let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory"), let image = WindowSnapshot.capture(overlay),
           let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            let file = URL(fileURLWithPath: directory).appending(path: "phase-5.12-pip-\(f512Appearance).png")
            SpikeRunner.record("capture_pip", (try? data.write(to: file)) != nil ? file.lastPathComponent : "failed")
        }
        // `-RoomSpikeHoldPip <s>` keeps the window up to look at (its in-process capture comes out blank).
        let hold = UserDefaults.standard.double(forKey: "RoomSpikeHoldPip")
        if hold > 0 {
            SpikeRunner.record("pip_hold", "\(hold) s")
            try? await Task.sleep(for: .seconds(hold))
        }
        _ = await js(video, "document.exitPictureInPicture().then(() => 'left', e => 'error ' + e.name)")
        try? await Task.sleep(for: .milliseconds(400))
    }

    // MARK: shots

    private func f512Shots() async {
        guard await open(URL(string: Self.f512Base + "find.html?split-a")!) != nil,
              let second = try? store.addEntry(.today, url: Self.f512Base + "find.html?split-b", space: sidebar.activeSpaceID),
              let first = sidebar.selectedEntryID else { return SpikeRunner.record("error", "shots: no pages") }
        tabs.loadInBackground(second)
        try? await Task.sleep(for: .milliseconds(800))
        sidebar.joinIntoSplit(second.id, with: first)
        try? await Task.sleep(for: .milliseconds(1000))
        sidebar.debugHover(nil)
        f512Capture("window")
        if let palette = AppDelegate.current?.activeWindow?.palette {
            palette.toggleNew()
            try? await Task.sleep(for: .milliseconds(600))
            f512Capture("palette")
            palette.dismiss()
        }
        sidebar.unsplit()
        try? await Task.sleep(for: .milliseconds(400))
    }
}
#endif
