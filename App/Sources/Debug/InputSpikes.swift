#if DEBUG
import AppKit
import Carbon
import Engine
import Model
import Palette
import Sidebar
import Tabs

/// `input` (5.5a, ROADMAP 5.5 tasks 1–3 and 8): marked text (what an input
/// method sends: `NSTextInputClient`'s `setMarkedText` then `insertText`,
/// straight to the first responder) in the palette field, the rename field and
/// a page's textarea, a reserved key while a page composes, dead keys and ⌥
/// characters in the palette; the mouse's back and forward buttons, middle-,
/// ⌘- and ⇧-clicks on links, horizontal scroll over the sidebar; the history
/// swipe (scroll-phase events into the card, then the same over the sidebar);
/// B-102 in the palette with suggestions off. Pages are the test servers'
/// (`scripts/test-servers.sh`: :8770's site, :8776's `phase-5.5/ime.html`).
/// `-RoomSpikeOnly ime,mouse,swipe,palette` runs a subset.
extension SpikeRunner.Context {
    private static let imePage = URL(string: "http://127.0.0.1:8776/phase-5.5/ime.html")!
    private static let sitePage = URL(string: "http://127.0.0.1:8770/site.html")!

    func inputChecks() async {
        let only = UserDefaults.standard.string(forKey: "RoomSpikeOnly").map { Set($0.split(separator: ",").map(String.init)) }
        func runs(_ name: String) -> Bool { only?.contains(name) ?? true }
        AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false }
        restorePaletteHooks()
        window.setContentSize(NSSize(width: 1200, height: 780))
        SpikeRunner.record("input_source", InputSources.currentID)
        if runs("ime") { await imeChecks() }
        if runs("mouse") { await mouseChecks() }
        if runs("swipe") { await swipeChecks() }
        if runs("palette") { await selectionChecks() }
    }

    // MARK: IME

    private var editor: NSTextView? { window.firstResponder as? NSTextView }

    private func imeChecks() async {
        guard let palette else { return SpikeRunner.record("error", "input: no palette") }
        // A typed visit, so "127" has an inline completion to withhold while composing.
        palette.toggleNew()
        palette.setText(Self.sitePage.absoluteString)
        palette.commit(modifier: .none)
        if let page = tabs.current { await waitLoaded(page, timeout: 10) }
        try? await Task.sleep(for: .milliseconds(500))

        // 1. The palette field.
        palette.toggleNew()
        try? await Task.sleep(for: .milliseconds(200))
        guard let field = editor else { return SpikeRunner.record("ime_palette", "no field editor") }
        field.setMarkedText("127", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try? await Task.sleep(for: .milliseconds(300))
        let composing = "marked=\(field.hasMarkedText()) field=\"\(palette.fieldText)\" typed=\"\(palette.typedText)\" inline=\(palette.result.inlineCompletion ?? "nil")"
        field.insertText("127", replacementRange: NSRange(location: NSNotFound, length: 0))
        try? await Task.sleep(for: .milliseconds(300))
        let committed = "marked=\(field.hasMarkedText()) field=\"\(palette.fieldText)\" typed=\"\(palette.typedText)\" inline=\(palette.result.inlineCompletion ?? "nil")"
        SpikeRunner.record("ime_palette_inline", "composing: \(composing); committed: \(committed)")
        palette.setText("")
        field.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try? await Task.sleep(for: .milliseconds(200))
        let japanese = "marked=\(field.hasMarkedText()) range=\(NSStringFromRange(field.markedRange())) field=\"\(palette.fieldText)\""
        field.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
        try? await Task.sleep(for: .milliseconds(200))
        SpikeRunner.record("ime_palette_kana", "\(japanese) → committed field=\"\(palette.fieldText)\" typed=\"\(palette.typedText)\" "
            + "rows=\(palette.result.matches.count) top=\(palette.result.matches.first?.title ?? "none")")
        field.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        field.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        field.insertText("拼音", replacementRange: NSRange(location: NSNotFound, length: 0))
        try? await Task.sleep(for: .milliseconds(200))
        SpikeRunner.record("ime_palette_pinyin", "field=\"\(palette.fieldText)\" typed=\"\(palette.typedText)\"")

        // 2. Dead keys and ⌥ characters, as key events on the current layout's keys.
        palette.setText("")
        if let layout = KeyLayout(id: InputSources.currentID), let e = layout.keyCode(for: "e"), let o = layout.keyCode(for: "o") {
            // Quartz key events (an NSEvent built from characters skips the layout's dead-key state: the first run typed "e").
            sendQuartzKey(e, option: true)   // ⌥E: the acute dead key
            try? await Task.sleep(for: .milliseconds(150))
            let deadMarked = editor?.hasMarkedText() ?? false
            sendQuartzKey(e, option: false)
            try? await Task.sleep(for: .milliseconds(150))
            sendQuartzKey(o, option: true)
            try? await Task.sleep(for: .milliseconds(200))
            SpikeRunner.record("dead_keys_palette", "layout=\(InputSources.currentID) ⌥E marked=\(deadMarked) then E, then ⌥O: field=\"\(palette.fieldText)\" "
                + "typed=\"\(palette.typedText)\" (expected \"éø\")")
        } else {
            SpikeRunner.record("dead_keys_palette", "no layout data for \(InputSources.currentID)")
        }
        palette.toggleNew()

        // 3. The rename field.
        if let id = tabs.currentEntryID {
            sidebar.beginRename(id)
            try? await Task.sleep(for: .milliseconds(300))
            if let rename = editor {
                rename.setMarkedText("へや", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
                try? await Task.sleep(for: .milliseconds(200))
                let during = "marked=\(rename.hasMarkedText()) text=\"\(rename.string)\" title=\"\(store.entry(id).map(EntryLabel.title) ?? "nil")\""
                rename.insertText("部屋", replacementRange: NSRange(location: NSNotFound, length: 0))
                rename.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                try? await Task.sleep(for: .milliseconds(300))
                SpikeRunner.record("ime_rename", "\(during) → after Return title=\"\(store.entry(id).map(EntryLabel.title) ?? "nil")\" (expected 部屋)")
            } else {
                SpikeRunner.record("ime_rename", "no field editor after beginRename")
            }
        }

        // 4. A page's textarea, and ⌘T (reserved) while it composes.
        guard let page = await open(Self.imePage, timeout: 10) else { return SpikeRunner.record("ime_page", "ime.html did not open") }
        await activate()
        try? await Task.sleep(for: .milliseconds(400))
        await click(page, "#t")
        focusPage(page)
        _ = await js(page, "document.getElementById('t').focus(); 0")
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("ime_page_focus", "key=\(window.isKeyWindow) active=\(await js(page, "document.activeElement && document.activeElement.id"))")
        guard let client = window.firstResponder as? NSTextInputClient else {
            return SpikeRunner.record("ime_page", "the page's view is not an NSTextInputClient (\(String(describing: window.firstResponder)))")
        }
        client.setMarkedText("にほ", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try? await Task.sleep(for: .milliseconds(300))
        client.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try? await Task.sleep(for: .milliseconds(300))
        let composingValue = await js(page, "document.getElementById('t').value")
        let marked = client.hasMarkedText()
        let paletteBefore = palette.isOpen
        sendRaw(keyCode: 17, characters: "t", ignoring: "t", [.command])
        try? await Task.sleep(for: .milliseconds(400))
        let reserved = palette.isOpen && !paletteBefore
        if palette.isOpen { palette.toggleNew() }
        focusPage(page)
        try? await Task.sleep(for: .milliseconds(200))
        (window.firstResponder as? NSTextInputClient)?.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
        try? await Task.sleep(for: .milliseconds(400))
        let value = await js(page, "document.getElementById('t').value")
        let events = await js(page, "document.documentElement.dataset.events || '[]'")
        SpikeRunner.record("ime_page", "composing value=\(composingValue) marked=\(marked); ⌘T while composing opened the palette=\(reserved); "
            + "committed value=\(value) events=\(events)")
    }

    /// One source for a sequence, so a dead key's state carries to the next key.
    nonisolated(unsafe) private static let keySource = CGEventSource(stateID: .privateState)

    /// A key down and up as Quartz events made into `NSEvent`s (their characters from the current layout).
    private func sendQuartzKey(_ keyCode: UInt16, option: Bool) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: Self.keySource, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = option ? .maskAlternate : []
            guard let ns = NSEvent(cgEvent: event) else { continue }
            // Down events straight to the field editor's input context (the event keeps its Quartz data, which
            // the text input system reads for dead keys); ups are not text.
            if down, let editor {
                // Straight to the field editor's keyDown (the event keeps its Quartz data, which the text input
                // system reads for dead keys); a key up is not text.
                editor.keyDown(with: ns)
                SpikeRunner.record("quartz_key_\(keyCode)_\(option ? "option" : "plain")", "characters=\(ns.characters?.debugDescription ?? "nil") field=\(editor.string.debugDescription) marked=\(editor.hasMarkedText())")
                continue
            }
            if !down { continue }
            if ns.window == nil, let keyed = NSEvent.keyEvent(with: ns.type, location: .zero, modifierFlags: ns.modifierFlags, timestamp: ns.timestamp,
                                                              windowNumber: window.windowNumber, context: nil, characters: ns.characters ?? "",
                                                              charactersIgnoringModifiers: ns.charactersIgnoringModifiers ?? "", isARepeat: false, keyCode: keyCode) {
                if down { SpikeRunner.record("quartz_key_\(keyCode)_\(option ? "option" : "plain")", "characters=\(ns.characters?.debugDescription ?? "nil")") }
                NSApp.sendEvent(keyed)
            } else {
                NSApp.sendEvent(ns)
            }
        }
    }

    /// A key down and up through the application, with the characters given (a dead key has none).
    private func sendRaw(keyCode: UInt16, characters: String, ignoring: String, _ flags: NSEvent.ModifierFlags) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: characters,
                                            charactersIgnoringModifiers: ignoring, isARepeat: false, keyCode: keyCode) {
                NSApp.sendEvent(event)
            }
        }
    }

    // MARK: Mouse

    private func mouseChecks() async {
        guard let page = await open(Self.sitePage, timeout: 10) else { return SpikeRunner.record("mouse", "site.html did not open") }
        page.load(URL(string: "http://127.0.0.1:8770/other.html")!)
        await waitLoaded(page, timeout: 10)
        try? await Task.sleep(for: .milliseconds(400))
        let card = cardPoint()
        let before = page.url?.lastPathComponent ?? "nil"
        let back = InputEvents.mouseButton(3, at: card, in: window)
        SpikeRunner.record("mouse_event", "button=\(back.down?.buttonNumber ?? -1) window=\(back.down?.window === window) "
            + "location=\(back.down.map { NSStringFromPoint($0.locationInWindow) } ?? "nil") expected=\(NSStringFromPoint(card))")
        back.send(to: window)
        _ = await waitUntil(4) { page.url?.lastPathComponent == "site.html" && !page.isLoading }
        let afterBack = page.url?.lastPathComponent ?? "nil"
        try? await Task.sleep(for: .milliseconds(300))
        InputEvents.mouseButton(4, at: card, in: window).send(to: window)
        _ = await waitUntil(4) { page.url?.lastPathComponent == "other.html" && !page.isLoading }
        let afterForward = page.url?.lastPathComponent ?? "nil"
        let sidebarBack = InputEvents.mouseButton(3, at: sidebarPoint(), in: window)
        sidebarBack.send(to: window)
        _ = await waitUntil(3) { page.url?.lastPathComponent == "site.html" && !page.isLoading }
        let overSidebar = page.url?.lastPathComponent ?? "nil"
        if overSidebar == "site.html" { page.goForward(); await waitLoaded(page, timeout: 5) }
        SpikeRunner.record("mouse_back_over_sidebar", "url \(afterForward) → \(overSidebar)")
        SpikeRunner.record("mouse_back_forward", "\(before) → button 4 (buttonNumber 3) → \(afterBack) → button 5 (buttonNumber 4) → \(afterForward) "
            + "(expected site.html, other.html)")

        // Middle-, ⌘- and ⇧-clicks on a link: a background Today tab, a background Today tab, Peek.
        page.load(Self.sitePage)
        await waitLoaded(page, timeout: 10)
        try? await Task.sleep(for: .milliseconds(300))
        let selected = tabs.currentEntryID
        func todayCount() -> Int { store.today(space: sidebar.activeSpaceID).count }
        var lines: [String] = []
        for (name, kind) in [("middle", 2), ("⌘", -1)] {
            let count = todayCount()
            if kind == 2 {
                if let point = await PageDriver.center(of: "#onsite", in: page, "middle-click") {
                    InputEvents.mouseButton(2, at: windowPoint(page, point), in: window).send(to: window)
                }
            } else {
                await click(page, "#onsite", modifiers: .command)
            }
            _ = await waitUntil(4) { todayCount() > count }
            let opened = store.today(space: sidebar.activeSpaceID).last
            lines.append("\(name)-click: today \(count)→\(todayCount()) new=\(opened?.currentURL ?? "nil") selected kept=\(tabs.currentEntryID == selected) "
                + "page stayed=\(page.url?.lastPathComponent ?? "nil")")
            if todayCount() > count, let opened { sidebar.close(opened.id) }
            try? await Task.sleep(for: .milliseconds(300))
            if let selected { sidebar.select(selected) }
        }
        await click(page, "#onsite", modifiers: .shift)
        _ = await waitUntil(4) { self.tabs.shownPeek != nil }
        lines.append("⇧-click: peek=\(tabs.shownPeek?.url?.absoluteString ?? "none")")
        _ = tabs.closeShownPeek()
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("mouse_link_clicks", lines.joined(separator: "; "))

        // Horizontal wheel over the sidebar: no sideways scroll, no space switch (only a trackpad swipe switches).
        let space = sidebar.activeSpaceID
        let clip = sidebarClipOrigin()
        let point = sidebarPoint()
        for delta in [-6, 6, -6] { InputEvents.wheel(dx: Int32(delta), dy: 0, at: point, in: window, precise: false).forEach { $0.send(to: window) } }
        InputEvents.wheel(dx: -6, dy: 0, at: point, in: window, precise: false, shift: true).forEach { $0.send(to: window) }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("mouse_horizontal_sidebar", "space kept=\(sidebar.activeSpaceID == space) clip origin \(clip) → \(sidebarClipOrigin())")
    }

    /// The card's centre in window coordinates.
    private func cardPoint() -> NSPoint {
        let card = controller.rootView.convert(controller.rootView.currentLayout.card, to: nil)
        return NSPoint(x: card.midX, y: card.midY)
    }

    private func sidebarPoint() -> NSPoint {
        let bar = controller.rootView.convert(controller.rootView.currentLayout.sidebar, to: nil)
        return NSPoint(x: bar.midX, y: bar.midY)
    }

    /// A page point (CSS pixels from the viewport's top-left) in window coordinates.
    private func windowPoint(_ page: any WebContents, _ point: CGPoint) -> NSPoint {
        let view = page.nativeView
        let local = view.isFlipped ? point : CGPoint(x: point.x, y: view.bounds.height - point.y)
        return view.convert(local, to: nil)
    }

    private func sidebarClipOrigin() -> String {
        let point = sidebarPoint()
        var view = window.contentView?.hitTest(window.contentView!.superview?.convert(point, from: nil) ?? point)
        while let current = view, !(current is NSScrollView) { view = current.superview }
        return (view as? NSScrollView).map { NSStringFromPoint($0.contentView.bounds.origin) } ?? "no scroll view"
    }

    // MARK: History swipe

    private func swipeChecks() async {
        SpikeRunner.record("swipe_setting", "isSwipeTrackingFromScrollEventsEnabled=\(NSEvent.isSwipeTrackingFromScrollEventsEnabled)")
        guard let page = await open(Self.sitePage, timeout: 10) else { return SpikeRunner.record("swipe", "site.html did not open") }
        page.load(URL(string: "http://127.0.0.1:8770/other.html")!)
        await waitLoaded(page, timeout: 10)
        try? await Task.sleep(for: .milliseconds(600))
        let space = sidebar.activeSpaceID
        // Fingers to the right over the card: back.
        let overlay = await swipe(at: cardPoint(), dx: 12, steps: 40)
        _ = await waitUntil(4) { page.url?.lastPathComponent == "site.html" && !page.isLoading }
        SpikeRunner.record("swipe_card_back", "url=\(page.url?.lastPathComponent ?? "nil") (expected site.html) overlay=\(overlay) space kept=\(sidebar.activeSpaceID == space)")
        try? await Task.sleep(for: .milliseconds(600))
        // Fingers to the left: forward.
        let overlayForward = await swipe(at: cardPoint(), dx: -12, steps: 40)
        _ = await waitUntil(4) { page.url?.lastPathComponent == "other.html" && !page.isLoading }
        SpikeRunner.record("swipe_card_forward", "url=\(page.url?.lastPathComponent ?? "nil") (expected other.html) overlay=\(overlayForward) space kept=\(sidebar.activeSpaceID == space)")
        try? await Task.sleep(for: .milliseconds(600))
        // The same gesture over the sidebar: a space swipe (two spaces), never a page navigation.
        if store.spaces.count < 2, let profile = sidebar.activeSpace?.profileID {
            _ = try? store.createSpace(name: "Swipe", profile: profile, icon: "star", themeColors: [])
        }
        try? await Task.sleep(for: .milliseconds(400))
        let url = page.url?.lastPathComponent
        let sidebarOverlay = await swipe(at: sidebarPoint(), dx: -12, steps: 40)
        try? await Task.sleep(for: .milliseconds(1200))
        SpikeRunner.record("swipe_sidebar", "space switched=\(sidebar.activeSpaceID != space) page url \(url ?? "nil") → \(page.url?.lastPathComponent ?? "nil") "
            + "(expected switched, unchanged) page overlay=\(sidebarOverlay)")
    }

    /// One two-finger gesture (may-begin, began, `steps` changes of `dx` points, ended, no momentum);
    /// whether a history overlay view appeared in the window while it ran.
    private func swipe(at point: NSPoint, dx: Int32, steps: Int) async -> String {
        for _ in 0..<40 where !overlayViews(in: window.contentView).isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        let before = overlayViews(in: window.contentView)
        var seen: Set<String> = []
        for event in InputEvents.swipe(dx: dx, steps: steps, at: point, in: window) {
            event.send(to: window)
            try? await Task.sleep(for: .milliseconds(12))
            overlayViews(in: window.contentView).forEach { seen.insert($0) }
        }
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(30))
            overlayViews(in: window.contentView).forEach { seen.insert($0) }
        }
        let after = overlayViews(in: window.contentView).count
        return seen.isEmpty ? "none" : "\(seen.sorted().joined(separator: ",")) views \(before.count) → \(after)"
    }

    private func overlayViews(in view: NSView?) -> [String] {
        guard let view else { return [] }
        let name = NSStringFromClass(Swift.type(of: view))
        let own = name.localizedCaseInsensitiveContains("history") || name.localizedCaseInsensitiveContains("swipe") || name.localizedCaseInsensitiveContains("overscroll")
        return (own ? [name] : []) + view.subviews.flatMap(overlayViews(in:))
    }

    // MARK: B-102

    private func selectionChecks() async {
        guard let palette else { return }
        guard let page = await open(Self.sitePage, timeout: 10) else { return }
        page.load(URL(string: "http://127.0.0.1:8770/other.html")!)
        await waitLoaded(page, timeout: 10)
        palette.toggleNew()
        try? await Task.sleep(for: .milliseconds(200))
        guard editor != nil else { return SpikeRunner.record("b102", "no field editor") }
        type("127")
        try? await Task.sleep(for: .milliseconds(600))
        let rows = palette.result.matches.map(\.id)
        var steps = ["typed field=\"\(palette.fieldText)\" rows=\(rows.count)"]
        for _ in 0..<2 {
            press("↓")
            try? await Task.sleep(for: .milliseconds(150))
            steps.append("↓ row \(palette.highlightedIndex ?? -1) field=\"\(palette.fieldText)\" destination=\(palette.result.matches[palette.highlightedIndex ?? 0].action.url ?? "-")")
        }
        steps.append("rows unchanged=\(palette.result.matches.map(\.id) == rows)")
        press("⎋")
        try? await Task.sleep(for: .milliseconds(150))
        steps.append("⎋ open=\(palette.isOpen) row \(palette.highlightedIndex ?? -1) field=\"\(palette.fieldText)\" typed=\"\(palette.typedText)\"")
        press("⎋")
        try? await Task.sleep(for: .milliseconds(150))
        steps.append("⎋ open=\(palette.isOpen)")
        SpikeRunner.record("b102_selection_in_field", steps.joined(separator: "; "))
    }
}

/// The input sources (Text Input Sources): the current one, and an enabled
/// Japanese or Chinese input method to select for a run (never one that is not
/// enabled: enabling is a System Settings change, the user's).
enum InputSources {
    static func id(_ source: TISInputSource) -> String {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    static var currentID: String { id(TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()) }

    static var currentInputID: String { id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()) }

    /// Selects the first enabled Japanese or Chinese input method; returns the source to restore.
    static func selectEnabledIME() -> (selected: String, previous: TISInputSource)? {
        let previous = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let enabled = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return nil }
        let prefixes = ["com.apple.inputmethod.Kotoeri", "com.apple.inputmethod.SCIM", "com.apple.inputmethod.TCIM", "com.apple.inputmethod.ChineseHandwriting"]
        guard let ime = enabled.first(where: { source in prefixes.contains { id(source).hasPrefix($0) } && id(source).contains(".") }),
              TISSelectInputSource(ime) == noErr else { return nil }
        return (id(ime), previous)
    }
}

/// Mouse buttons and scroll events made as Quartz events (the only way to give
/// an `NSEvent` a button number or scroll phases), delivered to Room's own window.
enum InputEvents {
    struct Pair {
        var down: NSEvent?
        var up: NSEvent?
        func send(to window: NSWindow) { [down, up].compactMap { $0 }.forEach { $0.send(to: window) } }
    }

    /// Where to put the Quartz event so that the `NSEvent` made from it carries `point` as its
    /// `locationInWindow`: an event made from an unposted Quartz event belongs to no window
    /// (the window fields are not read back: 5.5a's first run), so its location is read as window
    /// coordinates by `NSWindow.sendEvent`; Quartz's origin is the main display's top-left.
    static func global(_ point: NSPoint, in window: NSWindow) -> CGPoint {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: height - point.y)
    }

    private static func attach(_ event: CGEvent, to window: NSWindow) -> NSEvent? {
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
        event.timestamp = CGEventTimestamp(ProcessInfo.processInfo.systemUptime * 1e9)
        return NSEvent(cgEvent: event)
    }

    /// `button`: 2 middle, 3 back (mouse button 4), 4 forward (mouse button 5).
    static func mouseButton(_ button: Int, at point: NSPoint, in window: NSWindow) -> Pair {
        let location = global(point, in: window)
        let make = { (type: CGEventType) -> NSEvent? in
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location,
                                      mouseButton: CGMouseButton(rawValue: UInt32(button)) ?? .center) else { return nil }
            event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            return attach(event, to: window)
        }
        return Pair(down: make(.otherMouseDown), up: make(.otherMouseUp))
    }

    /// A mouse wheel notch (`precise` false: line units, no phases).
    static func wheel(dx: Int32, dy: Int32, at point: NSPoint, in window: NSWindow, precise: Bool, shift: Bool = false) -> [NSEvent] {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        else { return [] }
        event.location = global(point, in: window)
        if shift { event.flags = .maskShift }
        return attach(event, to: window).map { [$0] } ?? []
    }

    /// A two-finger horizontal gesture: may-begin, began, changes, ended (trackpad phases, continuous deltas).
    static func swipe(dx: Int32, steps: Int, at point: NSPoint, in window: NSWindow) -> [NSEvent] {
        // kCGScrollPhase: began 1, changed 2, ended 4, may begin 128.
        let phases: [(Int64, Int32)] = [(128, 0), (1, dx)] + Array(repeating: (2, dx), count: steps) + [(4, 0)]
        return phases.compactMap { phase, delta in
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: delta, wheel3: 0) else { return nil }
            event.location = global(point, in: window)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(delta))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(delta))
            return attach(event, to: window)
        }
    }
}

private extension NSEvent {
    /// Through the application when the event names this window (local monitors see it, as a real one),
    /// else straight to the window.
    func send(to window: NSWindow) {
        if self.window === window { NSApp.sendEvent(self) } else { window.sendEvent(self) }
    }
}
#endif
