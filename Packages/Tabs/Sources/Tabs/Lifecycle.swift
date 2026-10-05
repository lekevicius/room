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
        /// What the engine says keeps the page now (unsaved form input,
        /// Picture-in-Picture, sound, a capture: `WebContents.discardBlockers`,
        /// spec §H and §A.7; B-17). Empty on CEF, which cannot see them.
        public var blockers: DiscardBlockers

        public init(id: UUID, kind: EntryKind, isSelected: Bool, isAudible: Bool, isAlive: Bool, lastVisible: Date,
                    blockers: DiscardBlockers = []) {
            self.id = id
            self.kind = kind
            self.isSelected = isSelected
            self.isAudible = isAudible
            self.isAlive = isAlive
            self.lastVisible = lastVisible
            self.blockers = blockers
        }

        /// Never the selected page, a page playing audio, one already
        /// discarded, or one the engine says must stay (a blocked page is
        /// asked again at the next sweep).
        var isEligible: Bool { isCandidate && blockers.isEmpty }

        /// Eligible but for the engine's blockers.
        var isCandidate: Bool { isAlive && !isSelected && !isAudible }
    }

    /// The idle limit of a page's kind: Today tabs 60 min, pinned entries and
    /// essentials 3 h.
    static func idleLimit(_ kind: EntryKind) -> TimeInterval {
        kind == .today ? Timing.discardIdleToday : Timing.discardIdlePermanent
    }

    /// Unseen longer than its kind's limit.
    public static func idle(_ pages: [Page], now: Date) -> [UUID] {
        pages.filter { $0.isEligible && now.timeIntervalSince($0.lastVisible) >= idleLimit($0.kind) }.map(\.id)
    }

    /// Idle past the limit but kept by the engine's blockers, with them.
    public static func idleButBlocked(_ pages: [Page], now: Date) -> [(id: UUID, blockers: DiscardBlockers)] {
        pages.filter { $0.isCandidate && !$0.blockers.isEmpty && now.timeIntervalSince($0.lastVisible) >= idleLimit($0.kind) }
            .map { ($0.id, $0.blockers) }
    }

    /// Memory pressure: least recently seen first, across all spaces. A
    /// moderate level discards the older half of the eligible pages (rounded
    /// up); a critical one the oldest eligible page, and the policy takes the
    /// next while the level lasts, until it clears or none is left.
    public static func underPressure(_ pages: [Page], level: MemoryPressureLevel) -> [UUID] {
        let eligible = pages.filter(\.isEligible).sorted { $0.lastVisible < $1.lastVisible }
        let count = switch level {
        case .none: 0
        case .moderate: (eligible.count + 1) / 2
        case .critical: min(1, eligible.count)
        }
        return eligible.prefix(count).map(\.id)
    }
}

/// Idle and memory-pressure discards (spec §H). The host decides every
/// discard (3.7b): RoomCore never discards a Room page by itself, and the
/// policy asks the engine what keeps a page before discarding it.
extension TabController {
    /// Starts the idle sweep (every `Timing.discardSweepInterval`). With
    /// `systemMemoryPressure` it also listens for macOS's memory-pressure
    /// events itself (CEF, which reports none); RoomCore's reports arrive
    /// through `handleMemoryPressure(_:)` from the app.
    public func startLifecycle(systemMemoryPressure: Bool = true) {
        lifecycleStarted = true
        sweepTimer?.invalidate()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: Timing.discardSweepInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.discardIdlePages() }
        }
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        guard systemMemoryPressure else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            let level: MemoryPressureLevel = event.contains(.critical) ? .critical : event.contains(.warning) ? .moderate : .none
            MainActor.assumeIsolated { _ = self?.handleMemoryPressure(level) }
        }
        source.resume()
        memoryPressureSource = source
    }

    var discardCandidates: [DiscardPolicy.Page] {
        pages.compactMap { id, page in
            guard let entry = store.sidebar.entry(id) else { return nil }
            // A split's panes are all on screen (spec §D), like the selected page.
            var candidate = DiscardPolicy.Page(id: id, kind: entry.kind, isSelected: visibleEntryIDs.contains(id),
                                               isAudible: page.contents.isAudible, isAlive: page.contents.state == .alive,
                                               lastVisible: page.lastVisible)
            // The engine is asked only about pages the host's own rules would discard.
            if candidate.isCandidate { candidate.blockers = page.contents.discardBlockers }
            return candidate
        }
    }

    /// Discards pages idle past their limit; returns them. Pages the engine
    /// keeps are logged and asked again at the next sweep.
    @discardableResult
    public func discardIdlePages() -> [UUID] {
        let candidates = discardCandidates
        let blocked = DiscardPolicy.idleButBlocked(candidates, now: now())
        keptByEngine = Dictionary(blocked.map { ($0.id, $0.blockers) }, uniquingKeysWith: { $1 })
        for (id, blockers) in blocked {
            NSLog("Room: kept \(pages[id]?.contents.url?.host() ?? id.uuidString) past its idle limit: \(blockers.names.joined(separator: ","))")
        }
        let ids = DiscardPolicy.idle(candidates, now: now())
        for id in ids { discard(id, reason: "idle") }
        return ids
    }

    /// The engine's or the system's memory-pressure level (spec §H): a
    /// moderate level discards the older half of the eligible background
    /// pages once; a critical level discards the oldest eligible page now
    /// and the next every `Timing.criticalPressureStep` (and at each repeated
    /// report) until the level drops or nothing eligible is left. Never the
    /// selection, a page playing audio, or a page the engine keeps. Returns
    /// what this call discarded.
    @discardableResult
    public func handleMemoryPressure(_ level: MemoryPressureLevel) -> [UUID] {
        let previous = memoryPressure
        memoryPressure = level
        guard respondsToMemoryPressure else { return [] }
        switch level {
        case .none:
            stopPressureSteps()
            return []
        case .moderate:
            stopPressureSteps()
            // A lasting moderate level (the engine repeats it) discards once.
            guard previous < .moderate else { return [] }
            return discardUnderPressure(.moderate)
        case .critical:
            let ids = discardUnderPressure(.critical)
            if ids.isEmpty {
                stopPressureSteps()
            } else if lifecycleStarted, pressureTimer == nil {
                pressureTimer = Timer.scheduledTimer(withTimeInterval: Timing.criticalPressureStep, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.criticalPressureStep() }
                }
            }
            return ids
        }
    }

    private func criticalPressureStep() {
        guard memoryPressure == .critical, respondsToMemoryPressure, !discardUnderPressure(.critical).isEmpty else {
            return stopPressureSteps()
        }
    }

    private func stopPressureSteps() {
        pressureTimer?.invalidate()
        pressureTimer = nil
    }

    private func discardUnderPressure(_ level: MemoryPressureLevel) -> [UUID] {
        let ids = DiscardPolicy.underPressure(discardCandidates, level: level)
        for id in ids { discard(id, reason: level == .critical ? "memory pressure (critical)" : "memory pressure") }
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
            debugDidDiscard?(id, reason)
        } catch {
            NSLog("Room: discard of \(id) failed: \(error)")
        }
        sidebar?.pageStateDidChange([id])
    }
}
