import Foundation

/// The other browser's extensions brought over through their Chrome Web
/// Store pages (4.3b; the planner's decision: no install-by-id member): the
/// chosen extensions' pages open one at a time as Today tabs; the user adds
/// each from the store and answers Room's consent sheet; the next page opens
/// when the engine reports the install or the user closes the page. A pure
/// state machine: the app opens the pages and reports what happened.
public struct StorePageSequence: Hashable, Sendable {
    /// What the app does next.
    public enum Step: Hashable, Sendable {
        /// Open this extension's store page as a Today tab.
        case open(id: String, url: URL)
        /// Nothing left: the summary is final.
        case finished
    }

    /// The Web Store's page for an extension (`{id}` replaced).
    public static let defaultPageTemplate = "https://chromewebstore.google.com/detail/{id}"

    /// A Chrome extension id: 32 letters a–p.
    public static func isExtensionID(_ id: String) -> Bool {
        id.count == 32 && id.allSatisfy { ("a"..."p").contains($0) }
    }

    public let pageTemplate: String
    /// Waiting their turn, in order.
    public private(set) var pending: [String]
    /// The page open now.
    public private(set) var current: String?
    /// Pages opened, in order.
    public private(set) var opened: [String] = []
    /// Installed while their page was open (or before it opened).
    public private(set) var installed: [String] = []
    /// Their page closed without an install.
    public private(set) var closedWithoutInstall: [String] = []
    /// Already in the target profile when the sequence started: no page.
    public private(set) var alreadyInstalled: [String] = []
    /// Not an extension id (never opened).
    public private(set) var invalid: [String] = []

    /// `ids` in the order to open them; duplicates once.
    public init(ids: [String], pageTemplate: String = StorePageSequence.defaultPageTemplate) {
        var seen: Set<String> = []
        pending = ids.filter { seen.insert($0).inserted }
        self.pageTemplate = pageTemplate
    }

    public func pageURL(for id: String) -> URL? {
        URL(string: pageTemplate.replacingOccurrences(of: "{id}", with: id))
    }

    public var isFinished: Bool { current == nil && pending.isEmpty }

    /// The first page, skipping what the profile already has.
    public mutating func start(installedInProfile: Set<String>) -> Step {
        let (already, rest) = (pending.filter(installedInProfile.contains), pending.filter { !installedInProfile.contains($0) })
        alreadyInstalled = already
        pending = rest
        return advance()
    }

    /// After the profile's extensions changed: the current one installed
    /// moves the sequence on; a pending one installed some other way leaves
    /// the queue. `nil`: keep waiting.
    public mutating func extensionsChanged(installedInProfile: Set<String>) -> Step? {
        let early = pending.filter(installedInProfile.contains)
        if !early.isEmpty {
            installed += early
            pending.removeAll(where: installedInProfile.contains)
        }
        guard let current, installedInProfile.contains(current) else { return nil }
        installed.append(current)
        self.current = nil
        return advance()
    }

    /// The current page was closed (or left the sidebar) without an install.
    public mutating func pageClosed() -> Step? {
        guard let current else { return nil }
        closedWithoutInstall.append(current)
        self.current = nil
        return advance()
    }

    /// Stops: whatever is pending is never opened.
    public mutating func cancel() {
        pending = []
        current = nil
    }

    private mutating func advance() -> Step {
        while let next = pending.first {
            pending.removeFirst()
            guard Self.isExtensionID(next), let url = pageURL(for: next) else {
                invalid.append(next)
                continue
            }
            current = next
            opened.append(next)
            return .open(id: next, url: url)
        }
        return .finished
    }
}
