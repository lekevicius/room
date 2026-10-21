import AppKit
import Design

/// One stretch of the window's Tab order (5.3a, ROADMAP 5.3 task 2): the
/// key views under `roots`, without those under `excluding`.
public struct KeyViewRegion {
    public let roots: [NSView]
    public let excluding: [NSView]

    public init(_ roots: [NSView], excluding: [NSView] = []) {
        self.roots = roots
        self.excluding = excluding
    }
}

/// The browser window's Tab order: sidebar → header → card → footer, then
/// around again (the app gives the regions, `RoomWindow.keyViewRegions`).
/// Inside a region the key views are read top to bottom, leading to
/// trailing. Which views take part is AppKit's rule, `canBecomeKeyView`: a
/// list, a text field and the page always; buttons only while Full Keyboard
/// Access is on (Room's own controls ask `KeyboardAccess`). A view that
/// keeps Tab for its own content (a list, a text field, the page) is not
/// entered; a modal view (a page's dialog) keeps its own loop.
public enum KeyViewLoop {
    /// Views whose insides the loop does not enter: they move the focus among their own parts.
    static func isOpaque(_ view: NSView) -> Bool {
        if view is NSTableView || view is NSTextField || view is NSText { return true }
        let name = NSStringFromClass(type(of: view))
        return name.contains("RenderWidgetHostView")
    }

    /// The key views of `regions`, in Tab order.
    public static func candidates(_ regions: [KeyViewRegion]) -> [NSView] {
        var result: [NSView] = []
        for region in regions {
            var found: [NSView] = []
            func walk(_ view: NSView) {
                guard !view.isHidden, view.alphaValue > 0, !region.excluding.contains(where: { $0 === view }) else { return }
                if view.canBecomeKeyView, !found.contains(where: { $0 === view }) { found.append(view) }
                guard !isOpaque(view) else { return }
                for subview in view.subviews { walk(subview) }
            }
            for root in region.roots where root.window != nil && !root.isHiddenOrHasHiddenAncestor { walk(root) }
            result += ordered(found)
        }
        return result
    }

    /// Top to bottom, then leading to trailing, in window coordinates (rows whose tops share a 4 pt band are one line).
    static func ordered(_ views: [NSView]) -> [NSView] {
        let keyed = views.enumerated().map { offset, view in
            let frame = view.convert(view.bounds, to: nil)
            return (line: -(frame.maxY / ReadingOrder.tolerance).rounded(), x: frame.minX, offset: offset, view: view)
        }
        return keyed.sorted { ($0.line, $0.x, $0.offset) < ($1.line, $1.x, $1.offset) }.map(\.view)
    }

    /// The loop's view that holds `responder` (a field editor stands for its field; a view inside the page for the page).
    static func member(holding responder: NSResponder?, in loop: [NSView]) -> NSView? {
        var view: NSView?
        if let editor = responder as? NSText, editor.isFieldEditor, let field = editor.delegate as? NSView {
            view = field
        } else {
            view = responder as? NSView
        }
        guard let view else { return nil }
        // The innermost: the site button is in the loop and inside the address field, which is too.
        func depth(_ view: NSView) -> Int {
            var count = 0
            var current = view.superview
            while let parent = current { count += 1; current = parent.superview }
            return count
        }
        return loop.filter { view.isDescendant(of: $0) }.max { depth($0) < depth($1) }
    }

    /// Inside a modal view (a page's dialog over the card): its own loop applies.
    static func isInModal(_ responder: NSResponder?) -> Bool {
        var view = (responder as? NSText).flatMap { $0.isFieldEditor ? $0.delegate as? NSView : nil } ?? responder as? NSView
        while let current = view {
            if current is AccessibilityBackdrop { return true }
            view = current.superview
        }
        return false
    }
}

extension RoomWindow {
    /// Rebuilds the `nextKeyView` chain over the loop and moves the focus
    /// through AppKit's own selection (so the page learns the direction and
    /// focuses its first or last element). `false`: not Room's to handle.
    func selectInLoop(forward: Bool, from responder: NSResponder?) -> Bool {
        guard let regions = keyViewRegions?(), !KeyViewLoop.isInModal(responder) else { return false }
        let loop = KeyViewLoop.candidates(regions)
        guard !loop.isEmpty else { return false }
        for (index, view) in loop.enumerated() { view.nextKeyView = loop[(index + 1) % loop.count] }
        if let current = KeyViewLoop.member(holding: responder, in: loop) {
            if forward { appKitSelect(following: current) } else { appKitSelect(preceding: current) }
        } else if forward {
            // From outside the loop (the window itself, an overlay that closed): its first view.
            appKitSelect(following: loop[loop.count - 1])
        } else {
            appKitSelect(preceding: loop[0])
        }
        return true
    }
}
