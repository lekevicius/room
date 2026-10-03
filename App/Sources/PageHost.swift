import AppKit
import Card
import Design
import Engine
import Observation
import Tabs
import UIKitCore

/// Shows one page in the window's card and keeps the card's fill on the
/// page's root background, so live resize and loading never expose the
/// window material at the card edges. With no page it shows the empty
/// state ("Press ⌘T…", spec §A.7).
final class PageHost: PageDisplay {
    let container = PageContainerView()
    private weak var controller: RoomWindowController?
    private(set) var contents: (any WebContents)?
    /// The page in the card changed (the page's prompts follow it, 2.6a).
    var onShow: (((any WebContents)?) -> Void)?

    init(controller: RoomWindowController) {
        self.controller = controller
        controller.cardView.contentView = container
    }

    func show(_ contents: (any WebContents)?) {
        guard contents !== self.contents || container.pageView == nil else { return }
        self.contents?.devTools?.close()
        container.isDevToolsOpen = false
        self.contents = contents
        container.pageView = contents?.nativeView ?? container.emptyState
        trackBackground()
        onShow?(contents)
    }

    /// Puts the keyboard in the page: the first view in its tree that takes
    /// it (CEF's render view inside our container).
    func focusPage() {
        guard let window = container.window else { return }
        guard let root = contents?.nativeView else {
            window.makeFirstResponder(nil)
            return
        }
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.acceptsFirstResponder {
                window.makeFirstResponder(view)
                return
            }
            queue += view.subviews
        }
        window.makeFirstResponder(root)
    }

    var isDevToolsOpen: Bool { container.isDevToolsOpen || contents?.devTools?.isOpen == true }

    /// ⌥⌘I. Docked under the page when the engine can (Debug: the front-end
    /// over the debugging port); otherwise the engine's own window (Release).
    func toggleDevTools(inspecting point: NSPoint? = nil) {
        guard let devTools = contents?.devTools else { return }
        if isDevToolsOpen && point == nil {
            devTools.close()
            container.isDevToolsOpen = false
            return
        }
        showPane(for: devTools)
        if let point {
            devTools.inspectElement(at: point, in: container.devToolsPane)
        } else {
            devTools.open(in: container.devToolsPane)
        }
    }

    /// ⌥⌘J (console) and ⌥⌘C (element picker): open on that tool.
    func openDevTools(_ tool: DevToolsTool) {
        guard let devTools = contents?.devTools else { return }
        showPane(for: devTools)
        devTools.open(in: container.devToolsPane, tool: tool)
    }

    private func showPane(for devTools: any DevTools) {
        guard devTools.isDockable else { return }
        container.isDevToolsOpen = true
        container.layoutSubtreeIfNeeded()
    }

    private func trackBackground() {
        let color = withObservationTracking {
            contents?.rootBackgroundColor
        } onChange: { [weak self] in
            // Fires before the new value is stored; read it on the next turn.
            Task { @MainActor in self?.trackBackground() }
        }
        controller?.cardView.backgroundColor = color ?? Palette.cardBackground
        // The optional toolbar sits on that fill (2.7a).
        controller?.rootView.toolbarView.pageBackground = color
    }
}

/// The card's content: the page on top, an optional DevTools pane below it.
final class PageContainerView: NSView {
    /// CEF renders DevTools as a child view of this pane (`ShowDevTools` + `SetAsChild`).
    let devToolsPane = FlippedPaneView()
    /// Shown in place of a page when nothing is selected.
    let emptyState = CardEmptyStateView()
    /// Over the page, under its prompts: the find bar, the zoom indicator, the status pill (2.6b).
    let toolLayer = ToolLayerView()
    /// Over the page: its dialog sheet or certificate interstitial (2.6a).
    let promptLayer = PromptLayerView()
    /// Between the page and DevTools: drag to resize, double-click for the default.
    private let divider = DevToolsDividerView()

    var pageView: NSView? {
        didSet {
            guard pageView !== oldValue else { return }
            // A page view another container took already (Peek → Open as Tab) stays where it is.
            if oldValue?.superview === self { oldValue?.removeFromSuperview() }
            if let pageView { addSubview(pageView, positioned: .below, relativeTo: nil) }
            // Tools and prompts stay above the page view whatever was added last.
            addSubview(toolLayer, positioned: .above, relativeTo: nil)
            addSubview(promptLayer, positioned: .above, relativeTo: nil)
            addSubview(divider, positioned: .above, relativeTo: nil)
            needsLayout = true
        }
    }

    var isDevToolsOpen = false {
        didSet {
            devToolsPane.isHidden = !isDevToolsOpen
            divider.isHidden = !isDevToolsOpen
            needsLayout = true
        }
    }

    /// The card's share DevTools takes when open; dragging the divider sets it,
    /// and it is remembered across launches (a view preference, not model state).
    var devToolsFraction: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: PageContainerView.fractionKey)
        return stored > 0 ? CGFloat(stored) : DevToolsMetrics.defaultFraction
    }() {
        didSet { needsLayout = true }
    }

    private static let fractionKey = "RoomDevToolsFraction"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        devToolsPane.isHidden = true
        divider.isHidden = true
        devToolsPane.setAccessibilityIdentifier("devtools-pane")
        divider.onDrag = { [weak self] y in
            guard let self else { return }
            devToolsFraction = DevToolsSplit.fraction(dividerAt: y, height: bounds.height)
        }
        divider.onDragEnd = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(Double(devToolsFraction), forKey: Self.fractionKey)
        }
        divider.onReset = { [weak self] in
            self?.devToolsFraction = DevToolsMetrics.defaultFraction
            UserDefaults.standard.removeObject(forKey: Self.fractionKey)
        }
        addSubview(devToolsPane)
        addSubview(toolLayer)
        addSubview(promptLayer)
        // Above the pane's and the page's own views (CEF's), so it gets the drags.
        addSubview(divider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let paneHeight = isDevToolsOpen ? DevToolsSplit.paneHeight(fraction: devToolsFraction, height: bounds.height) : 0
        pageView?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - paneHeight)
        promptLayer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - paneHeight)
        toolLayer.frame = promptLayer.frame
        devToolsPane.frame = NSRect(x: 0, y: bounds.height - paneHeight, width: bounds.width, height: paneHeight)
        let hit = DevToolsMetrics.dividerHitHeight
        divider.frame = NSRect(x: 0, y: bounds.height - paneHeight - hit / 2, width: bounds.width, height: hit)
    }
}

final class FlippedPaneView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Holds the page's dialog or interstitial over the page view; without one
/// it lets every event through to the page.
final class PromptLayerView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !subviews.isEmpty else { return nil }
        return super.hitTest(point)
    }
}

/// Holds the find bar, the zoom indicator and the status pill over the page;
/// only they take events, the rest of the page stays clickable.
final class ToolLayerView: NSView {
    /// After every layout (the status pill and the indicator re-place themselves).
    var onLayout: (() -> Void)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// The DevTools pane's top edge: a 1 pt line in an 8 pt drag area with the
/// up-down resize cursor (ROADMAP 2.6 task 4).
final class DevToolsDividerView: NSView {
    /// The divider's new position, in the container's (flipped) coordinates.
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onReset: (() -> Void)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: (bounds.height / 2).rounded(.down), width: bounds.width, height: 1).fill()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { return onReset?() ?? () }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let container = superview else { return }
        onDrag?(container.convert(event.locationInWindow, from: nil).y)
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }
}
