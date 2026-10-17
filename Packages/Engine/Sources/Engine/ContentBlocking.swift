import Foundation

/// What Room's blocker does with cookie banners (Settings ▸ Privacy).
nonisolated public enum CookieBannerMode: String, Sendable, Hashable, Codable, CaseIterable {
    /// Nothing: banners show as the site draws them.
    case off
    /// Only the cookie list's hiding rules (the host includes that list).
    case hide
    /// DuckDuckGo's autoconsent opts out of the banner's purposes, then hides it.
    case reject
}

/// One filter list the engine reads, a file the host owns (bundled, or
/// downloaded when the user asked).
nonisolated public struct ContentBlockingList: Sendable, Hashable {
    public var fileURL: URL
    /// One hostname per line (HOSTS files) instead of filter syntax.
    public var isHostsFormat: Bool
    /// The list may use privileged scriptlets.
    public var isTrusted: Bool

    public init(fileURL: URL, isHostsFormat: Bool = false, isTrusted: Bool = false) {
        self.fileURL = fileURL
        self.isHostsFormat = isHostsFormat
        self.isTrusted = isTrusted
    }
}

/// Everything the blocker is told; the engine keeps no settings of its own.
nonisolated public struct ContentBlockingConfiguration: Sendable, Hashable {
    public var isEnabled: Bool
    public var lists: [ContentBlockingList]
    /// Filter syntax, one rule per line (Settings ▸ Privacy ▸ Custom Rules).
    public var customRules: String
    /// adblock-rust's resources JSON ($redirect bodies, scriptlets).
    public var resourcesURL: URL?
    /// Where the built engine is cached between launches.
    public var cacheDirectory: URL?
    /// Registrable domains where nothing is blocked (the per-site switch).
    public var allowedSites: [String]
    public var cookieBanners: CookieBannerMode
    /// autoconsent's bundle (Reject only).
    public var cookieScriptURL: URL?

    public init(isEnabled: Bool = false, lists: [ContentBlockingList] = [], customRules: String = "",
                resourcesURL: URL? = nil, cacheDirectory: URL? = nil, allowedSites: [String] = [],
                cookieBanners: CookieBannerMode = .off, cookieScriptURL: URL? = nil) {
        self.isEnabled = isEnabled
        self.lists = lists
        self.customRules = customRules
        self.resourcesURL = resourcesURL
        self.cacheDirectory = cacheDirectory
        self.allowedSites = allowedSites
        self.cookieBanners = cookieBanners
        self.cookieScriptURL = cookieScriptURL
    }
}

/// How applying a configuration went.
nonisolated public struct ContentBlockingReport: Sendable, Hashable {
    /// Files the engine could not read, one line each; empty when all were read.
    public var problems: [String]
    /// The engine came from its cache (or was unchanged) rather than the lists' text.
    public var fromCache: Bool
    public var buildMilliseconds: Double
    /// The serialized engine's size.
    public var engineBytes: Int

    public init(problems: [String] = [], fromCache: Bool = false, buildMilliseconds: Double = 0, engineBytes: Int = 0) {
        self.problems = problems
        self.fromCache = fromCache
        self.buildMilliseconds = buildMilliseconds
        self.engineBytes = engineBytes
    }
}

/// A request's kind as filter lists name it (`$script`, `$image`…).
nonisolated public enum ContentBlockingRequestType: String, Sendable, Hashable, CaseIterable {
    case script, image, stylesheet, font, media, object, ping, other
    case subFrame = "sub_frame"
    case xmlHTTPRequest = "xmlhttprequest"
}

/// Room's built-in ad and tracker blocker (B-30): one engine for every
/// profile and incognito, network requests matched in the engine, element
/// hiding, scriptlets and cookie banners in each document. RoomCore:
/// adblock-rust in `//room` (`RoomContentBlocker`); the fake: `||host^` and
/// `##selector` rules only.
@MainActor
public protocol ContentBlocking: AnyObject {
    /// Replaces the configuration; returns once the new rules are in use.
    /// Allowed sites and the cookie-banner mode apply to documents loaded
    /// after the call; an open page picks them up when it reloads.
    @discardableResult
    func apply(_ configuration: ContentBlockingConfiguration) async -> ContentBlockingReport

    /// What the engine would decide for one request (diagnostics, spikes).
    func wouldBlock(_ url: URL, from source: URL, type: ContentBlockingRequestType) -> Bool
}
