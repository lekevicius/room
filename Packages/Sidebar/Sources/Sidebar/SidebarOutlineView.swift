import AppKit
import Design

/// Mouse and key routing the outline hands to the controller.
protocol SidebarOutlineEvents: AnyObject {
    func outlineMiddleClicked(row: Int)
    /// Keyboard focus keys (spec §I.13); `false` passes the event on.
    func outlineKeyDown(_ event: NSEvent) -> Bool
    func outlineMenu(forRow row: Int) -> NSMenu?
    func outlineHoverChanged(row: Int?)
    /// Double-click below the rows: a new tab (spec §F).
    func outlineEmptyAreaDoubleClicked()
    /// A drag left the outline (hide the insertion line).
    func outlineDragExited()
    /// The outline became or stopped being first responder (focus ring).
    func outlineFocusChanged(_ focused: Bool)
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
        // AppKit's selection mirrors the ⌘/⇧-click multi-selection, so a drag
        // of a selected row carries the whole group (spec §A.9).
        allowsMultipleSelection = true
        draggingDestinationFeedbackStyle = .none
        setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        // Outside Room nothing (4.8a): a drop there is the drag out to a new window (spec §A.9).
        setDraggingSourceOperationMask([], forLocal: false)
        allowsTypeSelect = false
        focusRingType = .none
        floatsGroupRows = false
        setAccessibilityIdentifier("sidebar-outline")
        addSubview(pill, positioned: .below, relativeTo: nil)
        addSubview(dropIndicator)
    }

    /// The 2 pt accent insertion line while a drag is over the outline (spec §A.9).
    let dropIndicator = DropIndicatorView()

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Rows draw their own disclosure (folder icon, space-title chevron).
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if row(at: point) < 0 {
            if event.clickCount == 2 {
                events?.outlineEmptyAreaDoubleClicked()
            } else {
                window?.performDrag(with: event)
            }
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
        if events?.outlineKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { events?.outlineFocusChanged(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { events?.outlineFocusChanged(false) }
        return resigned
    }

    // The focus ring follows the window's key state.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyStateChanged), name: name, object: window)
        }
    }

    @objc private func keyStateChanged() { events?.outlineFocusChanged(window?.firstResponder === self) }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        super.draggingExited(sender)
        events?.outlineDragExited()
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

    /// The one tracking area also tells the hovered row's cell whether the
    /// pointer is on its icon (a tracking area per cell cost every scrolled-in row).
    private func updateHover(_ event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        hoveredRow = row >= 0 ? row : nil
        if row >= 0, let cell = view(atColumn: 0, row: row, makeIfNecessary: false) as? EntryCellView {
            cell.pointerMoved(to: cell.convert(event.locationInWindow, from: nil))
        }
    }
}

/// Row background: the 6% hover fill (spec §I.4), inset like the pill; the
/// multi-selection tint (§A.9); the drop-onto highlight (§A.6); the
/// keyboard focus ring (§I.13).
final class SidebarRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("sidebar-row")

    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    /// Rows that never show a hover fill (space title, separator).
    var showsHover = true
    /// The selected entry's row: the pill is drawn instead.
    var isSelectedEntry = false { didSet { if isSelectedEntry != oldValue { needsDisplay = true } } }
    /// In the ⌘/⇧-click multi-selection.
    var isMultiSelected = false { didSet { if isMultiSelected != oldValue { needsDisplay = true } } }
    /// A drag will drop onto this row (into the folder, or a new folder with it).
    var isDropTarget = false { didSet { if isDropTarget != oldValue { needsDisplay = true } } }
    var showsFocusRing = false { didSet { if showsFocusRing != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func drawBackground(in dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: Self.pillRect(in: bounds), xRadius: Radius.medium, yRadius: Radius.medium)
        if isDropTarget {
            Palette.sidebarMultiSelection.setFill()
            shape.fill()
        } else if isMultiSelected && !isSelectedEntry {
            Palette.sidebarMultiSelection.setFill()
            shape.fill()
        } else if isHovered, showsHover, !isSelectedEntry {
            Palette.sidebarHover.setFill()
            shape.fill()
        }
        if isDropTarget || showsFocusRing {
            let ring = NSBezierPath(roundedRect: Self.pillRect(in: bounds).insetBy(dx: 1, dy: 1),
                                    xRadius: Radius.medium - 1, yRadius: Radius.medium - 1)
            ring.lineWidth = SidebarMetrics.insertionLineWidth
            Palette.accent.setStroke()
            ring.stroke()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {}

    /// The pill / hover shape inside a row's bounds.
    static func pillRect(in bounds: NSRect) -> NSRect {
        bounds.insetBy(dx: SidebarMetrics.rowHorizontalInset, dy: SidebarMetrics.pillVerticalInset)
    }
}

/// The insertion line (spec §A.9): 2 pt, accent, rounded, indented to the
/// depth the drop lands at.
final class DropIndicatorView: NSView {
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
        layer?.backgroundColor = Palette.accent.cgColor
        layer?.cornerRadius = SidebarMetrics.insertionLineWidth / 2
    }

    /// Shows the line at `y` (outline coordinates) from `x` to `maxX`; `nil` hides it.
    func show(y: CGFloat?, x: CGFloat, maxX: CGFloat) {
        guard let y else {
            isHidden = true
            return
        }
        let width = SidebarMetrics.insertionLineWidth
        frame = NSRect(x: x, y: y - width / 2, width: max(0, maxX - x), height: width)
        isHidden = false
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
