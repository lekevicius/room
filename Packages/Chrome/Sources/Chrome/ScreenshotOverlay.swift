import AppKit
import Design

/// ⇧⌘2's overlay over the page (4.7a): everything outside the selection is
/// dimmed; a drag selects a rectangle, Return takes the whole viewport, Esc
/// cancels. Once the host has the image, a bar under the selection offers
/// Copy, Save, Open as Tab and (when the engine can) Full Page. Coordinates
/// are the page view's: flipped, points, the top-left origin.
public final class ScreenshotOverlayView: NSView {
    public enum Action: Sendable, Equatable {
        case copy, save, openAsTab, fullPage, close
    }

    /// A rectangle was chosen (a drag, or Return for the whole view).
    public var onSelect: ((CGRect) -> Void)?
    /// Esc, or the bar's ×.
    public var onCancel: (() -> Void)?
    /// A button of the bar.
    public var onAction: ((Action) -> Void)?

    public private(set) var selection: CGRect?
    private var dragStart: CGPoint?
    private let bar = NSView()
    private let label = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var fullPageButton: NSButton?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Screenshot selection")
        bar.wantsLayer = true
        bar.layer?.cornerRadius = ScreenshotMetrics.barCornerRadius
        bar.isHidden = true
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        stack.orientation = .horizontal
        stack.spacing = ScreenshotMetrics.barGap
        stack.edgeInsets = NSEdgeInsets(top: 0, left: ScreenshotMetrics.barPadding, bottom: 0, right: ScreenshotMetrics.barPadding)
        stack.addArrangedSubview(label)
        for (title, action, key) in [("Copy", Action.copy, "c"), ("Save", .save, "s"), ("Open as Tab", .openAsTab, ""),
                                     ("Full Page", .fullPage, ""), ("Done", .close, "")] {
            let button = NSButton(title: title, target: self, action: #selector(buttonPressed(_:)))
            button.bezelStyle = .push
            button.controlSize = .small
            button.keyEquivalent = key
            button.keyEquivalentModifierMask = key.isEmpty ? [] : .command
            button.tag = Self.actions.firstIndex(of: action) ?? 0
            if action == .fullPage { fullPageButton = button }
            stack.addArrangedSubview(button)
        }
        bar.addSubview(stack)
        addSubview(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static let actions: [Action] = [.copy, .save, .openAsTab, .fullPage, .close]

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBarColours()
    }

    private func updateBarColours() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            bar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            bar.layer?.borderColor = NSColor.separatorColor.cgColor
            bar.layer?.borderWidth = ScreenshotMetrics.selectionBorderWidth
        }
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let selection {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(ScreenshotMetrics.dimAlpha).setFill()
        dim.fill()
        if let selection {
            let outline = NSBezierPath(rect: selection.insetBy(dx: ScreenshotMetrics.selectionBorderWidth / 2,
                                                              dy: ScreenshotMetrics.selectionBorderWidth / 2))
            outline.lineWidth = ScreenshotMetrics.selectionBorderWidth
            NSColor.white.setStroke()
            outline.stroke()
        }
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if !bar.isHidden { addCursorRect(bar.frame, cursor: .arrow) }
    }

    // MARK: Input

    public override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
        hideBar()
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = ScreenshotRules.selection(from: dragStart, to: point, within: bounds, minimum: 0)
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        dragStart = nil
        let end = convert(event.locationInWindow, from: nil)
        select(ScreenshotRules.selection(from: start, to: end, within: bounds, minimum: ScreenshotMetrics.minimumSelection))
    }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: select(bounds)  // Return, Enter: the whole viewport
        case 53: onCancel?()  // Esc
        default: super.keyDown(with: event)
        }
    }

    public override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Selects `rect` as a drag would (the spikes; Return).
    public func select(_ rect: CGRect?) {
        selection = rect
        needsDisplay = true
        if let rect { onSelect?(rect) }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard Self.actions.indices.contains(sender.tag) else { return }
        onAction?(Self.actions[sender.tag])
    }

    // MARK: The bar

    /// Shows the bar with `text` (the image's size) under the selection, or
    /// above it, or inside its bottom edge when neither fits.
    public func showBar(_ text: String, fullPageAvailable: Bool) {
        label.stringValue = text
        fullPageButton?.isHidden = !fullPageAvailable
        updateBarColours()
        stack.layoutSubtreeIfNeeded()
        let size = CGSize(width: stack.fittingSize.width, height: ScreenshotMetrics.barHeight)
        let anchor = selection ?? bounds
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + ScreenshotMetrics.barGap)
        if origin.y + size.height > bounds.maxY { origin.y = anchor.minY - ScreenshotMetrics.barGap - size.height }
        if origin.y < bounds.minY { origin.y = anchor.maxY - ScreenshotMetrics.barGap - size.height }
        origin.x = min(max(bounds.minX + ScreenshotMetrics.barGap, origin.x), bounds.maxX - ScreenshotMetrics.barGap - size.width)
        bar.frame = CGRect(origin: origin, size: size)
        stack.frame = bar.bounds
        bar.isHidden = false
        window?.invalidateCursorRects(for: self)
    }

    /// The bar's text while the host works (the full page capturing).
    public func setBarText(_ text: String) { label.stringValue = text }

    public func hideBar() {
        bar.isHidden = true
        window?.invalidateCursorRects(for: self)
    }

    public var isBarShown: Bool { !bar.isHidden }
    public var barFrame: CGRect { bar.frame }
}
