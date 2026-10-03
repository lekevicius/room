import AppKit
import Design
import Model
import Store

/// One space's list (space title → pinned → separator → Today → New Tab):
/// its own outline in its own scroll view. Every space of the window has
/// one, built ahead of time (`SidebarController.prepareSpaces`), so a
/// space switch slides two lists that already exist instead of reloading
/// one (ROADMAP 2.5 exit: the 2.2a full reload took 42.7 ms for 508 rows).
/// Store changes reach every built pane; only the active one animates them.
final class SpacePane {
    let spaceID: UUID
    let outline = SidebarOutlineView()
    let scrollView = SpaceScrollView()
    let tree: SidebarTree
    /// The outline has its rows (`reloadData` ran since the last invalidation).
    var isLoaded = false

    init(store: SidebarStore, spaceID: UUID, selectedEntry: UUID?) {
        self.spaceID = spaceID
        tree = SidebarTree(store: store, spaceID: spaceID, selectedEntry: selectedEntry)
        scrollView.documentView = outline
        // Height comes from `tile()` in `SidebarBodyView.layout()`: with height autoresizing a
        // shorter window shrank the outline below its rows (2.2b), cutting off the last ones.
        outline.autoresizingMask = [.width]
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.wantsLayer = true
        scrollView.isHidden = true
        scrollView.setAccessibilityIdentifier("space-list")
    }
}

/// Which way a space switch moves the lists.
enum SlideDirection {
    /// To a space further right in the footer: the lists move left.
    case forward
    case backward

    init(from: Int, to: Int) { self = to >= from ? .forward : .backward }

    /// The incoming list's start offset in list widths (+1 = from the right).
    var sign: CGFloat { self == .forward ? 1 : -1 }
}
