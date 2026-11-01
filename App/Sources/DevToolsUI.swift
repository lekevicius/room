import AppKit
import Card
import Design

/// The docked DevTools pane (5.10): Room's strip with the placements and Close over the view the
/// front-end is adopted into. DevTools' own Dock side menu and close button stay hidden (Chrome
/// runs it without a docking controller, RoomCore 3.3b), so the strip is where they live.
final class DevToolsPaneView: NSView {
    let header = DevToolsHeaderView()
    /// The front-end goes here (`DevTools.open(in:)`).
    let host = FlippedPaneView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        host.setAccessibilityIdentifier("devtools-host")
        addSubview(header)
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        let height = DevToolsMetrics.headerHeight
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        host.frame = NSRect(x: 0, y: height, width: bounds.width, height: max(0, bounds.height - height))
    }
}

/// "Developer Tools", then Dock to Left, Bottom and Right, Open in Window and Close (5.10).
final class DevToolsHeaderView: NSView {
    var onPlacement: ((DevToolsPlacement) -> Void)?
    var onClose: (() -> Void)?
    /// The current placement: its button shows selected.
    var placement = DevToolsPlacement.bottom {
        didSet { updateButtons() }
    }

    private let titleLabel = NSTextField(labelWithString: "Developer Tools")
    private let line = HairlineView()
    private var placementButtons: [(DevToolsPlacement, HoverButton)] = []
    private let closeButton = HoverButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("devtools-header")
        titleLabel.font = Typography.secondary
        titleLabel.textColor = Palette.sidebarSecondaryLabel
        addSubview(titleLabel)
        let symbols: [(DevToolsPlacement, Symbol)] = [(.left, .devToolsDockLeft), (.bottom, .devToolsDockBottom), (.right, .devToolsDockRight),
                                                      (.window, .devToolsWindow)]
        for (placement, symbol) in symbols {
            let button = HoverButton()
            button.image = symbol.image(.rowButton, accessibilityDescription: placement.title)
            button.setTip(placement.title)
            button.setAccessibilityIdentifier("devtools-\(placement.rawValue)")
            button.target = self
            button.action = #selector(placementClicked(_:))
            button.tag = DevToolsPlacement.allCases.firstIndex(of: placement) ?? 0
            addSubview(button)
            placementButtons.append((placement, button))
        }
        closeButton.image = Symbol.closeTab.image(.rowButton, accessibilityDescription: "Close Developer Tools")
        closeButton.setTip("Close Developer Tools (⌥⌘I)")
        closeButton.contentTintColor = .labelColor
        closeButton.setAccessibilityIdentifier("devtools-close")
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        addSubview(closeButton)
        addSubview(line)
        updateButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func updateButtons() {
        for (placement, button) in placementButtons {
            button.contentTintColor = placement == self.placement ? .controlAccentColor : .secondaryLabelColor
            button.setAccessibilityValue(placement == self.placement ? "selected" : nil)
        }
    }

    @objc private func placementClicked(_ sender: HoverButton) {
        let placement = DevToolsPlacement.allCases[sender.tag]
        guard placement != self.placement else { return }
        onPlacement?(placement)
    }

    @objc private func closeClicked() { onClose?() }

    override func layout() {
        super.layout()
        let side = DevToolsMetrics.headerButtonSize
        let y = ((bounds.height - side) / 2).rounded()
        var x = bounds.width - Spacing.xs - side
        closeButton.frame = NSRect(x: x, y: y, width: side, height: side)
        x -= Spacing.s
        for (_, button) in placementButtons.reversed() {
            x -= side
            button.frame = NSRect(x: x, y: y, width: side, height: side)
        }
        let height = ceil(titleLabel.cell?.cellSize.height ?? 14)
        titleLabel.frame = NSRect(x: Spacing.s, y: ((bounds.height - height) / 2).rounded(), width: max(0, x - 2 * Spacing.s), height: height)
        line.frame = NSRect(x: 0, y: bounds.height - line.thickness, width: bounds.width, height: line.thickness)
    }
}

/// DevTools in a window of its own (5.10, Open in Window): the same strip over the front-end;
/// closing the window closes DevTools.
final class DevToolsWindowController: NSWindowController, NSWindowDelegate {
    let header = DevToolsHeaderView()
    let host = FlippedPaneView()
    /// The window was closed by its close button (DevTools goes with it).
    var onClose: (() -> Void)?
    private var dismissing = false
    private static let autosaveName = "RoomDevToolsWindow"

    init(title: String?, parent: NSWindow?) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: DevToolsMetrics.windowSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title.map { "Developer Tools — \($0)" } ?? "Developer Tools"
        window.isReleasedWhenClosed = false
        let placed = window.setFrameUsingName(Self.autosaveName)
        window.setFrameAutosaveName(Self.autosaveName)
        if !placed, let parent {
            // Beside the browser window's top-right, the first time.
            window.setFrameTopLeftPoint(NSPoint(x: parent.frame.maxX - DevToolsMetrics.windowSize.width / 2, y: parent.frame.maxY - 40))
        }
        super.init(window: window)
        window.delegate = self
        header.placement = .window
        host.setAccessibilityIdentifier("devtools-host")
        let content = FlippedPaneView()
        content.addSubview(header)
        content.addSubview(host)
        window.contentView = content
        content.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(contentResized), name: NSView.frameDidChangeNotification, object: content)
        contentResized()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func contentResized() {
        guard let content = window?.contentView else { return }
        let height = DevToolsMetrics.headerHeight
        header.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: height)
        host.frame = NSRect(x: 0, y: height, width: content.bounds.width, height: max(0, content.bounds.height - height))
    }

    func show() { window?.makeKeyAndOrderFront(nil) }

    /// Closes the window without asking DevTools again (the host already closed or moved it).
    func dismiss() {
        dismissing = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if !dismissing { onClose?() }
    }
}
