import AppKit
import Design

/// Invisible hit area on the sidebar's trailing edge. Dragging reports the
/// proposed sidebar width (pointer x in the root view, keeping the grab offset).
final class SidebarSplitterView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    /// Current width, so the cursor can show which directions are possible.
    var currentWidth: CGFloat = SidebarMetrics.defaultWidth {
        didSet { if currentWidth != oldValue { window?.invalidateCursorRects(for: self) } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier("sidebar-splitter")
        setAccessibilityRole(.splitter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        let directions: NSHorizontalDirection.Set =
            currentWidth <= SidebarMetrics.minWidth ? .right
            : currentWidth >= SidebarMetrics.maxWidth ? .left
            : .all
        addCursorRect(bounds, cursor: .columnResize(directions: directions))
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, let root = superview else { return }
        let start = root.convert(event.locationInWindow, from: nil).x
        let grabOffset = currentWidth - start
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { event, stop in
            guard let event else { stop.pointee = true; return }
            if event.type == .leftMouseUp {
                stop.pointee = true
                MainActor.assumeIsolated { self.onEnd?() }
                return
            }
            MainActor.assumeIsolated {
                let x = root.convert(event.locationInWindow, from: nil).x
                self.onDrag?(x + grabOffset)
            }
        }
    }
}
