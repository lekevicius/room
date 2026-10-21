import AppKit
import Design

/// Invisible hit area on the sidebar's inner edge. Dragging reports the
/// proposed sidebar width (the pointer's distance from the sidebar's side of
/// the window, keeping the grab offset).
final class SidebarSplitterView: NSView {
    var edge = SidebarEdge.left {
        didSet { if edge != oldValue { window?.invalidateCursorRects(for: self) } }
    }
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    /// Current width, so the cursor can show which directions are possible.
    var currentWidth: CGFloat = SidebarMetrics.defaultWidth {
        didSet { if currentWidth != oldValue { window?.invalidateCursorRects(for: self) } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("sidebar-splitter")
        // VoiceOver's splitter (5.3a): the width as its value, increment and decrement by 10 pt.
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Sidebar width")
    }

    /// The width a VoiceOver step moves (chosen).
    static let accessibilityStep: CGFloat = 10

    override func accessibilityValue() -> Any? { "\(Int(currentWidth.rounded())) points" }

    override func accessibilityPerformIncrement() -> Bool {
        onDrag?(currentWidth + Self.accessibilityStep)
        onEnd?()
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        onDrag?(max(SidebarMetrics.minWidth, currentWidth - Self.accessibilityStep))
        onEnd?()
        return true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        // Growing moves the splitter away from the sidebar's edge of the window.
        let grow: NSHorizontalDirection.Set = edge == .left ? .right : .left
        let shrink: NSHorizontalDirection.Set = edge == .left ? .left : .right
        let directions: NSHorizontalDirection.Set =
            currentWidth <= SidebarMetrics.minWidth ? grow
            : currentWidth >= SidebarMetrics.maxWidth ? shrink
            : .all
        addCursorRect(bounds, cursor: .columnResize(directions: directions))
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, let root = superview else { return }
        let start = root.convert(event.locationInWindow, from: nil).x
        let edge = edge
        let grabOffset = currentWidth - WindowLayout.proposedWidth(pointerX: start, bounds: root.bounds, grabOffset: 0, edge: edge)
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { event, stop in
            guard let event else { stop.pointee = true; return }
            if event.type == .leftMouseUp {
                stop.pointee = true
                MainActor.assumeIsolated { self.onEnd?() }
                return
            }
            MainActor.assumeIsolated {
                let x = root.convert(event.locationInWindow, from: nil).x
                self.onDrag?(WindowLayout.proposedWidth(pointerX: x, bounds: root.bounds, grabOffset: grabOffset, edge: edge))
            }
        }
    }
}
