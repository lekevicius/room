import AppKit
import Design
import Engine
#if ROOM_ENGINE_ROOMCORE
import EngineRoomCore
#endif

/// Document picture-in-picture (`documentPictureInPicture.requestWindow`,
/// 4.6, B-51): the page the engine made for it floats in its own panel of
/// the requested size, above other windows and on every Space, at the
/// card's top-right corner; no sidebar. The panel closes when the page
/// closes (its `window.close()`, the opener closing, the engine), and the
/// page closes when the user closes the panel; the opener stays loaded.
/// Popups stay Today tabs (2.6's rule). Video picture-in-picture is the
/// engine's own overlay window, not this.
@MainActor
final class PictureInPicturePanels: NSObject, WebContentsUIDelegate, NSWindowDelegate {
    /// One floating page.
    final class Item {
        let panel: NSPanel
        let contents: any WebContents
        weak var opener: (any WebContents)?
        let entry: UUID
        /// The size the page asked for (`requestedBounds`), if the engine reported one.
        let requestedSize: CGSize?

        init(panel: NSPanel, contents: any WebContents, opener: any WebContents, entry: UUID, requestedSize: CGSize?) {
            self.panel = panel
            self.contents = contents
            self.opener = opener
            self.entry = entry
            self.requestedSize = requestedSize
        }
    }

    /// The card's frame in screen coordinates (the panel's corner).
    var cardScreenRect: () -> NSRect = { NSScreen.main?.visibleFrame ?? .zero }
    /// The page's other UI (dialogs, permission prompts) goes where the card's pages' goes.
    weak var pageUIDelegate: (any WebContentsUIDelegate)?
    private(set) var items: [Item] = []
    /// Spikes: each panel shown and closed.
    var debugOnShow: ((Item) -> Void)?
    var debugOnClose: ((Item) -> Void)?

    /// The size used when the engine reported none (Chrome's document PiP default is the page's choice).
    static let fallbackSize = CGSize(width: 400, height: 225)

    func present(_ contents: any WebContents, opener: any WebContents, entry: UUID) {
        let requested = Self.requestedSize(of: contents)
        let screen = NSScreen.screens.first { $0.frame.intersects(cardScreenRect()) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        var size = requested ?? Self.fallbackSize
        size.width = min(max(size.width, PictureInPictureMetrics.minimumSize.width), visible.width - 2 * Spacing.l)
        size.height = min(max(size.height, PictureInPictureMetrics.minimumSize.height), visible.height - 2 * Spacing.l)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.title = contents.title ?? opener.url?.host() ?? "Picture in Picture"
        panel.delegate = self
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = CardMetrics.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        let view = contents.nativeView
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
        panel.contentView = container
        // The card's top-right corner, inside the visible screen.
        let card = cardScreenRect()
        let frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var origin = NSPoint(x: card.maxX - Spacing.l - frame.width, y: card.maxY - Spacing.l - frame.height)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        panel.setFrameOrigin(origin)
        contents.uiDelegate = self
        let item = Item(panel: panel, contents: contents, opener: opener, entry: entry, requestedSize: requested)
        items.append(item)
        panel.orderFront(nil)
        NSLog("Room: document picture-in-picture panel %@ (requested %@) for entry %@", NSStringFromRect(panel.frame),
              requested.map { NSStringFromSize($0) } ?? "none", entry.uuidString)
        debugOnShow?(item)
    }

    /// What the page asked for (engine-specific: RoomCore reports `requestedBounds`).
    static func requestedSize(of contents: any WebContents) -> CGSize? {
        #if ROOM_ENGINE_ROOMCORE
        if let bounds = (contents as? RoomCoreWebContents)?.requestedBounds, bounds.width > 0, bounds.height > 0 { return bounds.size }
        #endif
        return nil
    }

    func item(for contents: any WebContents) -> Item? { items.first { $0.contents === contents } }

    // MARK: WebContentsUIDelegate

    /// The page closed (its `window.close()`, the opener closing): its panel goes.
    func webContentsDidClose(_ webContents: any WebContents) {
        pageUIDelegate?.webContentsDidClose(webContents)
        guard let index = items.firstIndex(where: { $0.contents === webContents }) else { return }
        let item = items.remove(at: index)
        item.panel.delegate = nil
        item.panel.close()
        NSLog("Room: document picture-in-picture closed with its page")
        debugOnClose?(item)
    }

    /// A popup from the PiP page opens under its opener's entry as any other (through the card's delegate).
    func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?,
                     disposition: Disposition) {
        if let pageUIDelegate, let opener = item(for: webContents)?.opener {
            pageUIDelegate.webContents(opener, didCreate: newContents, targetURL: targetURL, disposition: disposition)
        } else {
            newContents.close()
        }
    }

    // MARK: NSWindowDelegate

    /// The user closed the panel: the page closes (the opener stays loaded).
    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, let index = items.firstIndex(where: { $0.panel === panel }) else { return }
        let item = items.remove(at: index)
        NSLog("Room: document picture-in-picture panel closed by the user")
        item.contents.close()
        debugOnClose?(item)
    }
}
