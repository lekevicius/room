import AppKit
import Foundation
import Testing
@testable import UIKitCore

/// The main menu against `docs/shortcuts.md` (ROADMAP 2.8 task 1: every row
/// present with its keys, one table, the reserved set from `ReservedShortcuts`).
@Suite("Main menu table")
struct MenuTableTests {
    struct Row {
        var action: String
        var keys: String
        var isReserved: Bool
        var chapter: String
    }

    /// The table rows of `docs/shortcuts.md`.
    static let rows: [Row] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/shortcuts.md")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { line -> Row? in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 6, line.hasPrefix("|"), cells[1] != "Action", !cells[1].hasPrefix("---") else { return nil }
            return Row(action: cells[1], keys: cells[2], isReserved: cells[3].contains("yes"), chapter: cells[4])
        }
    }()

    /// The shortcuts a Keys cell names, in `ReservedShortcuts.Shortcut.description`
    /// notation: "⌘1…⌘8, ⌘9" and "⌃⇧1…4" are ranges; "⇧-click" and a bare
    /// "Tab" or "Esc" are not menu keys.
    static func shortcuts(in keys: String) -> Set<String> {
        let modifiers = "[⌃⌥⇧⌘]"
        var text = keys
        var found = Set<String>()
        let range = try! NSRegularExpression(pattern: "(\(modifiers)+)(\\d)…(\(modifiers)*)(\\d)")
        for match in range.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let ns = text as NSString
            let prefix = ns.substring(with: match.range(at: 1))
            let first = Int(ns.substring(with: match.range(at: 2)))!, last = Int(ns.substring(with: match.range(at: 4)))!
            for digit in first...last { found.insert(prefix + String(digit)) }
            text = ns.replacingCharacters(in: match.range, with: " ")
        }
        let token = try! NSRegularExpression(pattern: "(\(modifiers)+)(Tab|←|→|↑|↓|[A-Z0-9\\[\\]=\\-.,])(?!click)")
        let ns = text as NSString
        for match in token.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            found.insert(ns.substring(with: match.range(at: 1)) + ns.substring(with: match.range(at: 2)))
        }
        return found
    }

    /// The default table (4.4a: the menu is built from `ShortcutTable`; with no
    /// overrides it is `MainMenuTable`, which these rows check against the doc).
    let items = ShortcutTable().menus(debug: []).flatMap(\.items)

    @Test("The shortcut table's defaults are the frozen menu table, and every keyed or Room item is a row")
    func tableDefaults() {
        let frozen = MainMenuTable.allItems
        #expect(items.map(\.id) == frozen.map(\.id))
        #expect(items.map(\.key) == frozen.map(\.key))
        let ids = Set(ShortcutTable.actions.map(\.id))
        #expect(ids.count == ShortcutTable.actions.count)
        for item in frozen where item.target == .app || item.key != nil {
            #expect(ids.contains(item.id), "\(item.title) is not in the table")
            #expect(ShortcutTable.action(item.id)?.defaultKey == item.key, "\(item.title)")
        }
        // Items sharing an id are the same action (New Space in File and Spaces).
        let byID = Dictionary(grouping: frozen, by: \.id)
        for (id, group) in byID where group.count > 1 {
            #expect(Set(group.map(\.title)).count == 1 && Set(group.map { $0.action ?? "" }).count == 1, "\(id)")
        }
        #expect(Set(ShortcutTable().reservedKeys) == Set(ReservedShortcuts.all))
    }

    @Test("The shortcuts table is read")
    func tableRead() {
        #expect(Self.rows.count >= 40)
        #expect(Self.shortcuts(in: "⌘1…⌘8, ⌘9").count == 9)
        #expect(Self.shortcuts(in: "⌃⇧1…4 / ⌃⇧] / ⌃⇧[") == ["⌃⇧1", "⌃⇧2", "⌃⇧3", "⌃⇧4", "⌃⇧]", "⌃⇧["])
        #expect(Self.shortcuts(in: "⇧-click").isEmpty)
        #expect(Self.shortcuts(in: "⌘[ ⌘] and ⌘← ⌘→ (outside text fields)") == ["⌘[", "⌘]", "⌘←", "⌘→"])
    }

    @Test("Every row of docs/shortcuts.md has a menu item, or a stated reason it has none")
    func everyRowPresent() {
        let named = Set(items.compactMap(\.row))
        for row in Self.rows {
            #expect(named.contains(row.action) || MainMenuTable.rowsWithoutItem[row.action] != nil, "no item for \(row.action)")
        }
        for name in named {
            #expect(Self.rows.contains { $0.action == name }, "item names a row that is not in docs/shortcuts.md: \(name)")
        }
    }

    @Test("Every key a row names is on a menu item, and every item's key is one its row names")
    func keysMatchTheTable() {
        let keyed = Set(items.compactMap { $0.key?.description })
        for row in Self.rows {
            for shortcut in Self.shortcuts(in: row.keys) {
                #expect(keyed.contains(shortcut), "\(shortcut) (\(row.action)) is on no menu item")
            }
        }
        for item in items {
            guard let key = item.key, let name = item.row, let row = Self.rows.first(where: { $0.action == name }) else { continue }
            #expect(Self.shortcuts(in: row.keys).contains(key.description), "\(item.title) has \(key), its row says \(row.keys)")
        }
    }

    @Test("No two menu items share a key")
    func noDuplicateKeys() {
        var seen: [ReservedShortcuts.Shortcut: String] = [:]
        for item in items {
            guard let key = item.key else { continue }
            #expect(seen[key] == nil, "\(key): \(seen[key] ?? "") and \(item.title)")
            seen[key] = item.title
        }
        // The same holds for the key equivalents AppKit matches.
        let menu = MainMenuBuilder.make(MainMenuTable.menus(), appTarget: nil)
        var equivalents = Set<String>()
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { walk(submenu) }
                guard !item.keyEquivalent.isEmpty else { continue }
                let id = "\(item.keyEquivalent)|\(item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]).rawValue)"
                #expect(equivalents.insert(id).inserted, "\(item.title) repeats a key equivalent")
            }
        }
        walk(menu)
    }

    @Test("The reserved rows are exactly UIKitCore.ReservedShortcuts, each on a menu item")
    func reservedSet() {
        let documented = Set(Self.rows.filter(\.isReserved).flatMap { Self.shortcuts(in: $0.keys) })
        #expect(documented == Set(ReservedShortcuts.all.map(\.description)))
        let keyed = Set(items.compactMap(\.key))
        for shortcut in ReservedShortcuts.all {
            #expect(keyed.contains(shortcut), "\(shortcut) is reserved but on no menu item")
        }
    }

    @Test("Rows for a later chapter are disabled items naming it; working items have an action")
    func plannedItems() {
        for item in items {
            if let chapter = item.chapter {
                let built = MainMenuBuilder.makeItem(item, appTarget: nil)
                #expect(built.action == nil && built.toolTip?.contains(chapter) == true, "\(item.title)")
            } else {
                #expect(item.action != nil, "\(item.title) has neither an action nor a chapter")
            }
        }
        // A planned item's chapter is the one the doc gives its row (4.1 made
        // its rows work, so a 4.x row is no longer planned by its number alone).
        for item in items {
            guard let chapter = item.chapter, let row = item.row else { continue }
            #expect(Self.rows.contains { $0.action == row && $0.chapter == chapter }, "\(item.title)")
        }
    }

    @Test("A shifted key is matched by the character it types, not by a Shift mask (2.3: ⇧⌘T, 2.7b: ⌃⇧1)")
    func shiftedEquivalents() {
        func equivalent(_ key: ReservedShortcuts.Shortcut.Key, _ modifiers: NSEvent.ModifierFlags) -> String {
            let result = MenuKey.equivalent(for: ReservedShortcuts.Shortcut(key, modifiers))
            return "\(result.key)|\(result.modifiers.rawValue)"
        }
        #expect(equivalent(.character("]"), [.command, .shift]) == "}|\(NSEvent.ModifierFlags.command.rawValue)")
        #expect(equivalent(.character("1"), [.control, .shift]) == "!|\(NSEvent.ModifierFlags.control.rawValue)")
        #expect(equivalent(.character("="), [.command, .shift]) == "+|\(NSEvent.ModifierFlags.command.rawValue)")
        #expect(MenuKey.equivalent(for: ReservedShortcuts.Shortcut(.character("t"), [.command, .shift])).key == "T")
        #expect(equivalent(.character("="), .command) == "=|\(NSEvent.ModifierFlags.command.rawValue)")
    }
}
