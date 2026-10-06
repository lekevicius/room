import Foundation

public enum EntryConversionError: Error, Equatable, Sendable {
    /// The Essentials grid already holds `cap` entries (spec §A.9: shake + "12/12").
    case essentialsFull(cap: Int)
    /// Folders live only in the pinned section (spec §A.6).
    case folderOutsidePinned
    /// A permanent entry needs a URL to store; the entry has none.
    case noURL
}

/// Entry rules from spec §A.1 and §A.9, as pure functions.
public enum EntryRules {
    /// Maximum entries in a profile's Essentials grid.
    public static let essentialsCap = 12

    public static func canAddEssential(currentCount: Int) -> Bool {
        currentCount < essentialsCap
    }

    /// A permanent entry whose live page differs from its stored URL (§A.1).
    /// Unloaded entries (no live URL) are never changed.
    public static func isChanged(_ entry: Entry) -> Bool {
        guard entry.kind == .essential || entry.kind == .pinned,
              let live = entry.liveURL, let stored = entry.storedURL else { return false }
        return !URLNormalization.isSame(live, stored)
    }

    /// The entry converted for `section` in `space` (§A.9):
    /// - Today → Pinned/Essential stores the current page (`storedURL = liveURL`).
    /// - Pinned/Essential → Today drops the stored state but keeps the page.
    /// - → Essentials needs room under the cap (`essentialsCount` excludes the
    ///   entry itself when it already is an essential).
    /// - Essentials have no space or folder; the entry takes `space`'s profile.
    /// Position and folder are the caller's to set.
    public static func converted(
        _ entry: Entry, to section: EntrySection, in space: Space, essentialsCount: Int
    ) throws(EntryConversionError) -> Entry {
        if entry.kind == .folder {
            guard section == .pinned else { throw .folderOutsidePinned }
            var folder = entry
            folder.spaceID = space.id
            folder.profileID = space.profileID
            return folder
        }
        var result = entry
        result.profileID = space.profileID
        switch section {
        case .essentials:
            if entry.kind != .essential {
                guard canAddEssential(currentCount: essentialsCount) else { throw .essentialsFull(cap: essentialsCap) }
            }
            try storeCurrentPage(&result)
            result.kind = .essential
            result.spaceID = nil
            result.folderID = nil
            // Shared by every window (schema v9).
            result.windowID = nil
        case .pinned:
            try storeCurrentPage(&result)
            result.kind = .pinned
            result.spaceID = space.id
            result.windowID = nil
        case .today:
            if entry.kind != .today {
                result.liveURL = entry.liveURL ?? entry.storedURL
                result.liveTitle = entry.liveTitle ?? entry.storedTitle
                result.storedURL = nil
                result.storedTitle = nil
            }
            result.kind = .today
            result.spaceID = space.id
            result.folderID = nil
        }
        return result
    }

    private static func storeCurrentPage(_ entry: inout Entry) throws(EntryConversionError) {
        guard entry.kind == .today else { return }
        guard let url = entry.liveURL else { throw .noURL }
        entry.storedURL = url
        entry.storedTitle = entry.liveTitle
    }
}
