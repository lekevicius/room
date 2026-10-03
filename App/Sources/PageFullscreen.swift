import AppKit
import Engine
import UIKitCore

/// A page's element fullscreen (a video's fullscreen button,
/// `requestFullscreen()`; `webContentsDidRequestEnterFullscreen`): the card
/// takes the whole window, edge to edge, and the window goes fullscreen if
/// it was not already. Leaving restores both. Leaving window fullscreen
/// (the green button, ⌃⌘F) or showing another page takes the page out of
/// fullscreen too.
final class PageFullscreen {
    private weak var controller: RoomWindowController?
    /// In a split the fullscreen pane fills the card alone (B-35).
    weak var host: PageHost?
    /// The page in element fullscreen.
    private(set) weak var page: (any WebContents)?
    /// The window went fullscreen for the page (and leaves with it).
    private var enteredWindowFullscreen = false

    init(controller: RoomWindowController) {
        self.controller = controller
    }

    var isActive: Bool { page != nil }

    func enter(_ contents: any WebContents, shown: (any WebContents)?) {
        guard let controller, let window = controller.window, contents === shown else {
            // Only the page in the card (in a split: the focused pane's) can take the window.
            contents.exitFullscreen()
            return
        }
        page = contents
        host?.splitView.fullscreenContents = contents
        controller.rootView.isPageFullscreen = true
        if !window.styleMask.contains(.fullScreen) {
            enteredWindowFullscreen = true
            window.toggleFullScreen(nil)
        }
    }

    func exit(_ contents: any WebContents) {
        guard contents === page else { return }
        restore()
    }

    /// Window fullscreen ended while a page was fullscreen.
    func windowDidExitFullscreen() {
        guard let page else { return }
        enteredWindowFullscreen = false
        page.exitFullscreen()
        restore()
    }

    /// The card shows another page (or none).
    func cardDidShow(_ contents: (any WebContents)?) {
        guard let page, page !== contents else { return }
        page.exitFullscreen()
        restore()
    }

    private func restore() {
        page = nil
        host?.splitView.fullscreenContents = nil
        controller?.rootView.isPageFullscreen = false
        guard enteredWindowFullscreen else { return }
        enteredWindowFullscreen = false
        if let window = controller?.window, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
    }
}
