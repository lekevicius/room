import AppKit
import Design
import Engine
import Observation

/// Find in page as pure rules (spec §C: "3 of 12"; ROADMAP 2.6 task 3).
public enum FindRules {
    /// The count beside the field: empty before there is anything to find,
    /// "No results", or "active of count" (updated while the engine counts).
    public static func label(text: String, result: FindResult?) -> String {
        guard !text.isEmpty, let result else { return "" }
        if result.matchCount == 0 { return result.isFinal ? "No results" : "" }
        return "\(max(result.activeMatch, 1)) of \(result.matchCount)"
    }

    /// Next and previous need something to find and at least one match.
    public static func canStep(text: String, result: FindResult?) -> Bool {
        !text.isEmpty && (result?.matchCount ?? 1) > 0
    }
}

/// The find bar at the card's top-right (spec §C): ⌘F opens it on the page
/// in the card, typing finds as you type, Return / ⌘G next, ⇧Return / ⇧⌘G
/// previous, Esc closes and leaves the active match selected. Each page keeps
/// its own text and whether its bar is open.
public final class FindController {
    private struct State {
        var text = ""
        var isOpen = false
    }

    private weak var host: NSView?
    private var states: [ObjectIdentifier: State] = [:]
    private weak var page: (any WebContents)?
    private var bar: FindBarView?
    /// The bar closed: the keyboard goes back to the page.
    public var onClose: (() -> Void)?
    /// The last text found anywhere: ⌘G on a page without its own starts with it.
    public private(set) var lastText = ""

    /// `host` is a layer over the page (the card's tool layer).
    public init(host: NSView) {
        self.host = host
    }

    public var isVisible: Bool { bar != nil }
    /// The bar on screen (DEBUG captures, spikes).
    public var barView: NSView? { bar }
    public var countText: String { bar?.countLabel.stringValue ?? "" }

    /// The focused page's tool layer (the card's, Peek's): the bar moves there.
    public func setHost(_ host: NSView) {
        guard host !== self.host else { return }
        let wasShown = bar != nil
        removeBar()
        self.host = host
        if wasShown { showBar(focus: false) }
    }

    /// The card shows another page: its own bar, if it had one open.
    public func setPage(_ page: (any WebContents)?) {
        guard page !== self.page else { return }
        removeBar()
        self.page = page
        if let page, states[ObjectIdentifier(page)]?.isOpen == true { showBar(focus: false) }
    }

    /// ⌘F: opens the bar (or focuses it) with its text selected.
    public func showFindBar() {
        guard let page else { return }
        var state = states[ObjectIdentifier(page)] ?? State(text: lastText)
        state.isOpen = true
        states[ObjectIdentifier(page)] = state
        showBar(focus: true)
        if !state.text.isEmpty { page.find(state.text, forward: true, matchCase: false) }
    }

    /// ⌘G / ⇧⌘G (and Return / ⇧Return in the field); opens the bar if needed.
    public func findNext(forward: Bool) {
        guard let page else { return }
        if bar == nil { showFindBar() }
        let text = states[ObjectIdentifier(page)]?.text ?? ""
        guard FindRules.canStep(text: text, result: page.findResult) else { return }
        page.find(text, forward: forward, matchCase: false)
    }

    /// Esc or ×: the bar goes, the active match stays selected.
    public func close() {
        guard let page else { return }
        states[ObjectIdentifier(page)]?.isOpen = false
        page.stopFind(clearSelection: false)
        removeBar()
        onClose?()
    }

    /// The page closed: its state goes.
    public func pageClosed(_ page: any WebContents) {
        states.removeValue(forKey: ObjectIdentifier(page))
        if page === self.page { removeBar(); self.page = nil }
    }

    // MARK: The bar

    private func showBar(focus: Bool) {
        guard let host, let page else { return }
        if bar == nil {
            let bar = FindBarView()
            bar.onTextChange = { [weak self] text in self?.textChanged(text) }
            bar.onStep = { [weak self] forward in self?.findNext(forward: forward) }
            bar.onClose = { [weak self] in self?.close() }
            host.addSubview(bar)
            self.bar = bar
            layout()
            observe(page)
        }
        let text = states[ObjectIdentifier(page)]?.text ?? ""
        bar?.field.stringValue = text
        updateCount()
        if focus, let bar {
            bar.window?.makeFirstResponder(bar.field)
            bar.field.currentEditor()?.selectAll(nil)
        }
    }

    private func removeBar() {
        bar?.removeFromSuperview()
        bar = nil
    }

    /// Top-right of the card (spec §C).
    public func layout() {
        guard let bar, let host else { return }
        let width = min(FindMetrics.width, host.bounds.width - 2 * FindMetrics.inset)
        let y = host.isFlipped ? FindMetrics.inset : host.bounds.height - FindMetrics.inset - FindMetrics.height
        bar.frame = NSRect(x: host.bounds.width - FindMetrics.inset - width, y: y, width: width, height: FindMetrics.height)
        bar.autoresizingMask = host.isFlipped ? [.minXMargin, .maxYMargin] : [.minXMargin, .minYMargin]
    }

    private func textChanged(_ text: String) {
        guard let page else { return }
        states[ObjectIdentifier(page), default: State(isOpen: true)].text = text
        if text.isEmpty {
            page.stopFind(clearSelection: true)
        } else {
            lastText = text
            page.find(text, forward: true, matchCase: false)
        }
        updateCount()
    }

    private func observe(_ page: any WebContents) {
        let ref = PageRef(page)
        withObservationTracking {
            _ = page.findResult
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let page = ref.page, page === self.page, self.bar != nil else { return }
                self.updateCount()
                self.observe(page)
            }
        }
    }

    private func updateCount() {
        guard let bar, let page else { return }
        let text = states[ObjectIdentifier(page)]?.text ?? ""
        bar.countLabel.stringValue = FindRules.label(text: text, result: page.findResult)
        let canStep = FindRules.canStep(text: text, result: page.findResult)
        bar.previous.isEnabled = canStep
        bar.next.isEnabled = canStep
        bar.needsLayout = true
    }
}

/// Field, count, previous / next, close on a glass capsule.
final class FindBarView: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    let countLabel = NSTextField(labelWithString: "")
    let previous = HoverButton()
    let next = HoverButton()
    private let closeButton = HoverButton()
    private let glass = NSGlassEffectView()
    private let content = NSView()
    var onTextChange: ((String) -> Void)?
    var onStep: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        glass.cornerRadius = Radius.large
        glass.contentView = content
        addSubview(glass)
        let icon = NSImageView(image: Symbol.search.image(pointSize: 12) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.identifier = NSUserInterfaceItemIdentifier("icon")
        content.addSubview(icon)
        field.placeholderString = "Find in page"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Typography.row
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setAccessibilityIdentifier("find-field")
        content.addSubview(field)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.setAccessibilityIdentifier("find-count")
        content.addSubview(countLabel)
        for (button, symbol, label, action) in [(previous, Symbol.findPrevious, "Previous (⇧⌘G)", #selector(previousClicked)),
                                                (next, Symbol.findNext, "Next (⌘G)", #selector(nextClicked)),
                                                (closeButton, Symbol.closeTab, "Done (Esc)", #selector(closeClicked))] {
            button.image = symbol.image(pointSize: 11, weight: .semibold, accessibilityDescription: label)
            button.toolTip = label
            button.target = self
            button.action = action
            content.addSubview(button)
        }
        setAccessibilityIdentifier("find-bar")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        glass.frame = bounds
        content.frame = bounds
        let h = bounds.height, button: CGFloat = 22, pad = Spacing.s
        var x = bounds.width - pad - button
        closeButton.frame = NSRect(x: x, y: (h - button) / 2, width: button, height: button)
        x -= button + 2
        next.frame = NSRect(x: x, y: (h - button) / 2, width: button, height: button)
        x -= button
        previous.frame = NSRect(x: x, y: (h - button) / 2, width: button, height: button)
        let countWidth = ceil(countLabel.cell?.cellSize.width ?? 0)
        let countHeight = ceil(countLabel.cell?.cellSize.height ?? 14)
        x -= countWidth + Spacing.xs
        countLabel.frame = NSRect(x: x, y: (h - countHeight) / 2, width: countWidth, height: countHeight)
        let iconSize: CGFloat = 14
        content.subviews.first { $0.identifier?.rawValue == "icon" }?.frame = NSRect(x: pad + 2, y: (h - iconSize) / 2, width: iconSize, height: iconSize)
        let fieldX = pad + iconSize + Spacing.s
        let fieldHeight = ceil(field.cell?.cellSize.height ?? 17)
        field.frame = NSRect(x: fieldX, y: (h - fieldHeight) / 2, width: max(40, x - Spacing.xs - fieldX), height: fieldHeight)
    }

    func controlTextDidChange(_ notification: Notification) {
        onTextChange?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onStep?(!(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false))
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            onStep?(false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }

    @objc private func previousClicked() { onStep?(false) }
    @objc private func nextClicked() { onStep?(true) }
    @objc private func closeClicked() { onClose?() }
}

/// The find bar's size and place (chosen; spec §C puts it at the card's top-right).
public enum FindMetrics {
    public static let width: CGFloat = 320
    public static let height: CGFloat = 36
    /// From the card's top and trailing edges.
    public static let inset: CGFloat = Spacing.s
}
