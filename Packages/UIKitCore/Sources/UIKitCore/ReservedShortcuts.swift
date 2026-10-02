import AppKit

/// Key equivalents the page never sees (PLAN §2.4): the engine hands them
/// straight to the main menu, so a page cannot trap the user. Every other
/// shortcut goes to the page first and reaches the menu only if the page does
/// not handle it (⌘S toggles the sidebar unless a web editor saves with it).
///
/// Frozen in Phase 1.6 (`docs/shortcuts.md`): the escape hatches of the
/// browser frame — new, close, quit, reopen, the palette, and moving between
/// tabs and spaces. Chrome reserves the same kind of set.
public enum ReservedShortcuts {
    public struct Shortcut: Hashable, Sendable, CustomStringConvertible {
        public enum Key: Hashable, Sendable {
            /// The Latin character of the key (layout-independent, see `normalizedKey`).
            case character(String)
            case leftArrow, rightArrow, upArrow, downArrow, tab
        }

        public let key: Key
        public let modifiers: NSEvent.ModifierFlags

        public init(_ key: Key, _ modifiers: NSEvent.ModifierFlags) {
            self.key = key
            self.modifiers = modifiers.intersection(Self.relevant)
        }

        static let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

        public static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
            lhs.key == rhs.key && lhs.modifiers.rawValue == rhs.modifiers.rawValue
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(key)
            hasher.combine(modifiers.rawValue)
        }

        public var description: String {
            var text = ""
            if modifiers.contains(.control) { text += "⌃" }
            if modifiers.contains(.option) { text += "⌥" }
            if modifiers.contains(.shift) { text += "⇧" }
            if modifiers.contains(.command) { text += "⌘" }
            switch key {
            case .character(let character): text += character.uppercased()
            case .leftArrow: text += "←"
            case .rightArrow: text += "→"
            case .upArrow: text += "↑"
            case .downArrow: text += "↓"
            case .tab: text += "Tab"
            }
            return text
        }
    }

    /// The frozen v0 set, in the order of `docs/shortcuts.md`.
    public static let all: [Shortcut] = [
        Shortcut(.character("t"), .command),               // new tab (palette)
        Shortcut(.character("l"), .command),               // edit URL (palette)
        Shortcut(.character("n"), .command),               // new window
        Shortcut(.character("n"), [.command, .shift]),     // new incognito window
        Shortcut(.character("w"), .command),               // close tab / pane
        Shortcut(.character("w"), [.command, .shift]),     // close window
        Shortcut(.character("t"), [.command, .shift]),     // reopen closed tab
        Shortcut(.character("q"), .command),               // quit
        Shortcut(.tab, .control),                          // MRU switcher
        Shortcut(.tab, [.control, .shift]),                // MRU switcher, backwards
        Shortcut(.character("]"), [.command, .shift]),     // next tab
        Shortcut(.character("["), [.command, .shift]),     // previous tab
        Shortcut(.downArrow, [.command, .option]),         // next tab in sidebar order
        Shortcut(.upArrow, [.command, .option]),           // previous tab in sidebar order
        Shortcut(.rightArrow, [.command, .option]),        // next space
        Shortcut(.leftArrow, [.command, .option]),         // previous space
    ]

    private static let set = Set(all)

    public static func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let key = key(for: event) else { return false }
        return set.contains(Shortcut(key, event.modifierFlags))
    }

    /// The layout-independent key of `event`: arrows and Tab by key code,
    /// everything else by the character the active layout produces (so ⌘T is
    /// the key labelled T on Colemak too), falling back to the US key for the
    /// key code when that character is not ASCII (Lithuanian number row,
    /// Cyrillic letters).
    static func key(for event: NSEvent) -> Shortcut.Key? {
        switch event.keyCode {
        case 123: return .leftArrow
        case 124: return .rightArrow
        case 125: return .downArrow
        case 126: return .upArrow
        case 48: return .tab
        default: break
        }
        guard let character = normalizedKey(event) else { return nil }
        return .character(character)
    }

    static func normalizedKey(_ event: NSEvent) -> String? {
        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()
        if let scalar = characters.unicodeScalars.first, scalar.isASCII {
            // `charactersIgnoringModifiers` keeps Shift for punctuation (⌘⇧[ → "{").
            return shiftedPunctuation[characters] ?? characters
        }
        return usKeys[event.keyCode]
    }

    private static let shiftedPunctuation: [String: String] = [
        "{": "[", "}": "]", "<": ",", ">": ".", "~": "`",
    ]

    /// ANSI key codes (`kVK_ANSI_*`) for letters, digits and the punctuation used above.
    private static let usKeys: [UInt16: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j",
        40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t",
        32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        33: "[", 30: "]", 43: ",", 47: ".", 50: "`",
    ]
}
