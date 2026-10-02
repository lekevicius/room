import AppKit
import CEFBridge
import Engine

/// DevTools for one `CEFWebContents`.
///
/// CEF 154 cannot parent its DevTools to a view on macOS (DevTools is always
/// a Chrome-style browser, and Chrome style refuses a native parent). Docked
/// DevTools is therefore our own Alloy browser in the host view, loading the
/// bundled front-end (`devtools://devtools/bundled/devtools_app.html`)
/// connected to the page over the 127.0.0.1 remote-debugging port. Without
/// that port, `open` falls back to CEF's separate DevTools window.
final class CEFDevTools: DevTools, CEFDevToolsInspectable {
    private weak var contents: CEFWebContents?
    private var frontend: CEFWebContents?
    private weak var hostView: NSView?
    private var usesWindow = false

    init(contents: CEFWebContents) {
        self.contents = contents
    }

    var isOpen: Bool {
        frontend != nil || (usesWindow && contents?.browser?.hasDevTools == true)
    }

    /// The docked front-end's page, for tests and the spike.
    public var frontendPage: CEFWebContents? { frontend }

    func open(in hostView: NSView) {
        Task { await show(in: hostView, inspecting: nil) }
    }

    func inspectElement(at point: NSPoint, in hostView: NSView) {
        Task { await show(in: hostView, inspecting: point) }
    }

    func close() {
        frontend?.close()
        frontend = nil
        if usesWindow { contents?.browser?.closeDevTools() }
        hostView = nil
    }

    private func show(in hostView: NSView, inspecting point: NSPoint?) async {
        guard let contents, let browser = contents.browser else { return }
        let port = CEFApplication.current?.remoteDebuggingPort ?? 0
        guard port > 0 else {
            usesWindow = true
            browser.showDevToolsWindowInspectingElement(at: point ?? .zero)
            return
        }
        if frontend == nil || self.hostView !== hostView {
            frontend?.close()
            frontend = nil
            let info: [String: Any]
            do {
                info = try await contents.devToolsMethod("Target.getTargetInfo")
            } catch {
                NSLog("Room: DevTools target lookup failed: \(error)")
                return
            }
            guard let targetID = (info["targetInfo"] as? [String: Any])?["targetId"] as? String,
                  let page = try? contents.profile.makeWebContents()
            else {
                NSLog("Room: DevTools target info without an id: \(info)")
                return
            }
            page.nativeView.frame = hostView.bounds
            page.nativeView.autoresizingMask = [.width, .height]
            hostView.addSubview(page.nativeView)
            page.load(URL(string: "devtools://devtools/bundled/devtools_app.html?ws=127.0.0.1:\(port)/devtools/page/\(targetID)")!)
            frontend = page
            self.hostView = hostView
        }
        if let point { await reveal(at: point) }
    }

    /// Selects the element at `point` in the docked front-end's Elements panel.
    private func reveal(at point: NSPoint) async {
        guard let contents, let frontend else { return }
        _ = try? await contents.devToolsMethod("DOM.enable")
        guard let node = try? await contents.devToolsMethod(
            "DOM.getNodeForLocation",
            params: ["x": Int(point.x), "y": Int(point.y), "includeUserAgentShadowDOM": false]
        ), let backendID = node["backendNodeId"] as? Int else { return }
        // Wait for the front-end to load and attach, then reveal through its own modules.
        for _ in 0..<50 {
            if let result = try? await frontend.executeJavaScript(PageScripts.revealNode(backendID)), result == "true" { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }
}

extension PageScripts {
    /// Runs inside the DevTools front-end: resolves a backend node id in the
    /// primary page target and reveals it in the Elements panel.
    static func revealNode(_ backendID: Int) -> String {
        """
        (async () => {
          const SDK = await import('./core/sdk/sdk.js');
          const Common = await import('./core/common/common.js');
          const target = SDK.TargetManager.TargetManager.instance().primaryPageTarget();
          const model = target && target.model(SDK.DOMModel.DOMModel);
          if (!model) return false;
          await model.requestDocument();
          const nodes = await model.pushNodesByBackendIdsToFrontend(new Set([\(backendID)]));
          const node = nodes && nodes.get(\(backendID));
          if (!node) return false;
          await Common.Revealer.reveal(node);
          return true;
        })()
        """
    }
}

/// Debug access to the docked DevTools front-end page.
@MainActor
public protocol CEFDevToolsInspectable: AnyObject {
    var frontendPage: CEFWebContents? { get }
}
