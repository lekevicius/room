import AppKit
import Omnibox

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
    public static let reopenClosedTab = "Reopen Closed Tab"
    public static let nextTab = "Select Next Tab"
    public static let previousTab = "Select Previous Tab"
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

/// Drops from outside the window (spec §A.9); `URLFixup` itself lives in
/// the `Omnibox` package with the palette's verbatim row.
extension URLFixup {
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
