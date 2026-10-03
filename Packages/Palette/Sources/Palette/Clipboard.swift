import AppKit

/// The clipboard as Paste & Go needs it (spec §C): whether it holds a URL,
/// asked without reading it, and the text, read only when the row is chosen.
public protocol PaletteClipboard {
    /// Changes whenever the clipboard's contents do (metadata, no prompt).
    var changeCount: Int { get }
    /// Whether the clipboard probably holds a web URL, without reading it.
    func detectURL(_ completion: @escaping @MainActor (Bool) -> Void)
    /// The clipboard's text (may show the system's paste-access prompt).
    func readString() -> String?
}

/// `NSPasteboard.general`: `detectedPatterns(for:)` reports a probable URL
/// without the macOS 26 paste-access prompt that reading would raise.
public struct SystemClipboard: PaletteClipboard {
    public init() {}

    public var changeCount: Int { NSPasteboard.general.changeCount }

    public func detectURL(_ completion: @escaping @MainActor (Bool) -> Void) {
        Task { @MainActor in
            let url: PartialKeyPath<NSPasteboard.DetectedValues> = \.probableWebURL
            let found = (try? await NSPasteboard.general.detectedPatterns(for: [url]))?.contains(url) ?? false
            completion(found)
        }
    }

    public func readString() -> String? { NSPasteboard.general.string(forType: .string) }
}
