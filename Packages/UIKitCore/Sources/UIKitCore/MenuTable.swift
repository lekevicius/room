import AppKit

/// One item of the main menu (ROADMAP 2.8 task 1). Every row of
/// `docs/shortcuts.md` is one or more of these, named by its Action cell in
/// `row`; the rest are the Mac's standard items (About, Undo, Minimize …).
///
/// `action` is a selector name. Room's commands (`.app`) target the app
/// delegate directly with their own selector names (AGENTS.md: never an
/// AppKit action name, NSWindow answers those first); AppKit's own actions
/// (`.responderChain`: Undo, Copy, Close Window, Minimize, Full Screen …) go
/// through the responder chain as in every Mac app.
public struct MenuItemSpec: Sendable {
    public enum Target: Sendable { case app, responderChain }

    public var title: String
    public var action: String?
    public var key: ReservedShortcuts.Shortcut?
    public var tag = 0
    public var target = Target.app
    /// The `docs/shortcuts.md` row (its Action cell, verbatim).
    public var row: String?
    /// Not built yet: the item is present and disabled, its tooltip names the chapter.
    public var chapter: String?
    /// A key the menu cannot carry without taking it from every field (Esc, Return),
    /// shown in the tooltip.
    public var hint: String?
    /// A second key for an item above it: hidden, its key equivalent still works.
    public var isAlias = false
    /// Names the action in Settings ▸ Shortcuts and `Settings.shortcutOverrides`
    /// (4.4a): the selector, the tag when it is not 0, "~alias" for an alias;
    /// given where two items share selector and tag (Next Tab in Sidebar).
    public var id: String {
        if let explicitID { return explicitID }
        return (action ?? "planned:\(title)") + (tag == 0 ? "" : "#\(tag)") + (isAlias ? "~alias" : "")
    }
    private var explicitID: String?

    public init(_ title: String, _ action: String?, key: ReservedShortcuts.Shortcut? = nil, tag: Int = 0, target: Target = .app,
                row: String? = nil, chapter: String? = nil, hint: String? = nil, isAlias: Bool = false, id: String? = nil) {
        self.explicitID = id
        self.title = title
        self.action = action
        self.key = key
        self.tag = tag
        self.target = target
        self.row = row
        self.chapter = chapter
        self.hint = hint
        self.isAlias = isAlias
    }

    /// The tooltip: the chapter for a planned item, else the key the menu cannot show.
    public var toolTip: String? {
        if let chapter { return "Comes in Chapter \(chapter)" }
        return hint
    }
}

public enum MenuNode: Sendable {
    case item(MenuItemSpec)
    case separator
    case submenu(String, [MenuNode])

    /// Every item in this node and below it.
    public var items: [MenuItemSpec] {
        switch self {
        case .item(let item): [item]
        case .separator: []
        case .submenu(_, let nodes): nodes.flatMap(\.items)
        }
    }
}

public struct MenuSpec: Sendable {
    public var title: String
    public var nodes: [MenuNode]

    public init(_ title: String, _ nodes: [MenuNode]) {
        self.title = title
        self.nodes = nodes
    }

    public var items: [MenuItemSpec] { nodes.flatMap(\.items) }
}

/// The main menu bar as data: App, File, Edit, View, History, Tab, Spaces
/// (Room's own), Debug (DEBUG builds, passed in), Window, Help.
public enum MainMenuTable {
    /// The rows of `docs/shortcuts.md` that are not a menu item, and why.
    public static let rowsWithoutItem: [String: String] = [
        "Open link in Peek": "a pointer gesture (⇧-click on a link); the page's context menu has Open Link in Peek",
    ]

    public static func menus(appName: String = "Room", debug: [MenuNode] = []) -> [MenuSpec] {
        var menus = [app(appName), file, edit, view, history, tab, spaces]
        if !debug.isEmpty { menus.append(MenuSpec("Debug", debug)) }
        menus += [window, help]
        return menus
    }

    public static var allItems: [MenuItemSpec] { menus(debug: []).flatMap(\.items) }

    /// Settings' sections in their toolbar order (the app's
    /// `SettingsWindowController.Section`); tag `i + 1` opens section `i`.
    public static let settingsSections = ["General", "Appearance", "Search", "Downloads", "Shortcuts", "Spaces", "Extensions", "Privacy"]

    // MARK: Menus

    private static func app(_ name: String) -> MenuSpec {
        MenuSpec(name, [
            item("About \(name)", "orderFrontStandardAboutPanel:", target: .responderChain),
            // Sparkle, a check the user asks for (ROADMAP 2.8 task 5).
            item("Check for Updates…", "checkForAppUpdates:"),
            .separator,
            item("Settings…", "showSettings:", key: k(",", .command), row: "Settings"),
            // One item per Settings section (4.4b), without keys: the palette's "Settings ▸ …" commands.
            .submenu("Settings Section", settingsSections.enumerated().map { index, title in
                item(title, "showSettingsSection:", tag: index + 1)
            }),
            // The system's confirmation dialog (ROADMAP 2.8 task 3).
            item("Set as Default Browser…", "makeDefaultBrowser:"),
            .separator,
            .submenu("Services", []),
            .separator,
            item("Hide \(name)", "hide:", key: k("h", .command), target: .responderChain),
            // ⌥⌘H stays Hide Others, the macOS standard (B-36, docs/shortcuts.md 2026-10-04).
            item("Hide Others", "hideOtherApplications:", key: k("h", [.command, .option]), target: .responderChain),
            item("Show All", "unhideAllApplications:", target: .responderChain),
            .separator,
            item("Quit \(name)", "terminate:", key: k("q", .command), target: .responderChain, row: "Quit"),
        ])
    }

    private static let file = MenuSpec("File", [
        item("New Tab", "newPage:", key: k("t", .command), row: "New tab (palette)"),
        item("New Window", "newRoomWindow:", key: k("n", .command), row: "New window"),
        item("New Incognito Window", nil, key: k("n", [.command, .shift]), row: "New incognito window", chapter: "4.8"),
        item("New Space", "newSpace:"),
        .separator,
        item("Open Location…", "openLocation:", key: k("l", .command), row: "Edit current URL (palette)"),
        item("Open File…", "openFileInTab:"),
        item("Commands…", "showCommands:", row: "Palette actions mode", hint: "⌘T then Tab, or type >"),
        .separator,
        item("Close Tab", "closeTab:", key: k("w", .command), row: "Close tab / pane (permanent entry: unload + reset + switch)"),
        item("Close Window", "performClose:", key: k("w", [.command, .shift]), target: .responderChain, row: "Close window"),
        item("Reopen Closed Tab", "reopenClosedTab:", key: k("t", [.command, .shift]), row: "Reopen closed tab (incl. Peek)"),
        .separator,
        item("Capture Screenshot", nil, key: k("2", [.command, .shift]), row: "Capture screenshot", chapter: "4.7"),
        item("Print…", "printPage:", key: k("p", .command)),
    ])

    private static let edit = MenuSpec("Edit", [
        item("Undo", "undo:", key: k("z", .command), target: .responderChain),
        item("Redo", "redo:", key: k("z", [.command, .shift]), target: .responderChain),
        .separator,
        item("Cut", "cut:", key: k("x", .command), target: .responderChain),
        item("Copy", "copy:", key: k("c", .command), target: .responderChain),
        item("Paste", "paste:", key: k("v", .command), target: .responderChain),
        item("Select All", "selectAll:", key: k("a", .command), target: .responderChain),
        .separator,
        item("Copy URL", "copyPageURL:", key: k("c", [.command, .shift]), row: "Copy URL / as Markdown"),
        item("Copy URL as Markdown", "copyPageURL:", key: k("c", [.command, .shift, .option]), tag: 1, row: "Copy URL / as Markdown"),
        .separator,
        .submenu("Find", [
            item("Find…", "showFindBar:", key: k("f", .command), row: "Find / next / previous"),
            item("Find Next", "findNext:", key: k("g", .command), tag: 1, row: "Find / next / previous"),
            item("Find Previous", "findNext:", key: k("g", [.command, .shift]), tag: -1, row: "Find / next / previous"),
        ]),
    ])

    private static let view = MenuSpec("View", [
        item("Hide Sidebar", "hideOrShowSidebar:", key: k("s", .command), row: "Toggle sidebar"),
        item("Keep Sidebar Open", "keepSidebarOpen:", key: k("s", [.command, .option]), row: "Pin overlay sidebar open"),
        item("Show Toolbar", "toggleToolbar:"),
        .separator,
        item("Reload Page", "reloadPage:", key: k("r", .command), row: "Reload / hard reload / stop"),
        item("Reload Ignoring Cache", "reloadIgnoringCache:", key: k("r", [.command, .shift]), row: "Reload / hard reload / stop"),
        item("Stop", "stopLoading:", key: k(".", .command), row: "Reload / hard reload / stop"),
        .separator,
        item("Actual Size", "zoomPage:", key: k("0", .command), tag: 0, row: "Zoom in / out / reset"),
        item("Zoom In", "zoomPage:", key: k("=", .command), tag: 1, row: "Zoom in / out / reset"),
        item("Zoom Out", "zoomPage:", key: k("-", .command), tag: -1, row: "Zoom in / out / reset"),
        .separator,
        item("Reader Mode", nil, key: k("r", [.command, .shift, .option]), row: "Reader mode", chapter: "4.7"),
        // AppKit's own action: the window retitles it (Exit Full Screen) and no second item is added.
        item("Enter Full Screen", "toggleFullScreen:", key: k("f", [.command, .control]), target: .responderChain, row: "Fullscreen"),
        .separator,
        .submenu("Developer", [
            item("Developer Tools", "toggleDevTools:", key: k("i", [.command, .option]), row: "Developer tools / inspect / console"),
            item("JavaScript Console", "showJavaScriptConsole:", key: k("j", [.command, .option]),
                 row: "Developer tools / inspect / console"),
            item("Inspect Elements", "inspectElements:", key: k("c", [.command, .option]), row: "Developer tools / inspect / console"),
        ]),
    ])

    private static let history = MenuSpec("History", [
        item("Back", "goBack:", key: k("[", .command), row: "Back / forward"),
        item("Forward", "goForward:", key: k("]", .command), row: "Back / forward"),
        // ⌘← / ⌘→ outside text fields (validated off while a field edits, so the field keeps them).
        item("Back", "goBack:", key: ReservedShortcuts.Shortcut(.leftArrow, .command), tag: 2, row: "Back / forward", isAlias: true),
        item("Forward", "goForward:", key: ReservedShortcuts.Shortcut(.rightArrow, .command), tag: 2, row: "Back / forward", isAlias: true),
        .separator,
        // The Library in the sidebar (4.1a): ⌘Y opens it at History, ⇧⌘L toggles it.
        item("Show History", "showHistory:", key: k("y", .command), row: "History"),
        item("Show Library", "toggleLibrary:", key: k("l", [.command, .shift]), row: "Library / archive"),
    ])

    private static let tab = MenuSpec("Tab", [
        item("Select Next Tab", "selectAdjacentTab:", key: k("]", [.command, .shift]), tag: 1, row: "Next / previous tab"),
        item("Select Previous Tab", "selectAdjacentTab:", key: k("[", [.command, .shift]), tag: -1, row: "Next / previous tab"),
        item("Next Tab in Sidebar", "selectAdjacentTab:", key: ReservedShortcuts.Shortcut(.downArrow, [.command, .option]), tag: 1,
             row: "Next / previous tab in sidebar order", id: "selectAdjacentTab:#1.sidebar"),
        item("Previous Tab in Sidebar", "selectAdjacentTab:", key: ReservedShortcuts.Shortcut(.upArrow, [.command, .option]), tag: -1,
             row: "Next / previous tab in sidebar order", id: "selectAdjacentTab:#-1.sidebar"),
        // ⌃Tab is held for the switcher (TabSwitcher sees it first); the item switches once.
        item("Switch to Recent Tab", "switchToRecentTab:", key: ReservedShortcuts.Shortcut(.tab, .control), tag: 1,
             row: "MRU switcher / backwards", hint: "Hold ⌃ and press Tab to pick from the five most recent"),
        item("Switch Back", "switchToRecentTab:", key: ReservedShortcuts.Shortcut(.tab, [.control, .shift]), tag: -1,
             row: "MRU switcher / backwards"),
        .submenu("Go to Tab", (1...9).map { digit in
            item(digit == 9 ? "Last Tab" : "Tab \(digit)", "selectTabByNumber:", key: k("\(digit)", .command), tag: digit,
                 row: "Sidebar item 1–8, last")
        }),
        .separator,
        item("Pin Tab", "togglePin:", key: k("d", .command), row: "Pin / unpin"),
        item("Add to Essentials", "toggleEssentials:", key: k("d", [.command, .shift]), row: "Add to / remove from Essentials"),
        item("Mute Tab", "toggleMute:", key: k("m", [.command, .shift]), row: "Mute tab"),
        item("Rename…", "renameSelected:", row: "Rename entry", hint: "Return on a focused row, or double-click"),
        item("Duplicate Tab", "duplicateSelected:", row: "Duplicate tab, unload tab, reset pinned entry"),
        item("Unload Tab", "unloadSelected:", row: "Duplicate tab, unload tab, reset pinned entry"),
        item("Reset Pinned Tab", "resetSelected:", row: "Duplicate tab, unload tab, reset pinned entry"),
        .separator,
        item("Clear Today Tabs", "clearTodayTabs:", key: k("k", [.command, .shift]), row: "Clear Today tabs"),
        .separator,
        .submenu("Split View", [
            item("New Split View", "newSplitPane:", key: k("=", [.command, .shift]), row: "New split (empty pane)"),
            item("New Split View", "newSplitPane:", key: k("=", [.control, .shift]), row: "New split (empty pane)", isAlias: true),
            item("Remove from Split View", "removeSplitPane:", key: k("-", [.control, .shift]), row: "Remove split pane"),
            .separator,
            item("Grid", "setSplitLayout:", key: k("g", [.command, .option]), tag: 0,
                 row: "Split layout grid / vertical / horizontal / unsplit"),
            item("Side by Side", "setSplitLayout:", key: k("v", [.command, .option]), tag: 1,
                 row: "Split layout grid / vertical / horizontal / unsplit"),
            // No key: ⌥⌘H is Hide Others (B-36).
            item("Stacked", "setSplitLayout:", tag: 2, row: "Split layout grid / vertical / horizontal / unsplit"),
            item("Unsplit", "unsplit:", key: k("u", [.command, .option]), row: "Split layout grid / vertical / horizontal / unsplit"),
            .separator,
        ] + (1...4).map { number in
            item("Focus Pane \(number)", "focusSplitPane:", key: k("\(number)", [.control, .shift]), tag: number,
                 row: "Focus split pane N / next / previous")
        } + [
            item("Focus Next Pane", "focusAdjacentPane:", key: k("]", [.control, .shift]), tag: 1, row: "Focus split pane N / next / previous"),
            item("Focus Previous Pane", "focusAdjacentPane:", key: k("[", [.control, .shift]), tag: -1,
                 row: "Focus split pane N / next / previous"),
        ]),
        .separator,
        item("Open Peek as Tab", "expandPeek:", key: k("o", .command), row: "Expand Peek to tab / Peek to split"),
        item("Open Peek in Split View", "splitPeek:", key: k("o", [.command, .shift]), row: "Expand Peek to tab / Peek to split"),
        item("Close Peek", "closePeek:", row: "Close Peek", hint: "Esc, or ⌘W"),
    ])

    private static let spaces = MenuSpec("Spaces", [
        item("Next Space", "selectAdjacentSpace:", key: ReservedShortcuts.Shortcut(.rightArrow, [.command, .option]), tag: 1,
             row: "Next / previous space"),
        item("Previous Space", "selectAdjacentSpace:", key: ReservedShortcuts.Shortcut(.leftArrow, [.command, .option]), tag: -1,
             row: "Next / previous space"),
        .separator,
    ] + [1, 2, 3, 4, 5, 6, 7, 8, 9, 0].map { digit in
        item("Space \(digit == 0 ? 10 : digit)", "selectSpaceByNumber:", key: k("\(digit)", .control), tag: digit, row: "Space 1–9, 10")
    } + [
        .separator,
        item("New Space", "newSpace:"),
    ])

    private static let window = MenuSpec("Window", [
        item("Minimize", "performMiniaturize:", key: k("m", .command), target: .responderChain),
        item("Zoom", "performZoom:", target: .responderChain),
        .separator,
        item("Downloads", "showDownloads:", key: k("j", [.command, .shift]), row: "Downloads popover"),
        .separator,
        item("Bring All to Front", "arrangeInFront:", target: .responderChain),
    ])

    /// AppKit adds the search field to the Help menu. Restore Sidebar… lists
    /// the rolling backups (spec §H, 4.1b).
    private static let help = MenuSpec("Help", [
        item("Restore Sidebar…", "showRestoreSidebar:"),
    ])

    // MARK: Building blocks

    private static func k(_ character: String, _ modifiers: NSEvent.ModifierFlags) -> ReservedShortcuts.Shortcut {
        ReservedShortcuts.Shortcut(.character(character), modifiers)
    }

    private static func item(_ title: String, _ action: String?, key: ReservedShortcuts.Shortcut? = nil, tag: Int = 0,
                             target: MenuItemSpec.Target = .app, row: String? = nil, chapter: String? = nil, hint: String? = nil,
                             isAlias: Bool = false, id: String? = nil) -> MenuNode {
        .item(MenuItemSpec(title, action, key: key, tag: tag, target: target, row: row, chapter: chapter, hint: hint, isAlias: isAlias,
                           id: id))
    }
}

/// How a shortcut becomes an `NSMenuItem` key equivalent. AppKit matches an
/// equivalent against the event's characters, which already carry Shift: a
/// shifted key is named by the character it types on the US layout (⇧⌘] is
/// "}", ⌃⇧1 is "!"), never by its base key with a Shift mask, which a real
/// key press never matches (found in 2.3 with ⇧⌘T, in 2.7b with ⌃⇧1).
public enum MenuKey {
    public static func equivalent(for shortcut: ReservedShortcuts.Shortcut) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        var modifiers = shortcut.modifiers
        let key: String
        switch shortcut.key {
        case .leftArrow: key = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case .rightArrow: key = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case .upArrow: key = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case .downArrow: key = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case .tab: key = "\t"
        case .character(let character):
            if modifiers.contains(.shift) {
                if let shifted = shiftedUS[character] {
                    key = shifted
                    modifiers.remove(.shift)
                } else {
                    // A letter: the capital carries the Shift.
                    key = character.uppercased()
                }
            } else {
                key = character
            }
        }
        return (key, modifiers)
    }

    /// The US layout's shifted characters for the digits and punctuation the table uses.
    public static let shiftedUS: [String: String] = [
        "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&", "8": "*", "9": "(", "0": ")",
        "-": "_", "=": "+", "[": "{", "]": "}", ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "`": "~", "\\": "|",
    ]
}

/// Builds the `NSMenu` bar from `MainMenuTable` (ROADMAP 2.8 task 1).
public enum MainMenuBuilder {
    /// `appTarget` receives every `.app` action (the app delegate); `nil` leaves them
    /// to the responder chain (tests).
    public static func make(_ menus: [MenuSpec], appTarget: AnyObject?) -> NSMenu {
        let bar = NSMenu(title: "Main Menu")
        for spec in menus {
            let menu = NSMenu(title: spec.title)
            add(spec.nodes, to: menu, appTarget: appTarget)
            let item = NSMenuItem(title: spec.title, action: nil, keyEquivalent: "")
            item.submenu = menu
            bar.addItem(item)
        }
        return bar
    }

    private static func add(_ nodes: [MenuNode], to menu: NSMenu, appTarget: AnyObject?) {
        for node in nodes {
            switch node {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let title, let children):
                let submenu = NSMenu(title: title)
                add(children, to: submenu, appTarget: appTarget)
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.submenu = submenu
                menu.addItem(item)
            case .item(let spec):
                menu.addItem(makeItem(spec, appTarget: appTarget))
            }
        }
    }

    /// Sets every item's key equivalent from `table` in place (4.4a: a remap
    /// changes the bar without rebuilding it, so the Window menu keeps its
    /// windows); an id that two items share (New Space) keys the first only.
    /// Returns the number of items whose key changed.
    @discardableResult
    public static func apply(_ table: ShortcutTable, to menu: NSMenu) -> Int {
        var seen = Set<String>()
        var changed = 0
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { walk(submenu) }
                guard let id = item.identifier?.rawValue, table.action(id) != nil else { continue }
                let key = seen.insert(id).inserted ? table.key(for: id) : nil
                let equivalent: (key: String, modifiers: NSEvent.ModifierFlags) = key.map { MenuKey.equivalent(for: $0) } ?? ("", [])
                let mask = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
                if item.keyEquivalent != equivalent.key || (!equivalent.key.isEmpty && mask != equivalent.modifiers) {
                    item.keyEquivalent = equivalent.key
                    item.keyEquivalentModifierMask = equivalent.modifiers
                    changed += 1
                }
            }
        }
        walk(menu)
        return changed
    }

    public static func makeItem(_ spec: MenuItemSpec, appTarget: AnyObject?) -> NSMenuItem {
        // A planned item has no action: AppKit shows it disabled and its key does nothing.
        let action = spec.chapter == nil ? spec.action.map(NSSelectorFromString) : nil
        let item = NSMenuItem(title: spec.title, action: action, keyEquivalent: "")
        if let key = spec.key {
            let equivalent = MenuKey.equivalent(for: key)
            item.keyEquivalent = equivalent.key
            item.keyEquivalentModifierMask = equivalent.modifiers
        }
        item.tag = spec.tag
        item.identifier = NSUserInterfaceItemIdentifier(spec.id)
        if spec.target == .app, action != nil { item.target = appTarget }
        item.toolTip = spec.toolTip
        if spec.isAlias {
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
        }
        return item
    }
}
