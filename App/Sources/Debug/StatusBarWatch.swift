#if DEBUG
import AppKit

/// Phase 5.9 (the status-item blocker): `-RoomSpikeStatusBarWatch YES` on any
/// spike polls this process's windows every 100 ms and records, the first
/// time a window whose class name contains "StatusBar" appears, the spike's
/// last recorded key before it, the window's frame and level, its content
/// view's subtree, and for each status-bar button its image name, tooltip,
/// accessibility title and label, and the status item's menu titles (the
/// creator's strings: Chromium's StatusIconMac sets the tooltip and the menu
/// from the feature that made the icon). A window that leaves is recorded too.
@MainActor
enum StatusBarWatch {
    static var lastKey = "none"
    private static var seen: Set<Int> = []
    private static var task: Task<Void, Never>?

    static func startIfRequested() {
        guard UserDefaults.standard.bool(forKey: "RoomSpikeStatusBarWatch"), task == nil else { return }
        SpikeRunner.record("statusbar_watch", "start: \(snapshotLine())")
        task = Task { @MainActor in
            while !Task.isCancelled {
                poll()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    static func statusBarWindows() -> [NSWindow] {
        NSApp.windows.filter { NSStringFromClass(type(of: $0)).contains("StatusBar") }
    }

    static func snapshotLine() -> String {
        let windows = statusBarWindows()
        let inProcess = windows.isEmpty ? "no status-bar window" : windows.map { describe($0) }.joined(separator: " | ")
        return "\(inProcess); window server, this pid, layer 25: \(serverList())"
    }

    /// CGWindowListCopyWindowInfo's metadata (no capture): the on-screen windows at the status-bar layer
    /// whose frame matches one of this process's status-bar windows (owner pid and name: on macOS 26 the
    /// window server may list a status item under another owner), and this process's own layer-25 windows.
    static func serverList() -> String {
        let all = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let frames = statusBarWindows().map { window in
            CGRect(x: window.frame.minX, y: screenHeight - window.frame.maxY, width: window.frame.width, height: window.frame.height)
        }
        let rows = all.compactMap { entry -> String? in
            guard (entry[kCGWindowLayer as String] as? Int) == 25,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            let pid = entry[kCGWindowOwnerPID as String] as? Int32 ?? 0
            guard pid == getpid() || frames.contains(where: { $0.intersects(bounds) }) else { return nil }
            return "#\(entry[kCGWindowNumber as String] as? Int ?? 0) \(NSStringFromRect(bounds)) owner=\(entry[kCGWindowOwnerName as String] as? String ?? "?")(\(pid == getpid() ? "this pid" : "pid \(pid)"))"
        }
        return rows.isEmpty ? "none" : rows.joined(separator: ", ")
    }

    private static func poll() {
        let windows = statusBarWindows()
        let numbers = Set(windows.map(\.windowNumber))
        for window in windows where !seen.contains(window.windowNumber) {
            SpikeRunner.record("statusbar_appeared", "after \(lastKey): \(describe(window))")
        }
        for gone in seen.subtracting(numbers) {
            SpikeRunner.record("statusbar_left", "after \(lastKey): window \(gone)")
        }
        seen = numbers
    }

    static func describe(_ window: NSWindow) -> String {
        var parts = ["\(NSStringFromClass(type(of: window))) #\(window.windowNumber) \(NSStringFromRect(window.frame)) level=\(window.level.rawValue) visible=\(window.isVisible)"]
        if let content = window.contentView {
            parts.append("tree=[\(subtree(content))]")
            for button in buttons(in: content) {
                let image = button.image
                parts.append("button(\(NSStringFromClass(type(of: button)))): image_name=\(image?.name() ?? "nil") "
                    + "image_size=\(image.map { NSStringFromSize($0.size) } ?? "nil") template=\(image?.isTemplate ?? false) "
                    + "image_a11y=\"\(image?.accessibilityDescription ?? "")\" title=\"\(button.title)\" "
                    + "tooltip=\"\(button.toolTip ?? "")\" a11y_title=\"\(button.accessibilityTitle() ?? "")\" "
                    + "a11y_label=\"\(button.accessibilityLabel() ?? "")\" a11y_help=\"\(button.accessibilityHelp() ?? "")\" "
                    + "target=\(button.target.map { NSStringFromClass(type(of: $0)) } ?? "nil") action=\(button.action.map(NSStringFromSelector) ?? "nil") "
                    + "menu=\(menuTitles(button.menu))")
            }
        }
        if window.responds(to: Selector(("statusItem"))), let item = window.value(forKey: "statusItem") as? NSStatusItem {
            parts.append("item: autosave=\"\(item.autosaveName ?? "")\" length=\(item.length) menu=\(menuTitles(item.menu)) "
                + "behavior=\(item.behavior.rawValue)")
        }
        return parts.joined(separator: " ")
    }

    private static func menuTitles(_ menu: NSMenu?) -> String {
        guard let menu else { return "nil" }
        return "[" + menu.items.map { $0.isSeparatorItem ? "—" : "\"\($0.title)\"" }.joined(separator: ",") + "]"
    }

    private static func subtree(_ view: NSView) -> String {
        let name = NSStringFromClass(type(of: view))
        let children = view.subviews.map { subtree($0) }
        let tip = view.toolTip.map { " tip=\"\($0)\"" } ?? ""
        return children.isEmpty ? "\(name)\(tip)" : "\(name)\(tip){\(children.joined(separator: ","))}"
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap { buttons(in: $0) }
    }
}
#endif
