#if DEBUG
import AppKit
import Design
import Engine
import Sidebar
import UIKitCore

/// `keyboard` (5.3a, ROADMAP 5.3 task 2 and the phase's exit): the key path
/// by keyboard alone. Every step posts key events to Room's own window
/// (`NSApp.sendEvent`) and reads the focus back: the first responder, the
/// page's `document.activeElement`, the sidebar's ring, the palette, the
/// toast's announcement. The Tab order (sidebar → header → card → footer)
/// in both of macOS's keyboard modes: the default (text fields, lists and
/// the page) and Full Keyboard Access (every control), switched in-process
/// through `KeyboardAccess.allControlsOverride` (never the system setting).
/// Pages are `research/spikes/phase-5.3/focus.html` (three focusable
/// elements); suggestions off; no click, no pasteboard.
/// `scripts/keyboard-check.sh` runs it on a throwaway state.
extension SpikeRunner.Context {
    private static var focusPage: URL {
        SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-5.3/focus.html")
    }

    func keyboardChecks() async {
        if UserDefaults.standard.bool(forKey: "RoomSuggestionsOff") { AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false } }
        window.setContentSize(NSSize(width: 1200, height: 780))
        guard let first = store.spaces.first else { return SpikeRunner.record("error", "keyboard: no space") }
        // Three Today tabs, a pinned entry (Space opens its Peek, spec §I.13) and a second space.
        let today = (1...3).compactMap { try? store.addEntry(.today, url: Self.focusPage.absoluteString + "?\($0)", title: "Focus \($0)",
                                                            space: first.id, window: sidebar.windowID).id }
        let pinned = try? store.addEntry(.pinned, url: Self.focusPage.absoluteString + "?pinned", title: "Focus pinned", space: first.id).id
        let work = try? store.createSpace(name: "Work", profile: first.profileID, icon: "briefcase", themeColors: [])
        guard today.count == 3, let pinned, let work else { return SpikeRunner.record("error", "keyboard: fixture") }
        sidebar.select(today[0])
        if let page = tabs.contents(for: today[0]) { await waitLoaded(page, timeout: 10) }
        await activate()
        try? await Task.sleep(for: .milliseconds(600))
        let outline = sidebar.debugOutline

        // 1. The Tab cycle, default mode: the list, the address field, the page's three elements, around again.
        KeyboardAccess.allControlsOverride = false
        window.makeFirstResponder(outline)
        try? await Task.sleep(for: .milliseconds(200))
        SpikeRunner.record("keyboard_default_tab", await cycle(presses: 7))
        SpikeRunner.record("keyboard_default_shift_tab", await cycle(presses: 6, backwards: true))

        // 2. Full Keyboard Access: every control, region by region.
        KeyboardAccess.allControlsOverride = true
        window.makeFirstResponder(outline)
        try? await Task.sleep(for: .milliseconds(200))
        SpikeRunner.record("keyboard_all_controls_tab", await cycle(presses: 16))
        if let room = window as? RoomWindow, let regions = room.keyViewRegions?() {
            let loop = KeyViewLoop.candidates(regions)
            SpikeRunner.record("keyboard_all_controls_loop", loop.map { view in
                view.accessibilityIdentifier().isEmpty ? NSStringFromClass(Swift.type(of: view)) : view.accessibilityIdentifier()
            }.joined(separator: ", "))
        }
        // Operable: Return on the Work space's icon switches to it, Space on the first space's switches back.
        if await tab(until: "Work", limit: 20) {
            await focusShot("space-icon")
            press(.return)
            _ = await waitUntil(3) { self.sidebar.activeSpaceID == work.id }
            SpikeRunner.record("keyboard_space_icon_return", "active=\(sidebar.activeSpace?.name ?? "?") (expected Work)")
            if await tab(until: first.name, limit: 20, backwards: true) {
                press(.space)
                _ = await waitUntil(3) { self.sidebar.activeSpaceID == first.id }
                SpikeRunner.record("keyboard_space_icon_space", "active=\(sidebar.activeSpace?.name ?? "?") (expected \(first.name))")
            } else {
                SpikeRunner.record("keyboard_space_icon_space", "not reached")
            }
        } else {
            SpikeRunner.record("keyboard_space_icon_return", "Work's icon not reached")
        }
        // Space on Back: the page goes back.
        if let page = tabs.current {
            page.load(URL(string: Self.focusPage.absoluteString + "?2")!)
            await waitLoaded(page, timeout: 10)
            try? await Task.sleep(for: .milliseconds(300))
            window.makeFirstResponder(outline)
            if await tab(until: "nav-back", limit: 12) {
                await focusShot("back")
                press(.space)
                _ = await waitUntil(5) { page.url?.query == "1" }
                SpikeRunner.record("keyboard_back_space", "url ?\(page.url?.query ?? "nil") (expected ?1)")
            } else {
                SpikeRunner.record("keyboard_back_space", "Back not reached")
            }
        }
        KeyboardAccess.allControlsOverride = false

        // 3. The key path: the sidebar to a page and back. From the first tab, the list focused without its
        // ring: the first ↓ shows the ring on the selected row, the second moves it to the next (spec §I.13).
        sidebar.select(today[0])
        if let page = tabs.current { await waitLoaded(page, timeout: 10) }
        sidebar.debugFocus(nil)
        try? await Task.sleep(for: .milliseconds(200))
        let selectedBefore = sidebar.selectedEntryID
        press(.down)
        press(.down)
        try? await Task.sleep(for: .milliseconds(150))
        let ring = sidebar.debugKeyboardFocus
        await focusShot("outline")
        press(.return)
        _ = await waitUntil(3) { self.sidebar.selectedEntryID != selectedBefore }
        if let page = tabs.current { await waitLoaded(page, timeout: 10) }
        let selectedTitle = sidebar.selectedEntryID.flatMap { sidebar.debugRowTitle(for: $0) } ?? "nil"
        await tabPress()
        let afterFirstTab = await focusName()
        await tabPress()
        let inPage = await focusName()
        await tabPress(backwards: true)
        await tabPress(backwards: true)
        let back = await focusName()
        SpikeRunner.record("keyboard_path_sidebar_page", "↓↓ ring=\(ring.ring) on \(ring.id.flatMap { sidebar.debugRowTitle(for: $0) } ?? "nil"); "
            + "⏎ selected \(selectedTitle); ⇥ \(afterFirstTab); ⇥ \(inPage); ⇧⇥⇧⇥ \(back)")

        // 4. The address field: Space opens the palette on the URL (⌘L's), Esc closes it and the focus returns.
        // The spike session counts ⌘T and ⌘L (the keys spike); here they open the palette, as in the app.
        let palette = AppDelegate.current?.activeWindow?.palette
        tabs.onNewTab = { [weak palette] in palette?.toggleNew() }
        tabs.onEditAddress = { [weak palette] docked in palette?.toggleEdit(docked: docked) }
        await tabPress()
        let onAddress = await focusName()
        await focusShot("address-field")
        press(.space)
        _ = await waitUntil(2) { palette?.isOpen == true }
        let opened = "\(palette?.mode.map { "\($0)" } ?? "closed")"
        press(.escape)
        _ = await waitUntil(2) { palette?.isOpen == false }
        try? await Task.sleep(for: .milliseconds(200))
        SpikeRunner.record("keyboard_address_field", "focus \(onAddress); Space → palette \(opened.prefix(40)); Esc → open=\(palette?.isOpen ?? false), focus \(await focusName())")

        // 5. The palette by keyboard alone: ⌘T, type, ↓/⏎ to another tab.
        sendKey("t", keyCode: 17, [.command])
        _ = await waitUntil(2) { palette?.isOpen == true }
        for character in "Focus 3" { type(character) }
        try? await Task.sleep(for: .milliseconds(500))
        let announcementsBefore = Announcement.count
        // ↓ until VoiceOver hears the tab's row (never Return on a search row: no request leaves for a check).
        var heard = "nil"
        for _ in 0..<5 {
            press(.down)
            heard = Announcement.last ?? "nil"
            if heard.hasPrefix("Focus 3,"), heard.contains("Open tabs") { break }
        }
        if heard.hasPrefix("Focus 3,"), heard.contains("Open tabs") { press(.return) } else { press(.escape) }
        _ = await waitUntil(3) { palette?.isOpen == false }
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("keyboard_palette", "⌘T typed \"Focus 3\", ↓ announced \(Announcement.count - announcementsBefore) (\"\(heard)\"), "
            + "⏎ → open=\(palette?.isOpen ?? false) selected \(sidebar.selectedEntryID.flatMap { sidebar.debugRowTitle(for: $0) } ?? "nil"); "
            + "suggestions=\(AppDelegate.current?.store?.settings.settings.searchSuggestions ?? true)")

        // 6. A toast: ⇧⌘K clears Today with "N tabs closed · Undo", announced; ⇧⌘T (Undo's key) brings them back.
        let countBefore = store.today(space: first.id, window: sidebar.windowID).count
        let toastAnnouncements = Announcement.count
        sendKey("K", keyCode: 40, [.command, .shift])
        _ = await waitUntil(3) { self.store.today(space: first.id, window: self.sidebar.windowID).count < countBefore }
        try? await Task.sleep(for: .milliseconds(600))
        let toast = AppDelegate.current?.activeWindow?.toasts?.currentToast
        let announced = Announcement.count > toastAnnouncements ? (Announcement.last ?? "nil") : "none"
        let cleared = store.today(space: first.id, window: sidebar.windowID).count
        sendKey("T", keyCode: 17, [.command, .shift])
        _ = await waitUntil(3) { self.store.today(space: first.id, window: self.sidebar.windowID).count == countBefore }
        SpikeRunner.record("keyboard_toast", "⇧⌘K: Today \(countBefore) → \(cleared), toast \"\(toast?.message ?? "none")\" action=\(toast?.action?.title ?? "none"), "
            + "announced \"\(announced)\"; ⇧⌘T → \(store.today(space: first.id, window: sidebar.windowID).count)")
        // Full Keyboard Access: does Tab reach the toast's button? (SwiftUI's own focus inside its hosting view.)
        KeyboardAccess.allControlsOverride = true
        sendKey("K", keyCode: 40, [.command, .shift])
        try? await Task.sleep(for: .milliseconds(800))
        window.makeFirstResponder(outline)
        var names: [String] = []
        for _ in 0..<18 { await tabPress(); names.append(await focusName()) }
        SpikeRunner.record("keyboard_toast_tab", names.contains { $0.contains("Hosting") || $0.contains("toast") } ? "reached: \(names.joined(separator: " → "))"
            : "not in the loop: \(names.joined(separator: " → "))")
        sendKey("T", keyCode: 17, [.command, .shift])
        _ = await waitUntil(3) { self.store.today(space: first.id, window: self.sidebar.windowID).count == countBefore }
        KeyboardAccess.allControlsOverride = false

        // 7. Esc leaves every overlay: Peek (Space on the pinned row), the Library (⇧⌘L), the downloads popover (⇧⌘J).
        sidebar.debugFocus(pinned)
        press(.space)
        _ = await waitUntil(5) { self.tabs.shownPeek != nil }
        try? await Task.sleep(for: .milliseconds(600))
        let peekShown = tabs.shownPeek != nil
        if let peek = tabs.shownPeek { focusPage(peek) }
        press(.escape)
        _ = await waitUntil(3) { self.tabs.shownPeek == nil }
        let peekAfter = tabs.shownPeek != nil
        var lines = ["Peek: Space → shown=\(peekShown), Esc → shown=\(peekAfter)"]
        if let app = AppDelegate.current {
            sendKey("L", keyCode: 37, [.command, .shift])
            _ = await waitUntil(2) { app.isLibraryShown }
            let shown = app.isLibraryShown
            press(.escape)
            _ = await waitUntil(2) { !app.isLibraryShown }
            lines.append("Library: ⇧⌘L → shown=\(shown), Esc → shown=\(app.isLibraryShown)")
            if let downloads = app.downloads {
                sendKey("J", keyCode: 38, [.command, .shift])
                _ = await waitUntil(2) { downloads.popover.isShown }
                let popover = downloads.popover.isShown
                // The popover is key: Esc goes to its window.
                let target = NSApp.keyWindow ?? window
                lines.append("key window \(NSStringFromClass(Swift.type(of: target)))")
                postKey(.escape, to: target)
                _ = await waitUntil(2) { !downloads.popover.isShown }
                lines.append("downloads: ⇧⌘J → shown=\(popover), Esc → shown=\(downloads.popover.isShown)")
            }
        }
        SpikeRunner.record("keyboard_escape", lines.joined(separator: "; "))
        KeyboardAccess.allControlsOverride = nil
    }

    /// The sidebar with the focus ring where the keyboard is (`-RoomSpikeCaptureDirectory`; a capture of
    /// Room's own window, for the review sheet, never an assertion).
    func focusShot(_ name: String) async {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard let image = await matrixShot(sidebarRect(), scale: 1),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true).appending(path: "phase-5.3a-focus-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
        SpikeRunner.record("keyboard_capture", url.lastPathComponent)
    }

    // MARK: Keys

    enum SpikeKey {
        case tab, backtab, `return`, escape, space, down, up

        var event: (characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) {
            switch self {
            case .tab: ("\t", 48, [])
            case .backtab: ("\u{19}", 48, [.shift])
            case .return: ("\r", 36, [])
            case .escape: ("\u{1b}", 53, [])
            case .space: (" ", 49, [])
            case .down: (String(UnicodeScalar(NSDownArrowFunctionKey)!), 125, [.numericPad, .function])
            case .up: (String(UnicodeScalar(NSUpArrowFunctionKey)!), 126, [.numericPad, .function])
            }
        }
    }

    func press(_ key: SpikeKey) {
        let event = key.event
        sendKey(event.characters, keyCode: event.keyCode, event.flags)
    }

    /// A key to another of Room's windows (a popover's).
    func postKey(_ key: SpikeKey, to target: NSWindow) {
        let event = key.event
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let keyEvent = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: event.flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: target.windowNumber, context: nil, characters: event.characters,
                                               charactersIgnoringModifiers: event.characters, isARepeat: false, keyCode: event.keyCode) {
                NSApp.sendEvent(keyEvent)
            }
        }
    }

    /// One printable character, typed (the field editor inserts it).
    func type(_ character: Character) {
        sendKey(String(character), keyCode: character == " " ? 49 : 0, [])
    }

    func tabPress(backwards: Bool = false) async {
        press(backwards ? .backtab : .tab)
        // The page answers through its renderer: focus moves a moment later.
        try? await Task.sleep(for: .milliseconds(250))
    }

    /// Tab (or ⇧Tab) `presses` times from where the focus is: the names, in order.
    func cycle(presses: Int, backwards: Bool = false) async -> String {
        var names = [await focusName()]
        for _ in 0..<presses {
            await tabPress(backwards: backwards)
            names.append(await focusName())
        }
        return names.joined(separator: " → ")
    }

    /// Tabs until the focus is on `name` (a view's identifier or label); false after `limit` presses.
    func tab(until name: String, limit: Int, backwards: Bool = false) async -> Bool {
        for _ in 0..<limit {
            if await focusName() == name { return true }
            await tabPress(backwards: backwards)
        }
        return await focusName() == name
    }

    /// The first responder by name: a view's identifier, else its label, else its class;
    /// the page as `page#<active element's id>`; a field editor as its field.
    func focusName() async -> String {
        guard let responder = window.firstResponder else { return "nil" }
        var view = responder as? NSView
        if let editor = responder as? NSTextView, editor.isFieldEditor, let field = editor.delegate as? NSView { view = field }
        guard let view else { return String(describing: Swift.type(of: responder)) }
        if NSStringFromClass(Swift.type(of: view)).contains("RenderWidgetHostView") {
            guard let page = tabs.shownPeek ?? tabs.current else { return "page" }
            let id = await js(page, "document.activeElement && document.activeElement !== document.body ? document.activeElement.id : ''")
            return "page#" + id.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        if !view.accessibilityIdentifier().isEmpty { return view.accessibilityIdentifier() }
        if let label = (view as? NSControl)?.cell?.accessibilityLabel() ?? view.accessibilityLabel(), !label.isEmpty { return label }
        return String(describing: Swift.type(of: view))
    }
}
#endif
