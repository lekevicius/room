import AppKit
import Sidebar

/// ⌘T and ⌘L until the palette (Phase 2.4 deletes this): a modal prompt.
enum URLPrompt {
    /// The text the user entered, trimmed; `nil` if cancelled or empty.
    static func run(title: String, message: String, text: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: text)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Typed text → a URL: a host or URL as typed (with a scheme), anything else a search.
    static func url(from text: String) -> String {
        URLFixup.url(from: text) ?? URLFixup.searchURL(for: text)
    }
}
