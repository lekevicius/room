import AppKit

/// Shortcut remapping (ROADMAP 4.4a task 1, spec §G "all shortcuts
/// remappable"): every action of the main menu with its default key from
/// `MainMenuTable` (which `docs/shortcuts.md` is checked against) and the
/// user's overrides (`Settings.shortcutOverrides` in `kv`: action id → key
/// string, `""` for no key; an absent id keeps its default). The menu, the
/// palette's hints, the sidebar's context menus and the reserved set are all
/// read from one table, so a remap moves the key everywhere at once.
///
/// The reserved set follows the actions, not the keys: an action whose
/// default key is reserved (`ReservedShortcuts.all`) stays reserved under its
/// new key, and its old key reaches the page like any other.
public struct ShortcutTable: Sendable, Equatable {
    public typealias Shortcut = ReservedShortcuts.Shortcut

    /// One remappable row: a menu item (or, for the few macOS owns, a fixed row).
    public struct Action: Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        /// The menu path ("Tab", "Tab ▸ Split View").
        public let menu: String
        public let defaultKey: Shortcut?
        /// The page never sees this action's key (PLAN §2.4), whatever the key is.
        public let isReserved: Bool
        /// Why the key cannot change (macOS's own, or a held gesture); `nil` if it can.
        public let fixed: String?
        /// A planned item's chapter (its key works once the chapter builds it).
        public let chapter: String?
        public let isAlias: Bool

        /// "Tab ▸ Pin Tab", the second key of an alias named as such.
        public var displayTitle: String { isAlias ? "\(title) (second key)" : title }
    }

    /// What a proposed key would do to an action.
    public enum Check: Sendable, Equatable {
        /// Takes effect.
        case ok
        /// The action already has that key.
        case unchanged
        /// Refused, with the message Settings shows.
        case refused(String)
        /// Other actions have the key: both are marked, and the new one wins only when confirmed.
        case conflict([String])
    }

    /// Keys macOS or the page's editing needs: refused for every action, with the reason.
    public static let systemKeys: [Shortcut: String] = makeSystemKeys()

    private static func makeSystemKeys() -> [Shortcut: String] {
        func k(_ c: String, _ m: NSEvent.ModifierFlags) -> Shortcut { Shortcut(.character(c), m) }
        let owner = "belongs to macOS"
        return [
            k("q", .command): "⌘Q is Quit: it \(owner).",
            k("h", .command): "⌘H is Hide Room: it \(owner).",
            k("h", [.command, .option]): "⌥⌘H is Hide Others: it \(owner).",
            k("m", .command): "⌘M is Minimize: it \(owner).",
            k(",", .command): "⌘, is Settings: it \(owner).",
            k("`", .command): "⌘` moves between windows: it \(owner).",
            k("`", [.command, .shift]): "⇧⌘` moves between windows: it \(owner).",
            k(" ", .command): "⌘Space is Spotlight: it \(owner).",
            k(" ", [.command, .control]): "⌃⌘Space is the Character Viewer: it \(owner).",
            k("3", [.command, .shift]): "⇧⌘3 takes a screenshot: it \(owner).",
            k("4", [.command, .shift]): "⇧⌘4 takes a screenshot: it \(owner).",
            k("5", [.command, .shift]): "⇧⌘5 takes a screenshot: it \(owner).",
            k("q", [.command, .control]): "⌃⌘Q locks the screen: it \(owner).",
            k("/", [.command, .shift]): "⇧⌘/ searches the Help menu: it \(owner).",
            k("c", .command): "⌘C is Copy: pages and fields need it.",
            k("v", .command): "⌘V is Paste: pages and fields need it.",
            k("x", .command): "⌘X is Cut: pages and fields need it.",
            k("z", .command): "⌘Z is Undo: pages and fields need it.",
            k("z", [.command, .shift]): "⇧⌘Z is Redo: pages and fields need it.",
            k("a", .command): "⌘A is Select All: pages and fields need it.",
        ]
    }

    /// Every remappable action, in menu order (the bar's items with a key or a Room action).
    public static let actions: [Action] = makeActions()

    private static func makeActions() -> [Action] {
        var actions: [Action] = []
        var seen = Set<String>()
        let reserved = Set(ReservedShortcuts.all)
        func walk(_ nodes: [MenuNode], path: String) {
            for node in nodes {
                switch node {
                case .separator: break
                case .submenu(let title, let children): walk(children, path: "\(path) ▸ \(title)")
                case .item(let item):
                    guard item.target == .app || item.key != nil, seen.insert(item.id).inserted else { continue }
                    let fixed: String? = if let key = item.key, let reason = systemKeys[key] {
                        reason
                    } else if item.key?.key == .tab, item.key?.modifiers.contains(.control) == true {
                        "Held ⌃ with Tab opens the switcher: the key stays."
                    } else {
                        nil
                    }
                    actions.append(Action(id: item.id, title: item.title, menu: path, defaultKey: item.key,
                                          isReserved: item.key.map(reserved.contains) ?? false, fixed: fixed, chapter: item.chapter,
                                          isAlias: item.isAlias))
                }
            }
        }
        for menu in MainMenuTable.menus(debug: []) { walk(menu.nodes, path: menu.title) }
        return actions
    }

    private static let index: [String: Int] = Dictionary(uniqueKeysWithValues: actions.enumerated().map { ($1.id, $0) })

    /// The overrides as stored; ids no action has and strings that name no key are ignored.
    public private(set) var overrides: [String: String]

    public init(overrides: [String: String] = [:]) {
        self.overrides = overrides.filter { id, value in
            guard let action = Self.action(id), action.fixed == nil else { return false }
            return value.isEmpty || Self.parse(value) != nil
        }
    }

    public static func action(_ id: String) -> Action? { index[id].map { actions[$0] } }
    public func action(_ id: String) -> Action? { Self.action(id) }

    /// The action's key now: its override, else its default; `nil` for no key.
    public func key(for id: String) -> Shortcut? {
        if let value = overrides[id] { return value.isEmpty ? nil : Self.parse(value) }
        return Self.action(id)?.defaultKey
    }

    public func isOverridden(_ id: String) -> Bool { overrides[id] != nil }

    /// The keys the page never sees: the reserved actions' current keys.
    public var reservedKeys: Set<Shortcut> {
        Set(Self.actions.filter(\.isReserved).compactMap { key(for: $0.id) })
    }

    public func isReserved(_ event: NSEvent) -> Bool {
        ReservedShortcuts.matches(event, in: reservedKeys)
    }

    /// The actions whose current key is `key`.
    public func actions(using key: Shortcut) -> [Action] {
        Self.actions.filter { self.key(for: $0.id) == key }
    }

    /// Keys two or more actions have now (marked in Settings until resolved).
    public var conflicts: [Shortcut: [String]] {
        var byKey: [Shortcut: [String]] = [:]
        for action in Self.actions {
            if let key = key(for: action.id) { byKey[key, default: []].append(action.id) }
        }
        return byKey.filter { $0.value.count > 1 }
    }

    public func check(_ key: Shortcut?, for id: String) -> Check {
        guard let action = Self.action(id) else { return .refused("Room has no such action.") }
        if let fixed = action.fixed { return .refused(fixed) }
        guard let key else { return self.key(for: id) == nil ? .unchanged : .ok }
        if self.key(for: id) == key { return .unchanged }
        if let reason = Self.systemKeys[key] { return .refused(reason) }
        guard key.modifiers.contains(.command) || key.modifiers.contains(.control) else {
            return .refused("\(key) has no ⌘ or ⌃: it would take the key from every text field.")
        }
        let others = actions(using: key).map(\.id).filter { $0 != id }
        return others.isEmpty ? .ok : .conflict(others)
    }

    /// Gives `id` the key `key` (`nil` = no key) when `check` allows it; with
    /// `replacingConflicts` (the user confirmed) the actions that had the key
    /// lose it. Returns what `check` said.
    @discardableResult
    public mutating func assign(_ key: Shortcut?, to id: String, replacingConflicts: Bool = false) -> Check {
        let result = check(key, for: id)
        switch result {
        case .ok: set(key, for: id)
        case .conflict(let others) where replacingConflicts:
            for other in others { set(nil, for: other) }
            set(key, for: id)
        case .unchanged, .refused, .conflict: break
        }
        return result
    }

    private mutating func set(_ key: Shortcut?, for id: String) {
        if key == Self.action(id)?.defaultKey {
            overrides[id] = nil
        } else {
            overrides[id] = Self.string(key)
        }
    }

    public mutating func reset(_ id: String) { overrides[id] = nil }
    public mutating func resetAll() { overrides = [:] }

    /// `MainMenuTable`'s menus with each item's current key (the bar is built
    /// from these; `MainMenuBuilder.apply` updates a built bar in place).
    public func menus(appName: String = "Room", debug: [MenuNode] = []) -> [MenuSpec] {
        var seen = Set<String>()
        func map(_ nodes: [MenuNode]) -> [MenuNode] {
            nodes.map { node in
                switch node {
                case .separator: return .separator
                case .submenu(let title, let children): return .submenu(title, map(children))
                case .item(var item):
                    if Self.action(item.id) != nil {
                        item.key = seen.insert(item.id).inserted ? key(for: item.id) : nil
                    }
                    return .item(item)
                }
            }
        }
        return MainMenuTable.menus(appName: appName, debug: debug).map { MenuSpec($0.title, map($0.nodes)) }
    }

    // MARK: Key strings ("⌥⌘P", "⌃Tab", "⇧⌘]": `Shortcut.description`)

    public static func string(_ key: Shortcut?) -> String { key?.description ?? "" }

    public static func parse(_ string: String) -> Shortcut? {
        var modifiers: NSEvent.ModifierFlags = []
        var rest = Substring(string)
        let glyphs: [Character: NSEvent.ModifierFlags] = ["⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command]
        while let first = rest.first, let flag = glyphs[first], rest.count > 1 {
            modifiers.insert(flag)
            rest = rest.dropFirst()
        }
        let key: Shortcut.Key
        switch rest {
        case "←": key = .leftArrow
        case "→": key = .rightArrow
        case "↑": key = .upArrow
        case "↓": key = .downArrow
        case "Tab": key = .tab
        case "Space": key = .character(" ")
        default:
            guard rest.count == 1, let scalar = rest.unicodeScalars.first, scalar.isASCII, scalar.value > 0x20 else { return nil }
            key = .character(rest.lowercased())
        }
        guard !modifiers.isEmpty else { return nil }
        return Shortcut(key, modifiers)
    }
}

// MARK: Extension commands (4.5)

/// An extension command's key as Settings ▸ Shortcuts lists it (read-only:
/// the key is changed on Chrome's `chrome://extensions/shortcuts` page), with
/// the Room actions that use the same key: an extension's key runs before
/// Room's menu (the engine's registry while a page has the keyboard, the
/// key router elsewhere, B-70), so such an action loses that key.
public struct ExtensionShortcutRow: Equatable, Sendable {
    public static let note = "Change in chrome://extensions/shortcuts"

    public let extensionName: String
    public let title: String
    /// The key in the table's notation ("⇧⌘U").
    public let shortcut: String
    /// Room actions with the same key (ids), in the table's order.
    public let conflicts: [String]

    public init(extensionName: String, title: String, shortcut: String, conflicts: [String]) {
        self.extensionName = extensionName
        self.title = title
        self.shortcut = shortcut
        self.conflicts = conflicts
    }
}

public extension ShortcutTable {
    /// The rows for `commands` (an extension's name, the command's title, its
    /// key), each with the Room actions on its key under the current overrides.
    func extensionRows(_ commands: [(extension: String, title: String, shortcut: String)]) -> [ExtensionShortcutRow] {
        commands.map { command in
            let conflicts = Self.parse(command.shortcut).map { key in actions(using: key).map(\.id) } ?? []
            return ExtensionShortcutRow(extensionName: command.extension, title: command.title, shortcut: command.shortcut,
                                        conflicts: conflicts)
        }
    }
}
