import AppKit
import Engine
import RoomCore

/// DevTools for one `RoomCoreWebContents`: Chrome's `DevToolsWindow` with its
/// bindings and lifetime, its front-end page shown in the host's pane.
///
/// The inspected page's `Browser` has no `DevtoolsUIController`, so Chrome
/// cannot dock and makes a DevTools `Browser` of its own, which RoomCore
/// keeps headless (no Chromium window, 3.2a); the front-end `WebContents`
/// stays in that Browser's strip and its view is adopted here into the view
/// the host gives (ROADMAP 3.3, shape (a)). No remote-debugging port.
@MainActor
public final class RoomCoreDevTools: DevTools {
    private weak var contents: RoomCoreWebContents?
    private var frontend: RoomCoreWebContents?
    private weak var hostView: NSView?

    init(contents: RoomCoreWebContents) {
        self.contents = contents
    }

    /// The front-end page (devtools://), for the spikes that read its panels.
    public var frontendPage: RoomCoreWebContents? { frontend }

    public var isOpen: Bool {
        guard let contents, let frontend, frontend.state != .closed else { return false }
        return contents.page.isDevToolsOpen
    }

    /// The pane is the host's on RoomCore, Debug and Release alike.
    public var isDockable: Bool { true }

    public func open(in hostView: NSView) {
        show(.default, in: hostView)
    }

    /// ⌥⌘J: the console panel; ⌥⌘C: Chrome's Inspect (the element picker).
    public func open(in hostView: NSView, tool: DevToolsTool) {
        switch tool {
        case .console: show(.console, in: hostView)
        case .elementPicker: show(.elementPicker, in: hostView)
        }
    }

    /// `DevToolsWindow::InspectElement` at `point` (the page view's top-left
    /// coordinates): the Elements panel with that element selected.
    public func inspectElement(at point: NSPoint, in hostView: NSView) {
        guard let contents, contents.state != .closed else { return }
        contents.page.inspectElement(at: point)
        adopt(in: hostView)
    }

    /// Closes Chrome's DevTools Browser (the front-end goes with it).
    public func close() {
        contents?.page.closeDevTools()
        frontend?.nativeView.removeFromSuperview()
        frontend = nil
        hostView = nil
    }

    private func show(_ tool: RoomDevToolsTool, in hostView: NSView) {
        guard let contents, contents.state != .closed else { return }
        contents.page.showDevTools(tool)
        adopt(in: hostView)
    }

    /// Shows the front-end filling `hostView`; a second host takes it over.
    private func adopt(in hostView: NSView) {
        guard let contents, let page = contents.page.devToolsWebContents else { return }
        if frontend?.page !== page {
            frontend?.nativeView.removeFromSuperview()
            frontend = RoomCoreWebContents(page: page, configuration: WebContentsConfiguration(), profile: nil)
        }
        guard let frontend else { return }
        let view = frontend.nativeView
        if view.superview !== hostView {
            view.removeFromSuperview()
            view.frame = hostView.bounds
            view.autoresizingMask = [.width, .height]
            hostView.addSubview(view)
            // Chrome focuses DevTools when it opens (DevToolsWindow::Show).
            page.focus()
        }
        self.hostView = hostView
    }
}
