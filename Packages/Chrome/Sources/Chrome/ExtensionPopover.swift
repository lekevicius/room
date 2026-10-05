import AppKit
import Engine

/// An extension's action popup (ROADMAP 3.6b): the engine's popup page in an
/// `NSPopover` on the action's button, sized by the page itself (the engine
/// clamps it to `ExtensionPopupBounds`), closed when the user clicks or
/// switches away (`.transient`) or presses Esc. No visual polish (Chapter 5).
public final class ExtensionPopover: NSObject, NSPopoverDelegate {
    public let popup: any WebContents
    /// The popover closed by itself (focus loss, Esc, a click elsewhere), not through `close()`.
    public var onClose: (() -> Void)?
    private let popover = NSPopover()
    private let container = NSView()
    private var closingFromCode = false

    public init(popup: any WebContents, size: CGSize) {
        self.popup = popup
        super.init()
        let controller = NSViewController()
        container.frame = NSRect(origin: .zero, size: size)
        let page = popup.nativeView
        page.frame = container.bounds
        page.autoresizingMask = [.width, .height]
        container.addSubview(page)
        controller.view = container
        popover.contentViewController = controller
        popover.contentSize = size
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        container.setAccessibilityIdentifier("extension-popup")
    }

    public var isShown: Bool { popover.isShown }
    /// The popover's own window (spikes send keys to it).
    public var window: NSWindow? { container.window }
    public var contentSize: CGSize { popover.contentSize }

    /// Shows the popup below `rect` of `view` (the action's button) and gives it the keyboard.
    public func show(relativeTo rect: NSRect, of view: NSView) {
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        container.window?.makeKey()
    }

    /// The page asked for another size.
    public func resize(_ size: CGSize) {
        popover.contentSize = size
    }

    /// Closes without `onClose` (the engine already knows).
    public func close() {
        closingFromCode = true
        popover.close()
    }

    public func popoverDidClose(_ notification: Notification) {
        popup.nativeView.removeFromSuperview()
        guard !closingFromCode else { return }
        onClose?()
    }
}
