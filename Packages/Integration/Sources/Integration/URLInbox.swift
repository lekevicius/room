import Foundation

/// Links the system hands to Room (`application(_:open:)`: another app's
/// link once Room is the default browser, `open`, Finder's Open With, an
/// AppleScript `open location`; ROADMAP 2.8 task 3). On a cold launch by a
/// link AppKit delivers it before `applicationDidFinishLaunching`, before the
/// store and the engine exist, so links wait here until the app opens the
/// inbox; after that they are handed on as they arrive, in order.
public final class URLInbox {
    /// Links received before `open(_:)`, oldest first.
    public private(set) var pending: [URL] = []
    private var deliver: (([URL]) -> Void)?

    public init() {}

    /// Whether links are handed on as they arrive.
    public var isOpen: Bool { deliver != nil }

    /// Web pages and local files (the HTML documents Room declares); any other scheme is not Room's.
    public static func accepts(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https": url.host().map { !$0.isEmpty } ?? false
        case "file": url.isFileURL
        default: false
        }
    }

    /// Takes what Room opens: queued while the inbox is closed, handed on at once
    /// when it is open. Returns the links it took.
    @discardableResult
    public func receive(_ urls: [URL]) -> [URL] {
        let accepted = urls.filter(Self.accepts)
        guard !accepted.isEmpty else { return [] }
        if let deliver {
            deliver(accepted)
        } else {
            pending += accepted
        }
        return accepted
    }

    /// The store and the engine are up: the queued links go first, then each new one.
    public func open(_ deliver: @escaping ([URL]) -> Void) {
        self.deliver = deliver
        let queued = pending
        pending = []
        if !queued.isEmpty { deliver(queued) }
    }
}
