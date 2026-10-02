import AppKit

/// A browsing profile: one cookie jar, cache, history and set of site
/// permissions. Chromium `Profile`; CEF `CefRequestContext`.
@MainActor
public protocol Profile: AnyObject {
    /// The name the profile was created with; also its directory name.
    var name: String { get }

    /// Creates a tab's web contents. It has no URL until `load` is called and
    /// is not shown until its `nativeView` is added to a window.
    func createWebContents(_ configuration: WebContentsConfiguration) throws -> any WebContents

    /// Receives every download started in this profile. Held weakly.
    var downloadsDelegate: (any DownloadsDelegate)? { get set }

    func pauseDownload(id: DownloadItem.ID)
    func resumeDownload(id: DownloadItem.ID)
    func cancelDownload(id: DownloadItem.ID)

    /// The engine's stored favicon for a page, if it has one.
    func favicon(for pageURL: URL) async -> NSImage?

    /// Deletes site data of the given kinds, for one origin or (`nil`) all.
    func clearSiteData(_ types: SiteDataTypes, for origin: URL?) async throws

    // Optional capabilities: `nil` when the engine does not provide them
    // (CEF provides none). Their members are specified in Chapter 3.

    /// Chromium's history service.
    var history: (any ProfileHistory)? { get }
    /// Chromium's bookmark model (import source; the sidebar has its own model).
    var bookmarks: (any ProfileBookmarks)? { get }
    /// Installed extensions, their actions and popups.
    var extensions: (any ProfileExtensions)? { get }
    /// A new omnibox `AutocompleteController`, one per address field.
    func makeAutocompleteController() -> (any AutocompleteController)?
}

/// Chromium history service. Members arrive in Phase 3.5.
@MainActor public protocol ProfileHistory: AnyObject {}

/// Chromium bookmark model. Members arrive in Phase 4.3.
@MainActor public protocol ProfileBookmarks: AnyObject {}

/// Chromium extension system. Members arrive in Phase 3.6.
@MainActor public protocol ProfileExtensions: AnyObject {}

/// Chromium omnibox autocomplete. Members arrive in Phase 3.5.
@MainActor public protocol AutocompleteController: AnyObject {}

/// Kinds of site data `Profile.clearSiteData` removes.
nonisolated public struct SiteDataTypes: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let cookies = SiteDataTypes(rawValue: 1 << 0)
    public static let cache = SiteDataTypes(rawValue: 1 << 1)
    /// Local/session storage, IndexedDB, Cache Storage, service workers.
    public static let storage = SiteDataTypes(rawValue: 1 << 2)
    public static let httpAuthCredentials = SiteDataTypes(rawValue: 1 << 3)
    /// Site permissions and content settings.
    public static let permissions = SiteDataTypes(rawValue: 1 << 4)

    public static let all: SiteDataTypes = [.cookies, .cache, .storage, .httpAuthCredentials, .permissions]
}
