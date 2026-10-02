import AppKit

/// Key equivalents the page never sees (PLAN §2.4): the engine hands them
/// straight to the main menu. Phase 1.6 freezes the final set.
enum ReservedShortcuts {
    /// ⌘ + character (`charactersIgnoringModifiers`, lower-cased).
    static let command: Set<String> = ["t", "l", "w", "n", "q", "s", ","]
    /// ⌘⇧ + character.
    static let commandShift: Set<String> = ["w", "t"]

    static func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = normalizedKey(event) else { return false }
        switch flags {
        case [.command]: return command.contains(key)
        case [.command, .shift]: return commandShift.contains(key)
        default: return false
        }
    }

    /// The Latin key for the event even on non-Latin layouts: macOS gives
    /// `charactersIgnoringModifiers` in the current layout, so fall back to
    /// the US key for the key code when that is not ASCII.
    static func normalizedKey(_ event: NSEvent) -> String? {
        let characters = (event.charactersIgnoringModifiers ?? "").lowercased()
        if let scalar = characters.unicodeScalars.first, scalar.isASCII { return characters }
        return usKeys[event.keyCode]
    }

    /// ANSI key codes (`kVK_ANSI_*`) for letters, digits and punctuation used above.
    private static let usKeys: [UInt16: String] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j",
        40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t",
        32: "u", 9: "v", 13: "w", 7: "x", 16: "y", 6: "z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        43: ",", 47: ".", 50: "`",
    ]
}
