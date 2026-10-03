import AppKit
import Design
import Engine
import Model

/// Which background pages to discard (spec §H), as pure functions. A
/// discarded page releases its renderer and keeps URL, title and favicon;
/// selecting it reloads it (on CEF without back/forward, backlog B-13).
public enum DiscardPolicy {
    /// What the policy needs to know about one page.
    public struct Page: Equatable, Sendable {
        public var id: UUID
        public var kind: EntryKind
        public var isSelected: Bool
        public var isAudible: Bool
        /// Has a renderer (`WebContentsState.alive`).
        public var isAlive: Bool
        /// When it was last on screen.
        public var lastVisible: Date

        public init(id: UUID, kind: EntryKind, isSelected: Bool, isAudible: Bool, isAlive: Bool, lastVisible: Date) {
            self.id = id
            self.kind = kind
            self.isSelected = isSelected
            self.isAudible = isAudible
            self.isAlive = isAlive
            self.lastVisible = lastVisible
        }

        /// Never the selected page, a page playing audio or one already discarded.
        var isEligible: Bool { isAlive && !isSelected && !isAudible }
    }

    /// Unseen longer than its kind's limit: Today tabs 60 min, pinned
    /// entries and essentials 3 h.
    public static func idle(_ pages: [Page], now: Date) -> [UUID] {
        pages.filter { page in
            let limit = page.kind == .today ? Timing.discardIdleToday : Timing.discardIdlePermanent
            return page.isEligible && now.timeIntervalSince(page.lastVisible) >= limit
        }.map(\.id)
    }

    /// Memory pressure: least recently seen first, across all spaces. A
    /// warning discards the older half of the eligible pages (rounded up), a
    /// critical level all of them.
    public static func underPressure(_ pages: [Page], critical: Bool) -> [UUID] {
        let eligible = pages.filter(\.isEligible).sorted { $0.lastVisible < $1.lastVisible }
        let count = critical ? eligible.count : (eligible.count + 1) / 2
        return eligible.prefix(count).map(\.id)
    }
}

/// Idle and memory-pressure discards (spec §H).
extension TabController {
    /// Starts the idle sweep (every `Timing.discardSweepInterval`) and listens
    /// for `DISPATCH_MEMORYPRESSURE_WARN` / `_CRITICAL`.
    public func startLifecycle() {
        sweepTimer?.invalidate()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: Timing.discardSweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.discardIdlePages() }
        }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated { _ = self?.handleMemoryPressure(critical: event.contains(.critical)) }
        }
        source.resume()
        memoryPressureSource = source
    }

    var discardCandidates: [DiscardPolicy.Page] {
        pages.compactMap { id, page in
            guard let entry = store.sidebar.entry(id) else { return nil }
            return DiscardPolicy.Page(id: id, kind: entry.kind, isSelected: id == currentEntryID, isAudible: page.contents.isAudible,
                                      isAlive: page.contents.state == .alive, lastVisible: page.lastVisible)
        }
    }

    /// Discards pages idle past their limit; returns them.
    @discardableResult
    public func discardIdlePages() -> [UUID] {
        let ids = DiscardPolicy.idle(discardCandidates, now: now())
        for id in ids { discard(id, reason: "idle") }
        return ids
    }

    /// Discards least recently seen pages; returns them.
    @discardableResult
    public func handleMemoryPressure(critical: Bool) -> [UUID] {
        let ids = DiscardPolicy.underPressure(discardCandidates, critical: critical)
        for id in ids { discard(id, reason: critical ? "memory pressure (critical)" : "memory pressure") }
        return ids
    }

    /// Discards every background page now (Debug menu).
    @discardableResult
    public func discardBackgroundPages() -> [UUID] {
        let ids = discardCandidates.filter(\.isEligible).map(\.id)
        for id in ids { discard(id, reason: "debug") }
        return ids
    }

    private func discard(_ id: UUID, reason: String) {
        guard let page = pages[id] else { return }
        do {
            try page.contents.discard()
            NSLog("Room: discarded \(page.contents.url?.host() ?? id.uuidString) (\(reason))")
        } catch {
            NSLog("Room: discard of \(id) failed: \(error)")
        }
        sidebar?.pageStateDidChange([id])
    }
}
