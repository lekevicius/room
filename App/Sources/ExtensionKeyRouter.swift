import AppKit
import Chrome
import Engine
import UIKitCore

/// Extension commands with the keyboard outside the page (ROADMAP 4.5,
/// B-70): the engine's keybinding registry sees keys only while a page (or
/// an action popup) has them, so with the sidebar's list, the address field
/// or the palette's field focused the host asks the extensions of the active
/// space's profile before its menu: a key-down in the browser window whose
/// key is an extension command's runs that command for the focused page
/// (`_execute_action` clicks the action, a named one reaches the
/// extension's `commands.onCommand`) and goes no further. While a page has
/// the keyboard nothing changes: the engine's registry answers first, as in
/// Chrome (3.6b).
final class ExtensionKeyRouter {
    private var monitor: Any?
    private let center: ExtensionsCenter
    private let window: () -> NSWindow?
    private let pageHasKeyboard: () -> Bool
    private let profile: () -> UUID?
    private let page: () -> (any WebContents)?
    /// What the router did last (spikes read it): the key and whether an extension took it.
    private(set) var lastRouted: (shortcut: String, handled: Bool)?

    init(center: ExtensionsCenter, window: @escaping () -> NSWindow?, pageHasKeyboard: @escaping () -> Bool,
         profile: @escaping () -> UUID?, page: @escaping () -> (any WebContents)?) {
        self.center = center
        self.window = window
        self.pageHasKeyboard = pageHasKeyboard
        self.profile = profile
        self.page = page
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weakSelf = MainActorWeak(self)] event in
            MainActor.assumeIsolated { weakSelf.value?.route(event) == true } ? nil : event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// `true` when an extension command took `event`.
    func route(_ event: NSEvent) -> Bool {
        // Extension keys carry ⌘, ⌃ or ⌥ (Chrome refuses others); the browser window only.
        guard event.type == .keyDown, !event.isARepeat,
              !event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let window = window(), event.window === window, !pageHasKeyboard(),
              let shortcut = ReservedShortcuts.shortcut(for: event) else { return false }
        let key = ShortcutTable.string(shortcut)
        guard center.command(forShortcut: key, profile: profile()) != nil else { return false }
        let handled = center.performCommand(forShortcut: key, profile: profile(), page: page())
        lastRouted = (key, handled)
        return handled
    }
}
