import AppKit
import Card
import Sidebar

/// Content dropped on the card (5.5b, spec §I.7, ROADMAP 5.5 task 4): a
/// view over the panes, registered for the content types, that takes no
/// clicks (`hitTest` is nil; AppKit picks drag destinations by registered
/// types, not by `hitTest`) and hands every drag to the page view under the
/// pointer (the deepest view in the panes registered for drags: the engine's
/// own), as if it were not there. What the page refuses Room opens as tabs
/// (`CardDropRule`): text on a part of the page that is not editable becomes
/// a search tab, image data a `file://` tab, a link or file Blink did not
/// load a tab of its own; several links are always Room's (Blink opens only
/// the first). Sidebar entries dragged here are `SplitDropOverlayView`'s,
/// which lies above while a drag of this window's sidebar is on.
final class CardDropView: NSView {
    /// The views drops are handed to (the panes, front last).
    var roots: () -> [NSView] = { [] }
    /// Room's tabs for what the page did not take.
    var onOpen: (([String]) -> Void)?
    /// What Room would open for a pasteboard (`SidebarController.dropURLs`; `writingImages` false while over the card).
    var urls: (NSPasteboard, Bool) -> [String] = { pasteboard, write in SidebarDrop.urls(from: pasteboard, writingImages: write) }
    /// The page view the drag is handed to, and its last answer.
    private var target: NSView?
    private var pageOperation: NSDragOperation = []
    /// The page view that took the drop (it hears the conclusion).
    private var dropped: NSView?
    private var content: (sequence: Int, value: Content)?

    #if DEBUG
    /// Spikes: what the last drop did ("page", "room N", "none") and the page view's class it was handed to.
    private(set) var debugLastDrop: String?
    private(set) var debugTargetClass: String?
    #endif

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(SidebarDrop.contentTypes)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// What is on the drag's pasteboard, read once per drag.
    struct Content {
        var links = 0
        var files = 0
        var fromPage = false
        var roomCanOpen = false
    }

    private func classify(_ info: any NSDraggingInfo) -> Content {
        if let content, content.sequence == info.draggingSequenceNumber { return content.value }
        let pasteboard = info.draggingPasteboard
        let onBoard = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        var value = Content()
        value.links = onBoard.filter { !$0.isFileURL && ["http", "https"].contains($0.scheme?.lowercased() ?? "") }.count
        value.files = onBoard.filter(\.isFileURL).count
        // A drag that began in a page (a link, an image, a selection): Room's other sources are the sidebar and the address field.
        let source = info.draggingSource
        value.fromPage = source != nil && !(source is AddressFieldView) && pasteboard.types?.contains(SidebarDragTypes.entry) != true
        let opened = urls(pasteboard, false)
        value.roomCanOpen = !opened.isEmpty
        // URLs as lines of text are links too: Chromium reads the whole text as one URL (5.5b's first run loaded
        // "…?drop=a%0Ahttp://…"), so two or more are Room's.
        if onBoard.isEmpty, pasteboard.string(forType: .string) != nil {
            let lines = opened.filter { ["http", "https"].contains(URL(string: $0)?.scheme?.lowercased() ?? "") }
            if lines.count > 1 { value.links = lines.count }
        }
        content = (info.draggingSequenceNumber, value)
        return value
    }

    private func owner(_ content: Content) -> CardDropRule.Owner {
        CardDropRule.owner(links: content.links, files: content.files, fromPage: content.fromPage, roomCanOpen: content.roomCanOpen,
                           pageAccepts: !pageOperation.isEmpty)
    }

    /// The deepest view registered for drags under `point` (window coordinates) in the panes.
    private func pageView(at point: NSPoint) -> NSView? {
        for root in roots().reversed() where !root.isHiddenOrHasHiddenAncestor {
            if let view = Self.deepestRegistered(in: root, at: point, excluding: self) { return view }
        }
        return nil
    }

    private static func deepestRegistered(in view: NSView, at point: NSPoint, excluding overlay: NSView) -> NSView? {
        guard !view.isHidden, view !== overlay, view.bounds.contains(view.convert(point, from: nil)) else { return nil }
        for subview in view.subviews.reversed() {
            if let found = deepestRegistered(in: subview, at: point, excluding: overlay) { return found }
        }
        return view.registeredDraggedTypes.isEmpty ? nil : view
    }

    private func hand(_ info: any NSDraggingInfo, to view: NSView?) -> NSDragOperation {
        guard let view else {
            leavePage(info)
            return []
        }
        let destination = view as NSDraggingDestination
        if view !== target {
            leavePage(info)
            target = view
            #if DEBUG
            debugTargetClass = String(describing: type(of: view))
            #endif
            return destination.draggingEntered?(info) ?? []
        }
        return destination.draggingUpdated?(info) ?? []
    }

    private func leavePage(_ info: (any NSDraggingInfo)?) {
        if let target { (target as NSDraggingDestination).draggingExited?(info) }
        target = nil
        pageOperation = []
    }

    private func update(_ info: any NSDraggingInfo) -> NSDragOperation {
        let content = classify(info)
        if content.links > 1, content.files == 0, !content.fromPage, content.roomCanOpen {
            leavePage(info)
            return .copy
        }
        pageOperation = hand(info, to: pageView(at: info.draggingLocation))
        switch owner(content) {
        case .page: return pageOperation
        case .room: return .copy
        case .none: return []
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { leavePage(sender) }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let content = classify(sender)
        switch owner(content) {
        case .page:
            guard let target else { return false }
            let destination = target as NSDraggingDestination
            guard destination.prepareForDragOperation?(sender) ?? true else { return false }
            dropped = target
            self.target = nil
            #if DEBUG
            debugLastDrop = "page"
            #endif
            return destination.performDragOperation?(sender) ?? false
        case .room:
            leavePage(sender)
            let opened = urls(sender.draggingPasteboard, true)
            #if DEBUG
            debugLastDrop = "room \(opened.count)"
            #endif
            guard !opened.isEmpty else { return false }
            onOpen?(opened)
            return true
        case .none:
            leavePage(sender)
            #if DEBUG
            debugLastDrop = "none"
            #endif
            return false
        }
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        if let dropped { (dropped as NSDraggingDestination).concludeDragOperation?(sender) }
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        if let view = dropped ?? target { (view as NSDraggingDestination).draggingEnded?(sender) }
        dropped = nil
        target = nil
        pageOperation = []
        content = nil
    }
}
