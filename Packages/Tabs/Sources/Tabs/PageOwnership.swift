import Engine
import Foundation
import Model

/// Page ownership across windows (4.8a, PLAN §4 "Windows and incognito"):
/// an entry's page lives in one window's tab controller (one `RoomBrowser`
/// per window and profile on RoomCore). Selecting the entry in another
/// window moves the page there: the holder hands it over and the claimer
/// moves it into its window with `WebContents.move(toHostWindow:)` (4.8b;
/// 4.8a unloaded it in the first window and loaded it from its saved
/// history in the second).
public enum PageOwnership {
    public enum Claim: Equatable, Sendable {
        /// No window holds the entry's page: make one.
        case load
        /// The requesting window holds it already.
        case keep
        /// Another window holds it: that window gives it up first.
        case move(from: UUID)
    }

    /// Window `window` wants `entry`'s page; `owners` maps entries to the window holding their page.
    public static func claim(_ entry: UUID, by window: UUID, owners: [UUID: UUID]) -> Claim {
        guard let owner = owners[entry] else { return .load }
        return owner == window ? .keep : .move(from: owner)
    }

    /// Where a window's selection goes when its shown page moved to another
    /// window: its most recent other entry (`mru`, most recent first) that
    /// was used and is not on screen in another window, else nothing (the
    /// empty state, spec §A.7).
    public static func fallback(mru: [Entry], losing entry: UUID, visibleElsewhere: Set<UUID>) -> UUID? {
        mru.first { $0.id != entry && $0.kind != .folder && $0.lastActiveAt != nil && !visibleElsewhere.contains($0.id) }?.id
    }
}

/// The app's windows as one tab controller sees them (`RoomWindows` in the
/// app; tests use a fake).
@MainActor
public protocol PageOwnershipCoordinator: AnyObject {
    /// `controller` is about to make a page for `entry`: a window holding
    /// one hands it over (4.8b) and it is returned for `controller` to move
    /// into its window; nil when no other window held it. Its navigation
    /// state is in the entry when this returns.
    func tabController(_ controller: TabController, willMakePageFor entry: UUID) -> (any WebContents)?
    /// The entries on screen in every other window (never discarded, spec §H).
    func entriesVisible(besides controller: TabController) -> Set<UUID>
}

extension TabController {
    /// The entries this window shows: the split's panes, or the card's entry.
    public var visibleEntries: Set<UUID> { visibleEntryIDs }
}

/// The coordinator over a set of windows' tab controllers (the app's
/// windows; tests make their own): a page claimed by one window is given
/// up by the window holding it (`PageOwnership.claim`).
@MainActor
public final class PageOwners: PageOwnershipCoordinator {
    /// The windows' controllers, each with its window's id.
    public var controllers: () -> [TabController]

    public init(controllers: @escaping () -> [TabController]) {
        self.controllers = controllers
    }

    /// Which window holds each entry's page.
    public var owners: [UUID: UUID] {
        var result: [UUID: UUID] = [:]
        for controller in controllers() {
            guard let window = controller.windowID else { continue }
            for id in controller.loadedEntryIDs { result[id] = window }
        }
        return result
    }

    public func tabController(_ controller: TabController, willMakePageFor entry: UUID) -> (any WebContents)? {
        guard let window = controller.windowID,
              case .move(let from) = PageOwnership.claim(entry, by: window, owners: owners) else { return nil }
        for other in controllers() where other !== controller && other.windowID == from {
            if let page = other.handOverPage(entry) { return page }
        }
        return nil
    }

    public func entriesVisible(besides controller: TabController) -> Set<UUID> {
        controllers().filter { $0 !== controller }.reduce(into: Set<UUID>()) { $0.formUnion($1.visibleEntries) }
    }
}
