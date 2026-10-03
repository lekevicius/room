import AppKit
import Design

/// Mouse and key routing the outline hands to the controller.
protocol SidebarOutlineEvents: AnyObject {
    func outlineMiddleClicked(row: Int)
    func outlineReturnPressed() -> Bool
    func outlineMenu(forRow row: Int) -> NSMenu?
    func outlineHoverChanged(row: Int?)
}

/// The sidebar tree: a view-based outline with no AppKit selection drawing
/// (the selected entry is marked by `SelectionPillView`), no disclosure
/// triangles (rows draw their own) and no indentation (rows indent
/// themselves). The empty area below the rows moves the window, as the
/// sidebar background does.
final class SidebarOutlineView: NSOutlineView {
    weak var events: SidebarOutlineEvents?
    let pill = SelectionPillView()
    private var hoverTracking: NSTrackingArea?
    private(set) var hoveredRow: Int? {
        didSet { if hoveredRow != oldValue { events?.outlineHoverChanged(row: hoveredRow) } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        addTableColumn(column)
        outlineTableColumn = column
        headerView = nil
        style = .plain
        selectionHighlightStyle = .none
        backgroundColor = .clear
        intercellSpacing = .zero
        indentationPerLevel = 0
        indentationMarkerFollowsCell = false
        autoresizesOutlineColumn = false
        columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        allowsEmptySelection = true
        allowsMultipleSelection = false
        allowsTypeSelect = false
        focusRingType = .none
        floatsGroupRows = false
        setAccessibilityIdentifier("sidebar-outline")
        addSubview(pill, positioned: .below, relativeTo: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Rows draw their own disclosure (folder icon, space-title chevron).
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if row(at: point) < 0 {
            window?.performDrag(with: event)
            return
        }
        super.mouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if event.buttonNumber == 2, row >= 0 {
            events?.outlineMiddleClicked(row: row)
        } else {
            super.otherMouseUp(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           events?.outlineReturnPressed() == true {
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return row >= 0 ? events?.outlineMenu(forRow: row) : nil
    }

    // MARK: Hover (one tracking area for the whole outline)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(event)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoveredRow = nil
    }

    /// Re-evaluates hover after rows moved under a still pointer.
    func refreshHover() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let row = visibleRect.contains(point) ? row(at: point) : -1
        hoveredRow = row >= 0 ? row : nil
    }

    private func updateHover(_ event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        hoveredRow = row >= 0 ? row : nil
    }
}

/// Row background: the 6% hover fill (spec §I.4), inset like the pill.
final class SidebarRowView: NSTableRowView {
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    /// Rows that never show a hover fill (space title, separator).
    var showsHover = true
    /// The selected entry's row: the pill is drawn instead.
    var isSelectedEntry = false { didSet { if isSelectedEntry != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered, showsHover, !isSelectedEntry else { return }
        Palette.sidebarHover.setFill()
        NSBezierPath(roundedRect: Self.pillRect(in: bounds), xRadius: Radius.medium, yRadius: Radius.medium).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {}

    /// The pill / hover shape inside a row's bounds.
    static func pillRect(in bounds: NSRect) -> NSRect {
        bounds.insetBy(dx: SidebarMetrics.rowHorizontalInset, dy: SidebarMetrics.pillVerticalInset)
    }
}

/// The selected entry's "slightly elevated" pill (Dia), one view that slides
/// between rows with `Motion.pill` (spec §I.1); reduced motion crossfades.
final class SelectionPillView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = Radius.medium
        layer.cornerCurve = .continuous
        layer.backgroundColor = Palette.sidebarSelection.cgColor
        layer.shadowColor = Palette.cardShadow.cgColor
        layer.shadowOpacity = effectiveAppearance.isDark ? 0 : SidebarMetrics.pillShadowOpacity
        layer.shadowRadius = SidebarMetrics.pillShadowRadius
        layer.shadowOffset = SidebarMetrics.pillShadowOffset
    }

    /// Moves to `target` (`nil` hides it).
    func move(to target: NSRect?, animated: Bool) {
        guard let target else {
            isHidden = true
            return
        }
        let wasHidden = isHidden
        isHidden = false
        guard let layer, animated, !wasHidden, frame != target else {
            frame = target
            if animated, wasHidden { fadeIn() }
            return
        }
        if Motion.reduceMotion {
            frame = target
            fadeIn()
            return
        }
        let from = layer.presentation() ?? layer
        let fromPosition = from.position
        let fromBounds = from.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = target
        CATransaction.commit()
        let position = Motion.pill.animation(keyPath: "position")
        position.fromValue = NSValue(point: fromPosition)
        position.toValue = NSValue(point: layer.position)
        let bounds = Motion.pill.animation(keyPath: "bounds")
        bounds.fromValue = NSValue(rect: fromBounds)
        bounds.toValue = NSValue(rect: layer.bounds)
        layer.add(position, forKey: "position")
        layer.add(bounds, forKey: "bounds")
    }

    private func fadeIn() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = Motion.fast
        layer?.add(fade, forKey: "fade")
    }
}
