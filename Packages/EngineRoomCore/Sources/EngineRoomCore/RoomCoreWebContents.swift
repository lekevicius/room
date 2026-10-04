import AppKit
import Engine
import Observation
import RoomCore

/// `WebContents` over a `RoomWebContents` (Chromium `content::WebContents`):
/// load, history, reload/stop, title, URL, loading, the native view, close,
/// and (3.2a) the pages it opens, the hovered link and element fullscreen.
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

    public func executeJavaScript(_ script: String) async throws -> String {
        throw EngineError.notSupported("RoomCoreWebContents.executeJavaScript")
    }

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
