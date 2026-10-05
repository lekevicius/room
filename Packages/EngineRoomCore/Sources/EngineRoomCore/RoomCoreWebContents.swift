import AppKit
import Engine
import Observation
import RoomCore

/// `WebContents` over a `RoomWebContents` (Chromium `content::WebContents`):
/// load, history, reload/stop, title, URL, loading, the native view, close,
/// (3.2a) the pages it opens, the hovered link and element fullscreen, and
/// (3.2b) reserved, unhandled and consumed keys and isolated-world scripts.
/// A page created for a host window is in that window's Chrome tab strip
/// (`RoomBrowser`); the members that need Chrome's tab helpers wired to Room
/// are `notSupported` or inert until their phase (docs/engine-api.md).
///
/// `nativeView` is a view this object owns, with Chromium's
/// `WebContentsViewCocoa` inside, so it stays valid after `close()`.
@Observable
public final class RoomCoreWebContents: NSObject, WebContents, RoomWebContentsDelegate {
    @ObservationIgnored public weak var uiDelegate: (any WebContentsUIDelegate)?
    @ObservationIgnored public weak var navigationDelegate: (any NavigationDelegate)?

    public let configuration: WebContentsConfiguration

    public private(set) var title: String?
    public private(set) var url: URL?
    public private(set) var favicon: NSImage?
    public private(set) var isLoading = false
    public private(set) var loadProgress = 1.0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public private(set) var themeColor: NSColor?
    public private(set) var rootBackgroundColor: NSColor?
    public private(set) var securityState = SecurityState.none
    public private(set) var isAudible = false
    public private(set) var state = WebContentsState.alive
    public private(set) var findResult: FindResult?
    /// Stored only: RoomCore has no audio or zoom members yet (3.3a).
    public var isMuted: Bool
    public var zoomFactor = 1.0

    /// What the page asked for when it opened this one: the window.open
    /// rect or the picture-in-picture size (top-left screen coordinates);
    /// `nil` for a page the host created or one opened without features.
    /// Engine-specific until the host has a popup window (Chapter 4).
    public private(set) var requestedBounds: CGRect?

    public var nativeView: NSView { pageView }
    public var devTools: (any DevTools)? { nil }

    @ObservationIgnored let page: RoomWebContents
    @ObservationIgnored private weak var profile: RoomCoreProfile?
    @ObservationIgnored private let pageView = RoomCorePageView()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var scriptSerial = 0

    init(page: RoomWebContents, configuration: WebContentsConfiguration, profile: RoomCoreProfile?) {
        self.page = page
        self.configuration = configuration
        self.profile = profile
        isMuted = configuration.initiallyMuted
        super.init()
        page.delegate = self
        if let view = page.nativeView { pageView.host(view) }
        let weakSelf = WeakContents(self)
        observations = [
            page.observe(\.url) { _, _ in weakSelf.refresh() },
            page.observe(\.title) { _, _ in weakSelf.refresh() },
            page.observe(\.isLoading) { _, _ in weakSelf.refresh() },
            page.observe(\.canGoBack) { _, _ in weakSelf.refresh() },
            page.observe(\.canGoForward) { _, _ in weakSelf.refresh() },
            page.observe(\.isClosed) { _, _ in weakSelf.refresh() },
        ]
        refresh()
    }

    /// Copies RoomCore's KVO state (main thread) into the observable properties.
    fileprivate func refresh() {
        if page.isClosed {
            guard state != .closed else { return }
            observations = []
            isLoading = false
            loadProgress = 1
            canGoBack = false
            canGoForward = false
            state = .closed
            uiDelegate?.webContentsDidClose(self)
            return
        }
        if url != page.url { url = page.url }
        let newTitle = page.title.isEmpty ? nil : page.title
        if title != newTitle { title = newTitle }
        if isLoading != page.isLoading {
            isLoading = page.isLoading
            // No progress events at this depth: a start and an end.
            loadProgress = isLoading ? 0.1 : 1
        }
        if canGoBack != page.canGoBack { canGoBack = page.canGoBack }
        if canGoForward != page.canGoForward { canGoForward = page.canGoForward }
    }

    // MARK: Navigation

    /// RoomCore loads every URL as typed from the address bar (the
    /// transition argument arrives with 3.3a).
    public func load(_ url: URL, transition: PageTransition, fromAddressBar: Bool) {
        page.loadURL(url)
    }

    public func goBack() { page.goBack() }
    public func goForward() { page.goForward() }
    public func reload() { page.reload() }
    /// A plain reload until 3.3a adds `ReloadType::BYPASSING_CACHE`.
    public func reloadIgnoringCache() { page.reload() }
    public func stop() { page.stop() }

    // MARK: Find (3.3b: FindTabHelper)

    public func find(_ text: String, forward: Bool, matchCase: Bool) {}
    public func stopFind(clearSelection: Bool) {}

    // MARK: Lifecycle

    public func discard() throws {
        throw EngineError.notSupported("RoomCoreWebContents.discard")
    }

    /// Closes the page at once (RoomCore runs no beforeunload handlers yet);
    /// `webContentsDidClose` follows from the `closed` change.
    public func close() {
        guard state != .closed else { return }
        page.close()
    }

    // MARK: Tools (3.3b)

    public func captureViewport() async throws -> NSImage {
        throw EngineError.notSupported("RoomCoreWebContents.captureViewport")
    }

    /// Runs `script` in RoomCore's isolated world of the main frame (the
    /// page's DOM, not its globals) and returns the completion value as JSON
    /// text, like the CEF engine's `Runtime.evaluate` (strings quoted,
    /// `undefined` as `null`). Chromium's isolated-world call does not wait
    /// for promises, so the script runs through `eval` in a wrapper that
    /// parks a promise's outcome in the isolated world, where it is polled.
    public func executeJavaScript(_ script: String) async throws -> String {
        guard state != .closed else { throw EngineError.closed }
        scriptSerial += 1
        let id = scriptSerial
        let source = String(decoding: try JSONSerialization.data(withJSONObject: script, options: .fragmentsAllowed), as: UTF8.self)
        var outcome = try await evaluate(Self.wrapper(source: source, id: id))
        if case .pending = outcome {
            let poll = "(() => { const r = window.__roomScriptResults; if (!r || !(\(id) in r)) return null; const x = r[\(id)]; delete r[\(id)]; return x; })()"
            let deadline = ContinuousClock.now + .seconds(120)
            repeat {
                guard ContinuousClock.now < deadline, state != .closed else {
                    throw EngineError.failed("executeJavaScript: the promise did not settle")
                }
                try await Task.sleep(for: .milliseconds(4))
                outcome = try await evaluate(poll)
            } while outcome == .notSettled
        }
        switch outcome {
        case .value(let json): return json
        case .exception(let message): throw EngineError.javaScriptException(message)
        case .pending, .notSettled: return "null"
        }
    }

    /// Evaluates the script as global code (its completion value, like the
    /// DevTools protocol's `Runtime.evaluate`), catching what it throws.
    private static func wrapper(source: String, id: Int) -> String {
        """
        (() => { let v; try { v = (0, eval)(\(source)); } catch (e) { return { e: String(e && e.message || e) }; }
        if (v && typeof v.then === 'function') { const r = (window.__roomScriptResults = window.__roomScriptResults || {});
        v.then(x => { r[\(id)] = { v: x }; }, e => { r[\(id)] = { e: String(e && e.message || e) }; }); return { p: \(id) }; }
        return { v: v }; })()
        """
    }

    /// What one isolated-world evaluation of the wrapper or the poll returned.
    private enum ScriptOutcome: Sendable, Equatable {
        /// `{v}`: the value as JSON text (`null` for undefined).
        case value(String)
        /// `{e}`: the script threw, or its promise rejected.
        case exception(String)
        /// `{p}`: a promise; its outcome is polled.
        case pending
        /// The poll found no outcome yet.
        case notSettled

        init(_ result: Any?) {
            guard let object = result as? [String: Any] else {
                self = .notSettled
                return
            }
            if let message = object["e"] as? String {
                self = .exception(message)
            } else if object["p"] != nil {
                self = .pending
            } else if let value = object["v"], !(value is NSNull),
                      let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]) {
                self = .value(String(decoding: data, as: UTF8.self))
            } else {
                self = .value("null")
            }
        }
    }

    /// One isolated-world evaluation. A page showing a JavaScript dialog
    /// (Chrome's own until 3.4b routes `alert` to the host's sheet) runs no
    /// script until it closes, so an answer that has not come in 30 s is an
    /// error, not a wait without end (found by the 3.2b tour's popups step).
    private func evaluate(_ script: String) async throws -> ScriptOutcome {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            page.evaluateJavaScript(script) { result, error in
                if let error {
                    once.resume(throwing: EngineError.failed(error.localizedDescription))
                } else {
                    once.resume(returning: ScriptOutcome(result))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.scriptTimeout) {
                once.resume(throwing: EngineError.failed("executeJavaScript: no answer in \(Int(Self.scriptTimeout)) s (a JavaScript dialog may be open)"))
            }
        }
    }

    private static let scriptTimeout: TimeInterval = 30

    public func print() {}

    /// Leaves element fullscreen; `webContentsDidRequestExitFullscreen`
    /// follows from Chrome's FullscreenController.
    public func exitFullscreen() { page.exitFullscreen() }

    // MARK: RoomWebContentsDelegate

    /// A page this one opened, already in this page's `Browser` (never a
    /// window of its own): the host places it, or closes it.
    public func webContents(_ webContents: RoomWebContents, didCreate newContents: RoomWebContents, targetURL: URL?,
                            disposition: RoomWindowOpenDisposition, requestedBounds: NSRect, userGesture: Bool) {
        let mapped = Disposition(disposition)
        let configuration = WebContentsConfiguration(initiallyHidden: mapped == .newBackgroundTab,
                                                     hostWindow: self.configuration.hostWindow)
        guard let profile else {
            newContents.close()
            return
        }
        let contents = profile.adoptOpened(newContents, configuration: configuration)
        if requestedBounds.width > 0 || requestedBounds.height > 0 { contents.requestedBounds = requestedBounds }
        guard let uiDelegate else {
            contents.close()
            return
        }
        uiDelegate.webContents(self, didCreate: contents, targetURL: targetURL, disposition: mapped)
    }

    public func webContents(_ webContents: RoomWebContents, didChangeStatusText text: String?) {
        uiDelegate?.webContents(self, didChangeStatusText: text)
    }

    public func webContentsDidRequestEnterFullscreen(_ webContents: RoomWebContents, origin: URL?) {
        uiDelegate?.webContentsDidRequestEnterFullscreen(self, origin: origin)
    }

    public func webContentsDidRequestExitFullscreen(_ webContents: RoomWebContents) {
        uiDelegate?.webContentsDidRequestExitFullscreen(self)
    }

    /// A key-down before the page sees it: a reserved one goes to the main
    /// menu here, once (as the CEF engine does), and never to the page.
    public func webContents(_ webContents: RoomWebContents, isReservedKeyEvent event: NSEvent) -> Bool {
        guard uiDelegate?.webContents(self, isReservedKeyEvent: event) == true else { return false }
        _ = NSApp.mainMenu?.performKeyEquivalent(with: event)
        return true
    }

    /// A key-down the page did not consume: the delegate offers it to the
    /// main menu (RoomCore does nothing else with it).
    public func webContents(_ webContents: RoomWebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        if let uiDelegate { return uiDelegate.webContents(self, handleUnhandledKeyEvent: event) }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    public func webContents(_ webContents: RoomWebContents, didConsumeKeyCode keyCode: UInt16,
                            modifierFlags: NSEvent.ModifierFlags, phase: RoomKeyEventPhase) {
        let mapped: KeyEventInfo.Phase = switch phase {
        case .keyUp: .keyUp
        case .character: .character
        default: .keyDown
        }
        uiDelegate?.webContents(self, didConsumeKey: KeyEventInfo(keyCode: keyCode, modifiers: modifierFlags, phase: mapped))
    }
}

extension Disposition {
    /// RoomCore's dispositions in the `Engine` protocol's terms: a singleton
    /// or switch-to-tab that Chromium had to open, and a split's new pane,
    /// arrive as foreground tabs (the host has no such placement yet).
    init(_ disposition: RoomWindowOpenDisposition) {
        switch disposition {
        case .newBackgroundTab: self = .newBackgroundTab
        case .newPopup: self = .newPopup
        case .newWindow: self = .newWindow
        case .newPictureInPicture: self = .newPictureInPicture
        case .offTheRecord: self = .offTheRecord
        case .newForegroundTab, .singletonTab, .switchToTab, .newSplitView: self = .newForegroundTab
        @unknown default: self = .newForegroundTab
        }
    }
}

/// Resumes a continuation once: the first of the script's answer and its
/// timeout wins (both arrive on the main thread).
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, any Error>?

    init(_ continuation: CheckedContinuation<T, any Error>) { self.continuation = continuation }

    func resume(returning value: T) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume(throwing error: any Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// Hands the contents through KVO's change handler and dereferences it on
/// the main thread, where RoomCore posts every change.
private struct WeakContents: @unchecked Sendable {
    weak var contents: RoomCoreWebContents?

    init(_ contents: RoomCoreWebContents) { self.contents = contents }

    nonisolated func refresh() {
        MainActor.assumeIsolated { contents?.refresh() }
    }
}

/// The page's view: Chromium's `WebContentsViewCocoa` filling it.
final class RoomCorePageView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityIdentifier("web-contents")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func host(_ view: NSView) {
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }
}
