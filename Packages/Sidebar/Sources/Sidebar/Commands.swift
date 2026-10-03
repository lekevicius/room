import AppKit

/// Command names shared by the sidebar's menus and, from Phase 2.4, the
/// palette's command list, so users learn one vocabulary (spec §I.10). Names
/// in the palette list (spec §C) are used as is; the rest come from §A.6/§A.8.
public enum CommandName {
    public static let newTab = "New Tab"
    public static let newFolder = "New Folder"
    public static let newSplit = "New Split View"
    public static let newSpace = "New Space"
    public static let pinTab = "Pin Tab"
    public static let unpinTab = "Unpin Tab"
    public static let addToEssentials = "Add to Essentials"
    public static let removeFromEssentials = "Remove from Essentials"
    public static let moveTo = "Move To"
    public static let moveToFolder = "Move to Folder"
    public static let newFolderWithTab = "New Folder with Tab"
    public static let splitWith = "Split With…"
    public static let duplicateTab = "Duplicate Tab"
    public static let rename = "Rename…"
    public static let changeIcon = "Change Icon…"
    public static let copyURL = "Copy URL"
    public static let copyMarkdown = "Copy URL as Markdown"
    public static let reload = "Reload"
    public static let muteTab = "Mute Tab"
    public static let unmuteTab = "Unmute Tab"
    public static let unloadTab = "Unload Tab"
    public static let archiveBelow = "Archive Tabs Below"
    public static let closeTabsBelow = "Close Tabs Below"
    public static let closeOtherTabs = "Close Other Tabs"
    public static let closeTab = "Close Tab"
    public static let pinnedURL = "Pinned URL"
    public static let resetPinnedTab = "Reset Pinned Tab"
    public static let replacePinnedURL = "Replace Pinned URL with Current"
    public static let editPinnedURL = "Edit Pinned URL…"
    public static let remove = "Remove"
    // Folders (spec §A.6)
    public static let newSubfolder = "New Subfolder"
    public static let unloadAllTabs = "Unload All Tabs"
    public static let copyAllLinks = "Copy All Links"
    public static let pasteURLAsNewTab = "Paste URL as New Tab"
    public static let convertToSpace = "Convert to Space"
    public static let moveToSpace = "Move to Space"
    public static let unpack = "Unpack Folder"
    public static let deleteFolder = "Delete Folder…"
    public static let clearToday = "Clear Today Tabs"
    // Multi-selection (spec §A.9, §A.6)
    public static func pinTabs(_ count: Int) -> String { "Pin \(count) Tabs" }
    public static func unpinTabs(_ count: Int) -> String { "Unpin \(count) Tabs" }
    public static func addTabsToEssentials(_ count: Int) -> String { "Add \(count) Tabs to Essentials" }
    public static func removeTabsFromEssentials(_ count: Int) -> String { "Remove \(count) Tabs from Essentials" }
    public static func newFolderWithTabs(_ count: Int) -> String { "New Folder with \(count) Tabs" }
    public static func copyURLs(_ count: Int) -> String { count == 1 ? "Copy URL" : "Copy \(count) URLs" }
    public static func unloadTabs(_ count: Int) -> String { count == 1 ? "Unload Tab" : "Unload \(count) Tabs" }
    public static func closeTabs(_ count: Int) -> String { "Close \(count) Tabs" }
    public static func removeTabs(_ count: Int) -> String { "Remove \(count) Tabs" }
}

/// "Edit Pinned URL…" and "Paste URL as New Tab" input (spec §A.5): adds a
/// scheme to bare hosts; refuses text that is not a URL.
public enum URLFixup {
    private static let schemes: Set<String> = ["http", "https", "file", "about", "data", "chrome", "view-source"]

    public static func url(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        if let colon = trimmed.firstIndex(of: ":") {
            let scheme = trimmed[..<colon].lowercased()
            if schemes.contains(scheme) {
                guard let components = URLComponents(string: trimmed) else { return nil }
                if scheme == "http" || scheme == "https" { guard components.host?.isEmpty == false else { return nil } }
                return trimmed
            }
        }
        // A bare host (with optional port, path, query): needs a dot or be localhost.
        guard let components = URLComponents(string: "https://" + trimmed), let host = components.host, !host.isEmpty else {
            return nil
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let isLocal = host == "localhost" || host.hasSuffix(".localhost")
        guard isLocal || (labels.count >= 2 && labels.allSatisfy { !$0.isEmpty }) else { return nil }
        let scheme = isLocal ? "http://" : "https://"
        return scheme + trimmed
    }

    /// Plain text dropped on the sidebar becomes a search tab (spec §A.9).
    /// Google until the palette's search engine setting (Phase 2.4, backlog B-12).
    public static func searchURL(for text: String) -> String {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text.trimmingCharacters(in: .whitespacesAndNewlines))]
        return components.url!.absoluteString
    }

    /// What a drop from outside the window opens (spec §A.9, §I.7): every
    /// URL or file on the pasteboard, else each line of text if all are
    /// URLs, else one search for the text.
    public static func dropURLs(from pasteboard: NSPasteboard) -> [String] {
        let allowed: Set<String> = ["http", "https", "file"]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let accepted = urls.filter { allowed.contains($0.scheme?.lowercased() ?? "") }.map(\.absoluteString)
            if !accepted.isEmpty { return accepted }
        }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return []
        }
        let lines = text.split(whereSeparator: \.isNewline).map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let urls = lines.compactMap(url(from:))
        if !urls.isEmpty, urls.count == lines.count { return urls }
        return [searchURL(for: text)]
    }
}
