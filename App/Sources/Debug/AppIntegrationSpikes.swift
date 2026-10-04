#if DEBUG
import AppKit
import Design
import Model
import QuartzCore
import Sidebar
import Tabs
import UIKitCore

/// Phase 2.8a: `appintegration` (`scripts/app-integration.sh`, which serves
/// `research/spikes/phase-2.7/` on 127.0.0.1:8770 and answers the capture
/// requests). Checks, each selectable with `-RoomSpikeOnly`:
/// - `menus`: every item of the menu bar with its key, validation state and
///   target; `NSMenu.update()` of the whole bar timed; each menu captured open.
/// Captures are named `phase-2.8a-<name>-<appearance>`; a request for another
/// window than Room's main window carries its number (`capture: name@123`).
extension SpikeRunner.Context {
    private var app28: AppDelegate? { NSApp.delegate as? AppDelegate }

    func appIntegration() async {
        NSApp.appearance = NSAppearance(named: appearanceSuffix == "dark" ? .darkAqua : .aqua)
        SpikeRunner.record("window_id", window.windowNumber)
        window.setContentSize(NSSize(width: 1244, height: 818))
        controller.sidebarWidth = 280
        await activate()
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        func runs(_ name: String) -> Bool { only.isEmpty || only.contains(name) }
        // Two Today tabs on the test site and one pinned entry, so tab, page and space items have something to act on.
        let store = sidebar.store.sidebar
        _ = try? store.addEntry(.pinned, url: Self.site28 + "site.html", title: "Room Test Site", space: sidebar.activeSpaceID)
        await open(URL(string: Self.site28 + "site.html?a")!)
        await open(URL(string: Self.site28 + "site.html?b")!)
        try? await Task.sleep(for: .milliseconds(500))
        if runs("menus") { await menusCheck() }
    }

    static let site28 = "http://127.0.0.1:8770/"

    /// A capture of Room's main window (`windowNumber` nil) or of another of its windows.
    func capture28(_ name: String, windowNumber: Int? = nil) async {
        guard UserDefaults.standard.bool(forKey: "RoomSpikeCaptures28") else { return }
        let full = "phase-2.8a-\(name)-\(appearanceSuffix)"
        SpikeRunner.record("capture", windowNumber.map { "\(full)@\($0)" } ?? full)
        _ = await waitUntil(20) { FileManager.default.fileExists(atPath: Self.ackPath(full)) }
    }

    private static func ackPath(_ name: String) -> String {
        let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
        return output.deletingLastPathComponent().appending(path: output.lastPathComponent + ".ack-" + name).path
    }

    // MARK: Menus (ROADMAP 2.8 task 1)

    private func menusCheck() async {
        guard let bar = NSApp.mainMenu, let app = app28 else { return SpikeRunner.record("error", "no main menu") }
        // The page has the keyboard, as when a person uses the menus.
        window.makeFirstResponder(app.pageHostContainer)

        // Validation of the whole bar: what AppKit does before it shows a menu or matches a key.
        func updateAll(_ menu: NSMenu) {
            menu.update()
            for item in menu.items { if let submenu = item.submenu { updateAll(submenu) } }
        }
        var samples: [Double] = []
        for _ in 0..<50 {
            let start = ContinuousClock.now
            updateAll(bar)
            samples.append(ms(since: start))
        }
        SpikeRunner.record("menu_update_all", SpikeRunner.stats(samples))

        // Every item: its key, whether it is enabled, the object its action reaches.
        var count = 0, enabled = 0, planned = 0, keys: [String: (name: String, action: Selector?)] = [:], duplicates: [String] = []
        var unvalidated: [String] = [], wrongTarget: [String] = []
        let appActions = Set(MainMenuTable.allItems.filter { $0.target == .app && $0.chapter == nil }.compactMap(\.action))
        func walk(_ menu: NSMenu, path: String) {
            for item in menu.items where !item.isSeparatorItem {
                let name = path.isEmpty ? item.title : "\(path) ▸ \(item.title)"
                if let submenu = item.submenu {
                    walk(submenu, path: name)
                    continue
                }
                count += 1
                if item.isEnabled { enabled += 1 }
                if item.action == nil { planned += 1 }
                let key = Self.describe(item)
                if !key.isEmpty {
                    // AppKit's own pairs (a hidden twin with the same action, as Start Dictation) are one command.
                    if let other = keys[key], other.action != item.action { duplicates.append("\(key): \(other.name) / \(name)") }
                    keys[key] = (name, item.action)
                }
                let actionName = item.action.map(NSStringFromSelector) ?? "nil"
                let target = item.action.flatMap { NSApp.target(forAction: $0, to: item.target, from: item) }
                let targetName = target.map { String(describing: Swift.type(of: $0)) } ?? "nil"
                if appActions.contains(actionName) {
                    if !(target is AppDelegate) { wrongTarget.append("\(name) → \(targetName)") }
                    if let action = item.action, AppDelegate.validators[action] == nil { unvalidated.append(name) }
                }
                var line = "\(name) | key=\(key.isEmpty ? "—" : key) | \(item.isEnabled ? "enabled" : "disabled")"
                line += " | action=\(actionName) | target=\(targetName)"
                if item.isHidden { line += " | hidden alias" }
                if let tip = item.toolTip { line += " | tooltip=\(tip)" }
                SpikeRunner.record("menu_item", line)
            }
        }
        walk(bar, path: "")
        SpikeRunner.record("menu_items", "\(count) items, \(enabled) enabled, \(planned) planned (no action), \(keys.count) with a key")
        SpikeRunner.record("menu_duplicate_keys", duplicates.isEmpty ? "none" : duplicates.joined(separator: "; "))
        SpikeRunner.record("menu_app_items_not_on_app_delegate", wrongTarget.isEmpty ? "none" : wrongTarget.joined(separator: "; "))
        SpikeRunner.record("menu_app_items_without_validation", unvalidated.isEmpty ? "none" : unvalidated.joined(separator: "; "))

        // ⌘← / ⌘→ belong to a text field while one edits (the aliases validate off).
        let history = bar.item(withTitle: "History")?.submenu
        let alias = history?.items.first { $0.isHidden && $0.action == #selector(AppDelegate.goBack(_:)) }
        tabs.navigateSelected(to: Self.site28 + "site.html?c")
        if let page = tabs.current { await waitLoaded(page) }
        window.makeFirstResponder(app.pageHostContainer)
        history?.update()
        let pageFocused = alias?.isEnabled ?? false
        app.palette?.toggleNew()
        try? await Task.sleep(for: .milliseconds(300))
        history?.update()
        let fieldFocused = alias?.isEnabled ?? false
        app.palette?.dismiss()
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("menu_command_left", "enabled with the page focused=\(pageFocused), with the palette's field editing=\(fieldFocused)")

        // Each menu open, as the menu bar shows it (popped up under the window's top-left).
        for item in bar.items {
            guard let menu = item.submenu, !menu.items.isEmpty else { continue }
            let title = item.title == "Room" || bar.items.first === item ? "app" : item.title.lowercased()
            await captureOpen(menu, name: "menu-\(title)")
        }
    }

    /// An item's key equivalent in `docs/shortcuts.md` notation ("" without one).
    static func describe(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        var modifiers = item.keyEquivalentModifierMask
        let arrows: [String: ReservedShortcuts.Shortcut.Key] = [
            String(UnicodeScalar(NSLeftArrowFunctionKey)!): .leftArrow, String(UnicodeScalar(NSRightArrowFunctionKey)!): .rightArrow,
            String(UnicodeScalar(NSUpArrowFunctionKey)!): .upArrow, String(UnicodeScalar(NSDownArrowFunctionKey)!): .downArrow, "\t": .tab,
        ]
        let unshifted = Dictionary(uniqueKeysWithValues: MenuKey.shiftedUS.map { ($1, $0) })
        let key: ReservedShortcuts.Shortcut.Key
        if let arrow = arrows[item.keyEquivalent] {
            key = arrow
        } else if let base = unshifted[item.keyEquivalent] {
            key = .character(base)
            modifiers.insert(.shift)
        } else {
            if item.keyEquivalent != item.keyEquivalent.lowercased() { modifiers.insert(.shift) }
            key = .character(item.keyEquivalent.lowercased())
        }
        // AppKit's own Globe-key items (🌐F Full Screen, 🌐D Dictation) carry `.function`.
        return (item.keyEquivalentModifierMask.contains(.function) ? "🌐" : "") + ReservedShortcuts.Shortcut(key, modifiers).description
    }

    /// Pops `menu` up over the window's top-left (validated as from the menu bar) and has it captured.
    func captureOpen(_ menu: NSMenu, name: String) async {
        guard UserDefaults.standard.bool(forKey: "RoomSpikeCaptures28") else { return }
        let driver = MenuCaptureDriver(menu: menu, name: "phase-2.8a-\(name)-\(appearanceSuffix)", ackPath: Self.ackPath)
        // Menu tracking runs its own loop: a timer in the common modes requests the capture and ends it.
        let timer = Timer(timeInterval: 0.1, target: driver, selector: #selector(MenuCaptureDriver.tick(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        menu.popUp(positioning: nil, at: NSPoint(x: 80, y: 4), in: controller.rootView)
        timer.invalidate()
        try? await Task.sleep(for: .milliseconds(200))
    }
}

/// Finds the open menu's window, asks the script for its capture, and closes the menu once captured.
private final class MenuCaptureDriver: NSObject {
    let menu: NSMenu
    let name: String
    let ackPath: (String) -> String
    private var requested = false
    private var deadline = Date().addingTimeInterval(20)

    init(menu: NSMenu, name: String, ackPath: @escaping (String) -> String) {
        self.menu = menu
        self.name = name
        self.ackPath = ackPath
    }

    @objc func tick(_ timer: Timer) {
        if !requested {
            let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
            let level = Int(CGWindowLevelForKey(.popUpMenuWindow))
            let menuWindow = windows.first {
                ($0[kCGWindowOwnerPID as String] as? Int) == Int(getpid()) && ($0[kCGWindowLayer as String] as? Int) == level
            }
            guard let number = menuWindow?[kCGWindowNumber as String] as? Int else { return }
            SpikeRunner.record("capture", "\(name)@\(number)")
            requested = true
            deadline = Date().addingTimeInterval(20)
            return
        }
        guard FileManager.default.fileExists(atPath: ackPath(name)) || Date() > deadline else { return }
        timer.invalidate()
        menu.cancelTracking()
    }
}
#endif
