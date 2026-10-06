import AppKit
import Testing
@testable import UIKitCore

/// ROADMAP 4.4a task 1: overrides move a key in the menu, the palette's hint
/// and the reserved set; conflicts are found and resolved only when confirmed;
/// macOS's own keys are refused; reset restores.
@Suite("Shortcut table")
struct ShortcutTableTests {
    typealias Shortcut = ReservedShortcuts.Shortcut
    static func k(_ character: String, _ modifiers: NSEvent.ModifierFlags) -> Shortcut { Shortcut(.character(character), modifiers) }

    let pin = "togglePin:"
    let print = "printPage:"
    let reopen = "reopenClosedTab:"

    private func key(_ characters: String, code: UInt16, _ modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private func menuItem(_ id: String, in menus: [MenuSpec]) -> MenuItemSpec? {
        menus.flatMap(\.items).first { $0.id == id }
    }

    @Test("An override moves the key in the menu, and the old key is on no item")
    func overrideMovesTheMenuKey() {
        var table = ShortcutTable()
        #expect(table.key(for: pin) == Self.k("d", .command))
        #expect(table.assign(Self.k("p", [.command, .option]), to: pin) == .ok)
        #expect(table.overrides == [pin: "⌥⌘P"])
        let menus = table.menus()
        #expect(menuItem(pin, in: menus)?.key == Self.k("p", [.command, .option]))
        #expect(!menus.flatMap(\.items).contains { $0.key == Self.k("d", .command) })
        // A built bar takes the change in place.
        let bar = MainMenuBuilder.make(ShortcutTable().menus(), appTarget: nil)
        #expect(MainMenuBuilder.apply(table, to: bar) == 1)
        let item = bar.item(withTitle: "Tab")?.submenu?.item(withTitle: "Pin Tab")
        #expect(item?.keyEquivalent == "p" && item?.keyEquivalentModifierMask == [.command, .option])
        #expect(MainMenuBuilder.apply(ShortcutTable(), to: bar) == 1)
        #expect(item?.keyEquivalent == "d" && item?.keyEquivalentModifierMask == .command)
    }

    @Test("A reserved action stays reserved under its new key; its old key is no longer reserved")
    func reservedFollowsTheAction() {
        var table = ShortcutTable()
        #expect(table.isReserved(key("T", code: 17, [.command, .shift])))
        #expect(table.assign(Self.k("t", [.command, .option]), to: reopen) == .ok)
        #expect(table.reservedKeys.contains(Self.k("t", [.command, .option])))
        #expect(!table.reservedKeys.contains(Self.k("t", [.command, .shift])))
        #expect(table.isReserved(key("t", code: 17, [.command, .option])))
        #expect(!table.isReserved(key("T", code: 17, [.command, .shift])))
        #expect(table.reservedKeys.count == ReservedShortcuts.all.count)
        // A page-first action under a once-reserved key stays page-first.
        #expect(table.assign(Self.k("t", [.command, .shift]), to: pin) == .ok)
        #expect(!table.isReserved(key("T", code: 17, [.command, .shift])))
    }

    @Test("Two actions on one key: a conflict naming the other, applied only when confirmed")
    func conflicts() {
        var table = ShortcutTable()
        #expect(table.assign(Self.k("p", .command), to: pin) == .conflict([print]))
        #expect(table.key(for: pin) == Self.k("d", .command) && table.key(for: print) == Self.k("p", .command))
        #expect(table.assign(Self.k("p", .command), to: pin, replacingConflicts: true) == .conflict([print]))
        #expect(table.key(for: pin) == Self.k("p", .command))
        #expect(table.key(for: print) == nil)
        #expect(table.conflicts.isEmpty)
        // Stored overrides that collide (an older Settings file) are marked on both rows.
        let stored = ShortcutTable(overrides: [pin: "⌘P"])
        #expect(stored.conflicts == [Self.k("p", .command): [print, pin]])
    }

    @Test("macOS's own keys and keys without ⌘ or ⌃ are refused; Quit and Settings keep theirs")
    func refusals() {
        var table = ShortcutTable()
        for key in [Self.k("q", .command), Self.k("h", .command), Self.k(",", .command), Self.k("c", .command)] {
            guard case .refused(let message) = table.assign(key, to: pin) else {
                Issue.record("\(key) was not refused")
                continue
            }
            #expect(message.contains(key.description))
        }
        func refused(_ check: ShortcutTable.Check) -> Bool { if case .refused = check { true } else { false } }
        #expect(refused(table.check(Self.k("d", [.shift]), for: pin)))
        #expect(refused(table.check(Self.k("x", [.command, .option]), for: "terminate:")))
        #expect(refused(table.check(Self.k("x", [.command, .option]), for: "showSettings:")))
        #expect(table.overrides.isEmpty)
        #expect(ShortcutTable(overrides: ["terminate:": "⌥⌘X", "nope:": "⌘K", pin: "garbage"]).overrides.isEmpty)
    }

    @Test("Reset restores one row; Reset All restores every row; no key is a key too")
    func reset() {
        var table = ShortcutTable()
        table.assign(Self.k("p", [.command, .option]), to: pin)
        table.assign(Self.k("t", [.command, .option]), to: reopen)
        table.assign(nil, to: "toggleMute:")
        #expect(table.key(for: "toggleMute:") == nil && table.overrides["toggleMute:"] == "")
        table.reset(pin)
        #expect(table.key(for: pin) == Self.k("d", .command) && table.overrides.count == 2)
        table.resetAll()
        #expect(table == ShortcutTable())
        // Assigning the default back drops the override.
        table.assign(Self.k("p", [.command, .option]), to: pin)
        table.assign(Self.k("d", .command), to: pin)
        #expect(table.overrides.isEmpty)
    }

    @Test("Key strings round-trip for every default key")
    func strings() {
        for action in ShortcutTable.actions {
            guard let key = action.defaultKey else { continue }
            #expect(ShortcutTable.parse(ShortcutTable.string(key)) == key, "\(action.title) \(key)")
        }
        #expect(ShortcutTable.parse("⌘") == nil && ShortcutTable.parse("D") == nil && ShortcutTable.parse("") == nil)
    }

    @Test("A recorded key is named as the table names it (⇧⌘2 arrives as \"@\", ⇧⌘[ as \"{\")")
    func recordedKeys() {
        #expect(ReservedShortcuts.shortcut(for: key("@", code: 19, [.command, .shift])) == Self.k("2", [.command, .shift]))
        #expect(ReservedShortcuts.shortcut(for: key("{", code: 33, [.command, .shift])) == Self.k("[", [.command, .shift]))
        #expect(ReservedShortcuts.shortcut(for: key("p", code: 35, [.command, .option, .function])) == Self.k("p", [.command, .option]))
        #expect(ReservedShortcuts.shortcut(for: key("\u{F701}", code: 125, [.command, .option])) == Shortcut(.downArrow, [.command, .option]))
    }
}
