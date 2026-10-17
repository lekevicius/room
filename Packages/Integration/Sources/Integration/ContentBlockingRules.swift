import Foundation
import Model

/// What a filter list is for: the Settings switch it follows.
public enum FilterListCategory: String, Sendable, Hashable, CaseIterable {
    case ads, trackers, cookieBanners, annoyances, security
}

/// One list of Room's catalogue (B-30; research/notes/adblock-approach.md
/// §9.3). Bundled lists ship in the app (permissive licences only) and work
/// with no network; the others are downloaded when the user turns them on.
public struct FilterListInfo: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let category: FilterListCategory
    /// The file in the app's ContentBlocking resources, for bundled lists.
    public let bundledFileName: String?
    /// Where updates (or, for optional lists, the list itself) come from.
    public let sourceURL: URL
    public let licence: String
    public let isHostsFormat: Bool

    public var isBundled: Bool { bundledFileName != nil }
}

public enum FilterListCatalog {
    public static let all: [FilterListInfo] = [
        FilterListInfo(id: "easylist", title: "EasyList", summary: "The main list of ads.",
                       category: .ads, bundledFileName: "easylist.txt",
                       sourceURL: URL(string: "https://easylist.to/easylist/easylist.txt")!,
                       licence: "CC BY-SA 3.0", isHostsFormat: false),
        FilterListInfo(id: "easyprivacy", title: "EasyPrivacy", summary: "Trackers, analytics and fingerprinting scripts.",
                       category: .trackers, bundledFileName: "easyprivacy.txt",
                       sourceURL: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
                       licence: "CC BY-SA 3.0", isHostsFormat: false),
        FilterListInfo(id: "easylist-cookie", title: "EasyList Cookie List", summary: "Hides cookie banners.",
                       category: .cookieBanners, bundledFileName: "easylist-cookie.txt",
                       sourceURL: URL(string: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt")!,
                       licence: "CC BY 3.0", isHostsFormat: false),
        FilterListInfo(id: "ublock-filters", title: "uBlock filters", summary: "uBlock Origin's own fixes for ads EasyList misses.",
                       category: .ads, bundledFileName: nil,
                       sourceURL: URL(string: "https://ublockorigin.github.io/uAssets/filters/filters.txt")!,
                       licence: "GPL-3.0", isHostsFormat: false),
        FilterListInfo(id: "ublock-privacy", title: "uBlock filters – Privacy", summary: "uBlock Origin's tracker rules.",
                       category: .trackers, bundledFileName: nil,
                       sourceURL: URL(string: "https://ublockorigin.github.io/uAssets/filters/privacy.txt")!,
                       licence: "GPL-3.0", isHostsFormat: false),
        FilterListInfo(id: "ublock-unbreak", title: "uBlock filters – Unbreak", summary: "Exceptions that keep sites working.",
                       category: .ads, bundledFileName: nil,
                       sourceURL: URL(string: "https://ublockorigin.github.io/uAssets/filters/unbreak.txt")!,
                       licence: "GPL-3.0", isHostsFormat: false),
        FilterListInfo(id: "ublock-badware", title: "uBlock filters – Badware risks", summary: "Sites known for scams and malware.",
                       category: .security, bundledFileName: nil,
                       sourceURL: URL(string: "https://ublockorigin.github.io/uAssets/filters/badware.txt")!,
                       licence: "GPL-3.0", isHostsFormat: false),
        FilterListInfo(id: "fanboy-annoyances", title: "Fanboy's Annoyance List", summary: "Pop-ups, newsletter prompts and social widgets.",
                       category: .annoyances, bundledFileName: nil,
                       sourceURL: URL(string: "https://secure.fanboy.co.nz/fanboy-annoyance.txt")!,
                       licence: "CC BY 3.0", isHostsFormat: false),
    ]

    public static func info(_ id: String) -> FilterListInfo? { all.first { $0.id == id } }
}

/// One list the engine should read now.
public struct PlannedFilterList: Sendable, Hashable {
    public let id: String
    public let fileURL: URL
    public let isHostsFormat: Bool
}

/// What the engine gets from the settings and the files on disk.
public struct ContentBlockingPlan: Sendable, Hashable {
    public var lists: [PlannedFilterList]
    /// Lists the settings ask for that are not on disk yet (the user turned
    /// them on; their download is due): catalogue ids or custom list ids.
    public var missing: [String]
    public var customRules: String
    public var allowedSites: [String]
    public var cookieBanners: CookieBannerSetting
    /// Anything to do at all (the engine's switch).
    public var isEnabled: Bool

    /// Bundled lists come from `bundleDirectory`, unless a downloaded copy
    /// (an update) is in `downloads`; optional and custom lists come from
    /// `downloads` only. `downloads` maps a list id (catalogue id or a custom
    /// list's UUID string) to its file.
    public static func make(settings: ContentBlockingSettings, bundleDirectory: URL, downloads: [String: URL]) -> Self {
        var lists: [PlannedFilterList] = []
        var missing: [String] = []
        func wanted(_ category: FilterListCategory) -> Bool {
            switch category {
            case .ads: settings.blockAds
            case .trackers: settings.blockTrackers
            // The cookie list hides what autoconsent could not answer, too.
            case .cookieBanners: settings.cookieBanners != .off
            case .annoyances, .security: true
            }
        }
        for info in FilterListCatalog.all where wanted(info.category) {
            if let bundled = info.bundledFileName {
                let file = downloads[info.id] ?? bundleDirectory.appending(path: bundled)
                lists.append(PlannedFilterList(id: info.id, fileURL: file, isHostsFormat: info.isHostsFormat))
            } else if settings.enabledLists.contains(info.id) {
                if let file = downloads[info.id] {
                    lists.append(PlannedFilterList(id: info.id, fileURL: file, isHostsFormat: info.isHostsFormat))
                } else {
                    missing.append(info.id)
                }
            }
        }
        for custom in settings.customLists where custom.isEnabled {
            let id = custom.id.uuidString
            if let file = downloads[id] {
                lists.append(PlannedFilterList(id: id, fileURL: file, isHostsFormat: false))
            } else {
                missing.append(id)
            }
        }
        let rules = settings.customRules.trimmingCharacters(in: .whitespacesAndNewlines)
        return ContentBlockingPlan(
            lists: lists, missing: missing, customRules: rules, allowedSites: settings.allowedSites.sorted(),
            cookieBanners: settings.cookieBanners,
            isEnabled: !lists.isEmpty || !rules.isEmpty || settings.cookieBanners == .reject)
    }
}

/// Facts read from a filter list's text.
public enum FilterListText {
    /// The header's `! Title:`, if any.
    public static func title(of text: String) -> String? {
        header(text, "Title")
    }

    /// The header's `! Expires: 4 days (update frequency)` as an interval;
    /// `nil` when absent or unreadable.
    public static func expiry(of text: String) -> TimeInterval? {
        guard let value = header(text, "Expires") else { return nil }
        let words = value.split(whereSeparator: \.isWhitespace)
        guard let first = words.first, let count = Double(first), count > 0, words.count >= 2 else { return nil }
        let unit = words[1].lowercased()
        if unit.hasPrefix("day") { return count * 86_400 }
        if unit.hasPrefix("hour") { return count * 3_600 }
        return nil
    }

    /// Rules in the text: lines that are neither empty nor comments.
    public static func ruleCount(_ text: String) -> Int {
        var count = 0
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("!"), !trimmed.hasPrefix("[") else { return }
            // `#` starts a comment in HOSTS files; `##`, `#@#`, `#?#`… are cosmetic rules.
            if trimmed.hasPrefix("#"), !trimmed.hasPrefix("##"), !trimmed.hasPrefix("#@#"), !trimmed.hasPrefix("#?#") { return }
            count += 1
        }
        return count
    }

    /// The text looks like a filter list (an ABP header, or rules) rather
    /// than an HTML error page.
    public static func looksLikeFilterList(_ text: String) -> Bool {
        let head = text.prefix(512).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if head.hasPrefix("<!doctype") || head.hasPrefix("<html") { return false }
        return head.hasPrefix("[adblock") || head.hasPrefix("!") || ruleCount(String(text.prefix(4096))) > 0
    }

    private static func header(_ text: String, _ key: String) -> String? {
        var found: String?
        var lines = 0
        text.enumerateLines { line, stop in
            lines += 1
            if lines > 60 { stop = true; return }
            let prefix = "! \(key):"
            if line.hasPrefix(prefix) {
                found = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                stop = true
            }
        }
        return found
    }
}

/// When a downloaded list is fetched again (only while the user's
/// "Update lists automatically" is on; "Update Now" ignores this).
public enum FilterListSchedule {
    /// Shortest interval between two checks of one list, whatever it asks.
    public static let minimumInterval: TimeInterval = 86_400
    /// Longest interval, and the one for a list that states none.
    public static let maximumInterval: TimeInterval = 7 * 86_400

    public static func interval(expiry: TimeInterval?) -> TimeInterval {
        min(max(expiry ?? maximumInterval, minimumInterval), maximumInterval)
    }

    /// The list was last fetched at `lastFetched` (`nil`: never) and says it
    /// expires after `expiry`.
    public static func isDue(lastFetched: Date?, expiry: TimeInterval?, now: Date) -> Bool {
        guard let lastFetched else { return true }
        return now.timeIntervalSince(lastFetched) >= interval(expiry: expiry)
    }
}
