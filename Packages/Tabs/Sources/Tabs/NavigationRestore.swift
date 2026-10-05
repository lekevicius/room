import Foundation

/// How a page made for an entry with a saved back/forward list starts
/// (3.7b): the engine restored the list, and the entry's URL is either the
/// restored current entry (load it: relaunch, crash recovery, ⌘W's unload,
/// ⇧⌘T) or somewhere else (navigate there with the list behind it: a pinned
/// entry reset to its stored URL, a URL typed for an unloaded entry).
enum NavigationRestore: Equatable {
    case loadRestored
    /// `unreadable`: there was a saved list but the engine restored nothing
    /// (another engine version's format, CEF); the entry's URL loads alone.
    case navigate(unreadable: Bool)

    static func firstLoad(entryURL: URL, restoredURL: URL?, hadState: Bool) -> NavigationRestore {
        guard hadState else { return .navigate(unreadable: false) }
        guard let restoredURL else { return .navigate(unreadable: true) }
        return restoredURL.absoluteString == entryURL.absoluteString ? .loadRestored : .navigate(unreadable: false)
    }
}
