import Foundation

/// A palette command (spec §C group 6). The registry names them; the app
/// decides which can run now, gives each its symbol and runs it by `id`.
public struct OmniboxCommand: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Other words that find it ("hide" finds Toggle Sidebar).
    public var keywords: [String]
    /// SF Symbol name for the row.
    public var symbol: String?
    /// Its key equivalent now ("⌥⌘P", from the app's shortcut table; 4.4a), the row's hint.
    public var shortcut: String?

    public init(id: String, title: String, keywords: [String] = [], symbol: String? = nil, shortcut: String? = nil) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.symbol = symbol
        self.shortcut = shortcut
    }

    /// The same command with a title for the current state ("Unpin Tab"), a symbol and its key.
    public func with(title: String? = nil, symbol: String?, shortcut: String? = nil) -> OmniboxCommand {
        var copy = self
        if let title { copy.title = title }
        copy.symbol = symbol
        copy.shortcut = shortcut
        return copy
    }
}

/// The spec §C command list (Zen's actions, A–Z). Commands that name a tab
/// or a space ("Focus on {space}", "Move to {space}") are made per target
/// with `focus(space:)` and `move(toSpace:)`.
public enum CommandRegistry {
    public static let addToEssentials = OmniboxCommand(id: "add-to-essentials", title: "Add to Essentials", keywords: ["favorite", "star"])
    public static let captureScreenshot = OmniboxCommand(id: "capture-screenshot", title: "Capture Screenshot", keywords: ["image"])
    public static let clearArchive = OmniboxCommand(id: "clear-archive", title: "Clear Archive")
    public static let closeTab = OmniboxCommand(id: "close-tab", title: "Close Tab")
    public static let copyURL = OmniboxCommand(id: "copy-url", title: "Copy URL", keywords: ["link", "address"])
    public static let copyMarkdown = OmniboxCommand(id: "copy-url-markdown", title: "Copy URL as Markdown", keywords: ["link"])
    public static let duplicateTab = OmniboxCommand(id: "duplicate-tab", title: "Duplicate Tab", keywords: ["copy"])
    public static let findInPage = OmniboxCommand(id: "find-in-page", title: "Find in Page", keywords: ["search"])
    /// The import sheet (4.3a): bookmarks, history and Arc's sidebar from another browser.
    public static let importFromBrowser = OmniboxCommand(id: "import-from-browser", title: "Import from another browser…",
                                                         keywords: ["bookmarks", "history", "chrome", "safari", "arc", "brave", "edge", "firefox"])
    public static let newFolder = OmniboxCommand(id: "new-folder", title: "New Folder")
    public static let newSpace = OmniboxCommand(id: "new-space", title: "New Space")
    public static let newSplitView = OmniboxCommand(id: "new-split-view", title: "New Split View")
    public static let nextSpace = OmniboxCommand(id: "next-space", title: "Next Space")
    public static let previousSpace = OmniboxCommand(id: "previous-space", title: "Previous Space")
    public static let openPrivateWindow = OmniboxCommand(id: "open-private-window", title: "Open Private Window", keywords: ["incognito"])
    public static let pinTab = OmniboxCommand(id: "pin-tab", title: "Pin Tab", keywords: ["unpin"])
    public static let print = OmniboxCommand(id: "print", title: "Print")
    /// View ▸ Reader Mode (4.7b): toggles.
    public static let readerMode = OmniboxCommand(id: "reader-mode", title: "Reader Mode", keywords: ["read", "article", "distill"])
    public static let reload = OmniboxCommand(id: "reload", title: "Reload", keywords: ["refresh"])
    /// File ▸ Save Page… (4.7a).
    public static let savePage = OmniboxCommand(id: "save-page", title: "Save Page…", keywords: ["download", "mhtml", "archive", "html"])
    /// View ▸ Developer ▸ View Source (4.7a).
    public static let viewSource = OmniboxCommand(id: "view-source", title: "View Source", keywords: ["html", "developer"])
    public static let reloadWithoutCache = OmniboxCommand(id: "reload-without-cache", title: "Reload without Cache", keywords: ["refresh", "hard"])
    public static let reopenClosedTab = OmniboxCommand(id: "reopen-closed-tab", title: "Reopen Closed Tab", keywords: ["undo", "restore"])
    public static let resetPinnedTab = OmniboxCommand(id: "reset-pinned-tab", title: "Reset Pinned Tab")
    public static let settings = OmniboxCommand(id: "settings", title: "Settings", keywords: ["preferences", "options"])
    public static let spaceRouting = OmniboxCommand(id: "space-routing", title: "Space Routing…", keywords: ["rules"])
    public static let lightAppearance = OmniboxCommand(id: "appearance-light", title: "Switch to Light Appearance", keywords: ["theme", "mode"])
    public static let darkAppearance = OmniboxCommand(id: "appearance-dark", title: "Switch to Dark Appearance", keywords: ["theme", "mode"])
    public static let autoAppearance = OmniboxCommand(id: "appearance-auto", title: "Switch to Auto Appearance", keywords: ["theme", "mode", "system"])
    public static let toggleSidebar = OmniboxCommand(id: "toggle-sidebar", title: "Toggle Sidebar", keywords: ["hide", "show"])
    public static let viewArchive = OmniboxCommand(id: "view-archive", title: "View Archive")
    public static let unsplit = OmniboxCommand(id: "unsplit", title: "Unsplit")
    public static let unloadTab = OmniboxCommand(id: "unload-tab", title: "Unload Tab", keywords: ["sleep", "discard"])

    /// Every fixed command, A–Z by title.
    public static let all: [OmniboxCommand] = [
        addToEssentials, captureScreenshot, clearArchive, closeTab, copyURL, copyMarkdown, duplicateTab, findInPage, importFromBrowser, newFolder, newSpace,
        newSplitView, nextSpace, previousSpace, openPrivateWindow, pinTab, print, readerMode, reload, reloadWithoutCache, reopenClosedTab,
        resetPinnedTab, savePage, settings, spaceRouting, lightAppearance, darkAppearance, autoAppearance, toggleSidebar, viewArchive, unsplit,
        unloadTab, viewSource,
    ].sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

    /// "Settings ▸ Privacy" (4.4b): opens Settings at one section.
    public static func settingsSection(_ index: Int, title: String) -> OmniboxCommand {
        OmniboxCommand(id: "settings-section:\(index)", title: "Settings ▸ \(title)", keywords: ["preferences", "settings"])
    }

    /// The section index a "Settings ▸ …" command opens (`nil` for others).
    public static func settingsSection(in id: String) -> Int? {
        id.hasPrefix("settings-section:") ? Int(id.dropFirst("settings-section:".count)) : nil
    }

    public static func focus(space id: UUID, name: String) -> OmniboxCommand {
        OmniboxCommand(id: "focus-space:\(id.uuidString)", title: "Focus on \(name)", keywords: ["space", "switch"])
    }

    public static func move(toSpace id: UUID, name: String) -> OmniboxCommand {
        OmniboxCommand(id: "move-to-space:\(id.uuidString)", title: "Move to \(name)", keywords: ["space"])
    }

    /// The space a per-space command targets (`nil` for fixed commands).
    public static func space(in id: String) -> (focus: Bool, space: UUID)? {
        for (prefix, focus) in [("focus-space:", true), ("move-to-space:", false)] where id.hasPrefix(prefix) {
            return UUID(uuidString: String(id.dropFirst(prefix.count))).map { (focus, $0) }
        }
        return nil
    }
}

/// Commands (spec §C group 6). In commands mode (`>` or Tab from an empty
/// field) they are the only rows: all of them A–Z for an empty query, else
/// those whose words match. In normal mode a command shows only when the
/// query starts its words (three letters or more), below everything else.
public struct CommandsProvider: OmniboxProvider {
    public init() {}

    public var kind: ProviderKind { .commands }

    /// Normal-mode commands stay below every other group.
    static let normalBand = 400...700

    public func matches(for input: OmniboxInput, in context: OmniboxContext) -> [OmniboxMatch] {
        let commands = context.commands
        let terms = input.trimmed.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        switch input.mode {
        case .siteSearch:
            return []
        case .commands:
            guard !terms.isEmpty else {
                // A–Z: the first is the top hit.
                return commands.enumerated().map { index, command in
                    match(command, relevance: Relevance.commands.upperBound - min(index, Relevance.commands.count - 1))
                }
            }
            return commands.enumerated().compactMap { index, command in
                guard let quality = Self.quality(terms: terms, command: command) else { return nil }
                // Quality first, the A–Z order breaks ties.
                let tiebreak = 1 - Double(index) / Double(max(1, commands.count))
                return match(command, relevance: Relevance.scaled(quality * 0.95 + tiebreak * 0.05, in: Relevance.commands))
            }
        case .normal:
            guard input.trimmed.count >= 3 else { return [] }
            return commands.compactMap { command in
                guard let quality = Self.quality(terms: terms, command: command), quality >= 0.8 else { return nil }
                return match(command, relevance: Relevance.scaled(quality, in: Self.normalBand))
            }
        }
    }

    private func match(_ command: OmniboxCommand, relevance: Int) -> OmniboxMatch {
        var match = OmniboxMatch(id: "command:\(command.id)", provider: .commands, relevance: relevance, action: .command(id: command.id),
                                 title: command.title, icon: .symbol(command.symbol ?? "command"))
        match.shortcut = command.shortcut
        return match
    }

    /// 0…1, or `nil` when a word matches nothing: a word start in the title
    /// scores 1, a keyword start 0.8, a substring of the title 0.5.
    static func quality(terms: [String], command: OmniboxCommand) -> Double? {
        let title = command.title.lowercased()
        let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let keywords = command.keywords.map { $0.lowercased() }
        var total = 0.0
        for term in terms {
            if words.contains(where: { $0.hasPrefix(term) }) {
                total += 1
            } else if keywords.contains(where: { $0.hasPrefix(term) }) {
                total += 0.8
            } else if title.contains(term) {
                total += 0.5
            } else {
                return nil
            }
        }
        return total / Double(terms.count)
    }
}
