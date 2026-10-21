import AppKit
import Testing
@testable import UIKitCore

@Suite("Reserved shortcuts")
struct ReservedShortcutsTests {
    private func key(
        _ characters: String, code: UInt16, _ modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    @Test("Every frozen shortcut matches its US-layout event")
    func frozenSet() {
        let events: [NSEvent] = [
            key("t", code: 17, .command), key("l", code: 37, .command),
            key(",", code: 43, .command),
            key("n", code: 45, .command), key("n", code: 45, [.command, .shift]),
            key("w", code: 13, .command), key("w", code: 13, [.command, .shift]),
            key("t", code: 17, [.command, .shift]), key("q", code: 12, .command),
            key("\t", code: 48, .control), key("\t", code: 48, [.control, .shift]),
            key("}", code: 30, [.command, .shift]), key("{", code: 33, [.command, .shift]),
            key("\u{F701}", code: 125, [.command, .option]), key("\u{F700}", code: 126, [.command, .option]),
            key("\u{F703}", code: 124, [.command, .option]), key("\u{F702}", code: 123, [.command, .option]),
        ]
        #expect(events.count == ReservedShortcuts.all.count)
        for event in events {
            #expect(ReservedShortcuts.matches(event), "\(event.charactersIgnoringModifiers ?? "") \(event.keyCode)")
        }
    }

    @Test("Page-first shortcuts are not reserved")
    func notReserved() {
        let events: [NSEvent] = [
            key("s", code: 1, .command),            // sidebar: editors save with it
            key("c", code: 8, .command), key("v", code: 9, .command), key("z", code: 6, .command),
            key("a", code: 0, .command), key("f", code: 3, .command), key("r", code: 15, .command),
            key("1", code: 18, .command), key("1", code: 18, .control),
            key("i", code: 34, [.command, .option]),
            key("t", code: 17, [.command, .option]),
            key("\u{F702}", code: 123, .command),   // ⌘← is back only outside text fields
            key("\t", code: 48, []),
        ]
        for event in events {
            #expect(!ReservedShortcuts.matches(event), "\(event.charactersIgnoringModifiers ?? "") \(event.keyCode)")
        }
    }

    @Test("Letters follow the active layout's character, not the key position (Colemak)")
    func colemak() {
        // Colemak T sits on the QWERTY F key (code 3); Colemak G sits on QWERTY T (code 17).
        #expect(ReservedShortcuts.matches(key("t", code: 3, .command)))
        #expect(!ReservedShortcuts.matches(key("g", code: 17, .command)))
    }

    @Test("Non-Latin characters fall back to the US key for the key code")
    func nonLatin() {
        // Russian layout: the T key produces "е".
        #expect(ReservedShortcuts.matches(key("е", code: 17, .command)))
        #expect(!ReservedShortcuts.matches(key("ы", code: 1, .command)))
    }

    @Test("Descriptions read like menu shortcuts")
    func descriptions() {
        #expect(ReservedShortcuts.all.map(\.description) == [
            "⌘T", "⌘L", "⌘,", "⌘N", "⇧⌘N", "⌘W", "⇧⌘W", "⇧⌘T", "⌘Q", "⌃Tab", "⌃⇧Tab",
            "⇧⌘]", "⇧⌘[", "⌥⌘↓", "⌥⌘↑", "⌥⌘→", "⌥⌘←",
        ])
    }
}

@Suite("Menu actions")
struct MenuActionTests {
    /// 2.7b: View ▸ Hide Sidebar was disabled because the item's action was
    /// `toggleSidebar:`, which NSWindow answers itself (and disables) before
    /// the window's controller in the responder chain.
    @Test("The window does not answer the controller's sidebar actions")
    func windowDoesNotShadowSidebarActions() {
        #expect(NSWindow.instancesRespond(to: Selector(("toggleSidebar:"))))
        #expect(!RoomWindow.instancesRespond(to: #selector(RoomWindowController.toggleSidebarVisibility(_:))))
        #expect(!RoomWindow.instancesRespond(to: #selector(RoomWindowController.toggleSidebarOverlayPin(_:))))
    }
}

@Suite("Mouse side buttons (5.5a)")
struct MouseNavigationTests {
    @Test("Button 4 goes back, button 5 forward; the others are not navigation")
    func buttons() {
        #expect(MouseNavigation(buttonNumber: 3) == .back)
        #expect(MouseNavigation(buttonNumber: 4) == .forward)
        #expect([0, 1, 2, 5].allSatisfy { MouseNavigation(buttonNumber: $0) == nil })
    }
}
