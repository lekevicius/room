import AppKit
import Model

/// What the sidebar shows about an entry's live page (not persisted). The
/// host (the tab controller from Phase 2.3; FakeEngine pages in 2.2) owns it.
public struct EntryPageState: Equatable {
    public var isLoaded: Bool
    public var isLoading: Bool
    public var isAudible: Bool
    public var isMuted: Bool
    public var favicon: NSImage?

    public init(isLoaded: Bool = false, isLoading: Bool = false, isAudible: Bool = false, isMuted: Bool = false,
                favicon: NSImage? = nil) {
        self.isLoaded = isLoaded
        self.isLoading = isLoading
        self.isAudible = isAudible
        self.isMuted = isMuted
        self.favicon = favicon
    }

    public static let unloaded = EntryPageState()
}

/// Page operations the sidebar asks for. The sidebar itself only writes the
/// stores (selection, order, kinds, labels); everything that touches a web
/// page goes through the host.
public protocol SidebarHost: AnyObject {
    func pageState(for entry: UUID) -> EntryPageState

    /// The entry became the selected one: show its page, loading
    /// `entry.currentURL` if it has none.
    func activate(_ entry: Entry)
    /// Nothing is selected (the empty state, spec §A.7).
    func deactivate()
    /// Drop the entry's page; the entry stays.
    func unload(_ entry: UUID)
    /// Navigate the loaded page back to the stored URL (the store already
    /// holds `liveURL = storedURL`).
    func reset(_ entry: Entry)
    /// ⌘-click "Separate from pinned tab": the page moves to `newEntry` (a
    /// new Today tab) and `entry` is left without one.
    func separate(_ entry: UUID, into newEntry: Entry)
    func reload(_ entry: UUID)
    func setMuted(_ muted: Bool, entry: UUID)
    /// "New Tab": the palette from Phase 2.4.
    func newTab()
    /// The header's address field was clicked (⌘L docked, Phase 2.4).
    func editAddress()
    /// Space on a focused permanent row (spec §I.13): its stored URL in Peek.
    func peek(_ entry: Entry)
    /// ⇧⌘T on a closed Peek: it opens again over `entry`'s page (spec §I.6).
    func reopenPeek(url: String, over entry: UUID)
}

public extension SidebarHost {
    func peek(_ entry: Entry) {}
    func reopenPeek(url: String, over entry: UUID) {}
}
