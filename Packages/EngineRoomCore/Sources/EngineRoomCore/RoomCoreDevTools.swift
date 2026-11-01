import AppKit
import Engine
import RoomCore

/// DevTools for one `RoomCoreWebContents`: Chrome's `DevToolsWindow` with its
/// bindings and lifetime, its front-end page shown in the view the host gives.
///
/// Since 5.10 the inspected page's `Browser` has a `DevtoolsUIController`
/// (RoomBrowser), so Chrome docks DevTools on its remembered dock side and the
/// front-end shows its own Dock side menu and close button; the host lays the
/// page out over the front-end where Chrome's resizing strategy says
/// (`pageFrame(inContainerOf:)`), told of every change through `onChange`.
/// Undocked, the front-end lives in a headless DevTools `Browser` (3.2a) and
/// the host shows it in a window of its own. No remote-debugging port.
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

    public var onChange: (() -> Void)?

    public var isDocked: Bool {
        guard isOpen, let contents else { return false }
        return contents.page.isDevToolsDocked
    }

    public func pageFrame(inContainerOf size: CGSize) -> CGRect {
        guard isOpen, let contents else { return CGRect(origin: .zero, size: size) }
        return contents.page.devToolsPageFrame(inContainerOf: size)
    }

    /// `webContentsDevToolsDidChange` (patches/0028): the front-end may have moved or closed.
    func engineDidChange() {
        if let frontend, frontend.state == .closed || contents?.page.isDevToolsOpen != true {
            frontend.nativeView.removeFromSuperview()
            self.frontend = nil
            hostView = nil
        }
        onChange?()
    }

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

    /// Closes DevTools: docked, the front-end's page closes (as its own close button);
    /// undocked, Chrome's DevTools Browser (the front-end goes with it).
    public func close() {
        contents?.page.closeDevTools()
        frontend?.nativeView.removeFromSuperview()
        frontend = nil
        hostView = nil
    }

    private func show(_ tool: RoomDevToolsTool, in hostView: NSView) {
        guard let contents, contents.state != .closed else { return }
        // Open DevTools moved to another host (docked ↔ its window) is only re-hosted: showing it
        // again would re-dock it on Chrome's side and take the focus.
        if tool != .default || !isOpen { contents.page.showDevTools(tool) }
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
