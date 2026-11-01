import AppKit
import Card
import Design
import Engine
import Observation
import Tabs
import UIKitCore

/// Shows the selected entry's page in the window's card, or its split
/// (spec §D: up to four panes in a `SplitView`, the focused pane's page is
/// `contents`), and keeps the card's fill on the focused page's root
/// background, so live resize and loading never expose the window material
/// at the card edges. With no page it shows the empty state ("Press ⌘T…",
/// spec §A.7). A press in a pane focuses it (focus follows click).
final class PageHost: PageDisplay {
    let splitView = SplitView()
    /// The focused pane's container: the prompts, the find bar, the zoom
    /// indicator, the status pill and DevTools follow it.
    var container: PageContainerView { splitView.focusedPane.container }
    private weak var controller: RoomWindowController?
    private(set) var contents: (any WebContents)?
    private var pendingSplit: SplitPresentation?
    /// The page in the card changed (the page's prompts follow it, 2.6a).
    var onShow: (((any WebContents)?) -> Void)?
    /// A press in another pane of the split: its entry becomes the focused one.
    var onFocusPane: ((UUID) -> Void)?
    private var pressMonitor: Any?
    #if DEBUG
    /// Spikes: a press focused another pane — the main-thread time to the field updated, and to the next frame.
    var debugFocusTiming: ((_ handled: Double, _ toFrame: Double) -> Void)?
    #endif

    init(controller: RoomWindowController) {
        self.controller = controller
        controller.cardView.contentView = splitView
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.pressed(event)
            return event
        }
    }

    isolated deinit {
        if let pressMonitor { NSEvent.removeMonitor(pressMonitor) }
    }

    func showSplit(_ split: SplitPresentation?) {
        pendingSplit = split
    }

    func show(_ contents: (any WebContents)?) {
        let split = pendingSplit
        let changed = contents !== self.contents || container.pageView == nil
        if changed {
            self.contents?.devTools?.close()
            container.devTools = nil
            container.isDevToolsOpen = false
            dismissDevToolsWindow()
        }
        let keyboardInSplit = splitView.isSplit && isFirstResponderInSplit
        self.contents = contents
        splitView.apply(split, focused: contents)
        // B-113: a split's panes are cards of their own; the page card steps back.
        controller?.cardView.isSplitHost = split != nil
        // 5.10: one page is edge to edge; a split's panes keep the inset.
        controller?.rootView.isCardInset = split != nil
        // ⌃⇧1…4 and ⌃⇧] / ⌃⇧[ move the keyboard with the focus (a click already put it there).
        if changed, split != nil, keyboardInSplit { focusPage() }
        guard changed else { return }
        trackBackground()
        onShow?(contents)
    }

    /// Whether the keyboard is in one of the split's pages.
    private var isFirstResponderInSplit: Bool {
        guard let view = splitView.window?.firstResponder as? NSView else { return false }
        return view.isDescendant(of: splitView)
    }

    /// Focus follows click (spec §D): a press inside another pane's page
    /// focuses that pane; the press goes on to the page.
    private func pressed(_ event: NSEvent) {
        guard splitView.isSplit, let window = splitView.window, event.window === window,
              let hit = window.contentView?.hitTest(window.contentView?.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
        else { return }
        guard let pane = splitView.panes.first(where: { hit.isDescendant(of: $0.container) }), let entry = pane.entry,
              pane !== splitView.focusedPane else { return }
        #if DEBUG
        let start = ProcessInfo.processInfo.systemUptime
        #endif
        onFocusPane?(entry)
        #if DEBUG
        let handled = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let timing = debugFocusTiming
        CATransaction.setCompletionBlock { timing?(handled, (ProcessInfo.processInfo.systemUptime - start) * 1000) }
        #endif
    }

    /// Puts the keyboard in the page: the first view in its tree that takes
    /// it (Chromium's render widget view inside our container).
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

    var isDevToolsOpen: Bool { container.isDevToolsOpen || devToolsWindow != nil || contents?.devTools?.isOpen == true }

    /// The DevTools window while DevTools is undocked (5.10: DevTools' own Dock side menu undocks it).
    private var devToolsWindow: DevToolsWindowController?

    /// ⌥⌘I: DevTools for the page, where Chrome last docked it (DevTools' own Dock side menu
    /// moves it; its close button closes it), or closed.
    func toggleDevTools(inspecting point: NSPoint? = nil) {
        guard let devTools = contents?.devTools else { return }
        if isDevToolsOpen && point == nil {
            closeDevTools()
            return
        }
        follow(devTools)
        if let point {
            devTools.inspectElement(at: point, in: devToolsHost(for: devTools))
        } else {
            devTools.open(in: devToolsHost(for: devTools))
        }
        updateDevTools()
    }

    /// ⌥⌘J (console) and ⌥⌘C (element picker): open on that tool.
    func openDevTools(_ tool: DevToolsTool) {
        guard let devTools = contents?.devTools else { return }
        follow(devTools)
        devTools.open(in: devToolsHost(for: devTools), tool: tool)
        updateDevTools()
    }

    /// Closes DevTools, docked or in its window.
    func closeDevTools() {
        contents?.devTools?.close()
        container.devTools = nil
        container.isDevToolsOpen = false
        dismissDevToolsWindow()
        focusPage()
    }

    /// The engine tells of every docking change, split move and close (its own controls included).
    private func follow(_ devTools: any DevTools) {
        devTools.onChange = { [weak self, weak devTools] in
            guard let self, let devTools, devTools === self.contents?.devTools else { return }
            self.updateDevTools()
        }
    }

    /// Where the front-end goes now: the card while docked (or before Chrome has said), else its window.
    private func devToolsHost(for devTools: any DevTools) -> NSView {
        if devTools.isOpen, !devTools.isDocked { return showDevToolsWindow().host }
        return container.devToolsHost
    }

    /// Follows the engine: docked, the front-end fills the card under the page, which sits where
    /// DevTools says; undocked, its window; closed, neither.
    private func updateDevTools() {
        guard let devTools = contents?.devTools, devTools.isOpen else {
            container.devTools = nil
            container.isDevToolsOpen = false
            dismissDevToolsWindow()
            return
        }
        if devTools.isDocked || !devTools.isDockable {
            dismissDevToolsWindow()
            container.devTools = devTools
            container.isDevToolsOpen = true
            devTools.open(in: container.devToolsHost)
            container.needsLayout = true
        } else {
            container.devTools = nil
            container.isDevToolsOpen = false
            devTools.open(in: showDevToolsWindow().host)
        }
    }

    private func showDevToolsWindow() -> DevToolsWindowController {
        if let devToolsWindow { return devToolsWindow }
        let window = DevToolsWindowController(title: contents?.title, parent: controller?.window)
        window.onClose = { [weak self] in
            self?.devToolsWindow = nil
            self?.closeDevTools()
        }
        devToolsWindow = window
        window.show()
        return window
    }

    private func dismissDevToolsWindow() {
        devToolsWindow?.dismiss()
        devToolsWindow = nil
    }

    private func trackBackground() {
        let color = withObservationTracking {
            contents?.rootBackgroundColor
        } onChange: { [weakSelf = MainActorWeak(self), id = contents.map(ObjectIdentifier.init)] in
            // Fires before the new value is stored; read it on the next turn.
            Task { @MainActor in
                guard let self = weakSelf.value, self.contents.map(ObjectIdentifier.init) == id else { return }
                self.trackBackground()
            }
        }
        controller?.cardView.backgroundColor = color ?? Palette.cardBackground
        // The optional toolbar sits on that fill (2.7a).
        controller?.rootView.toolbarView.pageBackground = color
    }
}

/// The card's content: the page, and DevTools docked in it (5.10: Chrome's own docking). Docked,
/// the front-end fills the container under the page, and the page sits where DevTools' resizing
/// strategy says (`DevTools.pageFrame(inContainerOf:)`); DevTools draws the split and moves it.
final class PageContainerView: NSView {
    /// The DevTools front-end page is placed in this view (RoomCore 3.3b: `DevToolsWindow`'s front-end adopted).
    let devToolsHost = FlippedPaneView()
    /// Shown in place of a page when nothing is selected.
    let emptyState = CardEmptyStateView()
    /// Over the page, under its prompts: the find bar, the zoom indicator, the status pill (2.6b).
    let toolLayer = ToolLayerView()
    /// Over the page: its dialog sheet or certificate interstitial (2.6a).
    let promptLayer = PromptLayerView()
    /// Docked DevTools: it says where the page goes.
    weak var devTools: (any DevTools)? {
        didSet { needsLayout = true }
    }

    var pageView: NSView? {
        didSet {
            guard pageView !== oldValue else { return }
            // A page view another container took already (Peek → Open as Tab) stays where it is.
            if oldValue?.superview === self { oldValue?.removeFromSuperview() }
            // Above the docked front-end, which fills the container.
            if let pageView { addSubview(pageView, positioned: .above, relativeTo: devToolsHost) }
            // Tools and prompts stay above the page view whatever was added last.
            addSubview(toolLayer, positioned: .above, relativeTo: nil)
            addSubview(promptLayer, positioned: .above, relativeTo: nil)
            needsLayout = true
        }
    }

    var isDevToolsOpen = false {
        didSet {
            devToolsHost.isHidden = !isDevToolsOpen
            needsLayout = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        devToolsHost.isHidden = true
        devToolsHost.setAccessibilityIdentifier("devtools-pane")
        addSubview(devToolsHost)
        addSubview(toolLayer)
        addSubview(promptLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The page's frame: where docked DevTools puts it, else the whole container.
    var pageFrame: NSRect {
        guard isDevToolsOpen, let devTools else { return bounds }
        return devTools.pageFrame(inContainerOf: bounds.size)
    }

    override func layout() {
        super.layout()
        devToolsHost.frame = bounds
        let page = pageFrame
        pageView?.frame = page
        pageView?.isHidden = page.isEmpty && isDevToolsOpen
        promptLayer.frame = page
        toolLayer.frame = page
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

