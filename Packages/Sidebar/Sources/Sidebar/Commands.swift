import Foundation

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
}
