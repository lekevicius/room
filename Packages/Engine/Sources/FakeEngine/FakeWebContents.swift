import AppKit
import Engine
import Observation

/// A page that never touches the network: navigation history, loading state
/// and delegate traffic behave like an engine's, and the view is a text view
/// listing the URL and title.
@Observable
public final class FakeWebContents: WebContents {
    @ObservationIgnored public weak var uiDelegate: (any WebContentsUIDelegate)?
    @ObservationIgnored public weak var navigationDelegate: (any NavigationDelegate)?

    public let configuration: WebContentsConfiguration

    /// When `true` (default) navigations finish immediately; otherwise they
    /// stay loading until `finishLoading()`.
    @ObservationIgnored public var loadsSynchronously = true
    /// Makes `close()`, `reload()` and termination ask the UI delegate first.
    @ObservationIgnored public var hasBeforeUnloadHandler = false
    /// Answers `executeJavaScript` for scripts other than the built-ins
    /// (`document.title`, `location.href`).
    @ObservationIgnored public var javaScriptHandler: ((String) throws -> String)?

    public private(set) var title: String?
    public private(set) var url: URL?
    public private(set) var favicon: NSImage?
    public private(set) var isLoading = false
    public private(set) var loadProgress = 1.0
    public private(set) var themeColor: NSColor?
    public private(set) var rootBackgroundColor: NSColor? = .white
    public private(set) var securityState = SecurityState.none
    public private(set) var isAudible = false
    public private(set) var state = WebContentsState.alive
    public private(set) var findResult: FindResult?
    /// Set by `simulateCrash`; cleared by the next reload or navigation.
    public private(set) var isCrashed = false
    public private(set) var printCount = 0

    /// Committed history and the index of the current entry.
    public private(set) var backForwardList: [URL] = []
    public private(set) var currentIndex = -1

    private var muted: Bool
    private var zoom = 1.0
    private var lastFind: (text: String, matchCase: Bool)?

    @ObservationIgnored private weak var profile: FakeProfile?
    @ObservationIgnored private var pageView: FakePageView?
    @ObservationIgnored private lazy var fakeDevTools = FakeDevTools(contents: self)

    init(profile: FakeProfile, configuration: WebContentsConfiguration) {
        self.profile = profile
        self.configuration = configuration
        self.muted = configuration.initiallyMuted
        if configuration.transparentBackground { rootBackgroundColor = nil }
    }

    public var nativeView: NSView {
        if let pageView { return pageView }
        let view = FakePageView()
        pageView = view
        updatePageView()
        return view
    }

    // MARK: Navigation

    public var canGoBack: Bool { currentIndex > 0 }
    public var canGoForward: Bool { currentIndex < backForwardList.count - 1 }

    public func load(_ url: URL, transition: PageTransition, fromAddressBar: Bool) {
        let action = NavigationAction(
            url: url,
            kind: transition == .formSubmit ? .formSubmitted : .other,
            transition: transition,
            isUserGesture: fromAddressBar
        )
        navigate(action)
    }

    public func goBack() {
        guard canGoBack else { return }
        traverse(to: currentIndex - 1)
    }

    public func goForward() {
        guard canGoForward else { return }
        traverse(to: currentIndex + 1)
    }

    public func reload() {
        reload(ignoringCache: false)
    }

    public func reloadIgnoringCache() {
        reload(ignoringCache: true)
    }

    public func stop() {
        guard isLoading else { return }
        isLoading = false
        loadProgress = 1
        updatePageView()
    }

    /// Completes the pending navigation when `loadsSynchronously` is `false`.
    public func finishLoading() {
        guard isLoading, let url else { return }
        title = url.host() ?? url.absoluteString
        favicon = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        isLoading = false
        loadProgress = 1
        updatePageView()
    }

    func navigate(_ action: NavigationAction) {
        guard state != .closed else { return }
        let disposition = navigationDelegate?.webContents(self, decidePolicyFor: action) ?? action.disposition
        switch disposition {
        case .ignore:
            return
        case .currentTab:
            commit(action.url, transition: action.transition)
        case .saveToDisk:
            profile?.simulateDownload(url: action.url)
        case .newForegroundTab, .newBackgroundTab, .newWindow, .newPopup, .newPictureInPicture, .offTheRecord:
            openNewContents(action.url, disposition: disposition)
        }
    }

    private func commit(_ url: URL, transition: PageTransition) {
        backForwardList.removeSubrange((currentIndex + 1)...)
        backForwardList.append(url)
        currentIndex = backForwardList.count - 1
        startLoading(url, transition: transition)
    }

    private func traverse(to index: Int) {
        let action = NavigationAction(url: backForwardList[index], kind: .backForward, transition: .other)
        guard navigationDelegate?.webContents(self, decidePolicyFor: action) != .ignore else { return }
        currentIndex = index
        startLoading(backForwardList[index], transition: .other)
    }

    private func reload(ignoringCache: Bool) {
        guard state != .closed, let url else { return }
        confirmUnload(isReload: true) { [weak self] proceed in
            guard proceed, let self else { return }
            let action = NavigationAction(url: url, kind: .reload, transition: .reload)
            guard self.navigationDelegate?.webContents(self, decidePolicyFor: action) != .ignore else { return }
            self.startLoading(url, transition: .reload)
        }
    }

    /// The navigation commits at once (FakeEngine has no network phase).
    private func startLoading(_ url: URL, transition: PageTransition) {
        state = .alive
        isCrashed = false
        findResult = nil
        lastFind = nil
        self.url = url
        title = nil
        favicon = nil
        isLoading = true
        loadProgress = 0.1
        updateSecurityState(for: url)
        updatePageView()
        navigationDelegate?.webContents(self, didCommitNavigation: url, transition: transition)
        if loadsSynchronously { finishLoading() }
    }

    private func openNewContents(_ url: URL, disposition: Disposition) {
        guard let profile else { return }
        let contents = profile.makeWebContents(WebContentsConfiguration(initiallyHidden: disposition == .newBackgroundTab))
        contents.loadsSynchronously = loadsSynchronously
        contents.load(url, transition: .link, fromAddressBar: false)
        if let uiDelegate {
            uiDelegate.webContents(self, didCreate: contents, targetURL: url, disposition: disposition)
        } else {
            contents.close()
        }
    }

    private func updateSecurityState(for url: URL) {
        let level: SecurityState.Level = switch url.scheme {
        case "https", "wss": .secure
        case "http", "ws": .insecure
        default: .none
        }
        let newState = SecurityState(level: level)
        guard newState != securityState else { return }
        securityState = newState
        uiDelegate?.webContents(self, didChangeSecurityState: newState)
    }

    // MARK: Page state

    public var isMuted: Bool {
        get { muted }
        set {
            guard newValue != muted else { return }
            muted = newValue
            uiDelegate?.webContents(self, didChangeMuted: newValue)
        }
    }

    public var zoomFactor: Double {
        get { zoom }
        set { zoom = min(max(newValue, 0.25), 5) }
    }

    // MARK: Find

    public func find(_ text: String, forward: Bool, matchCase: Bool) {
        guard !text.isEmpty else { return stopFind(clearSelection: true) }
        let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
        let count = pageText.ranges(of: text, options: options)
        guard count > 0 else {
            findResult = FindResult(matchCount: 0, activeMatch: 0, isFinal: true)
            lastFind = (text, matchCase)
            return
        }
        var active = 1
        if let lastFind, lastFind.text == text, lastFind.matchCase == matchCase, let previous = findResult, previous.matchCount == count {
            active = forward
                ? previous.activeMatch % count + 1
                : (previous.activeMatch + count - 2) % count + 1
        } else if !forward {
            active = count
        }
        lastFind = (text, matchCase)
        findResult = FindResult(matchCount: count, activeMatch: active, isFinal: true)
    }

    public func stopFind(clearSelection: Bool) {
        findResult = nil
        lastFind = nil
    }

    /// What find-in-page searches: the lines the page view shows.
    public var pageText: String {
        [url?.absoluteString, title].compactMap { $0 }.joined(separator: "\n")
    }

    // MARK: Lifecycle

    public func discard() throws {
        guard state != .closed else { throw EngineError.closed }
        guard state != .discarded else { return }
        state = .discarded
        isLoading = false
        loadProgress = 1
        isAudible = false
        updatePageView()
    }

    public func close() {
        guard state != .closed else { return }
        confirmUnload(isReload: false) { [weak self] proceed in
            if proceed { self?.closeNow() }
        }
    }

    /// Runs the page's beforeunload handler, if it has one, through the UI delegate.
    func confirmUnload(isReload: Bool, _ completion: @escaping (Bool) -> Void) {
        guard hasBeforeUnloadHandler, state == .alive else { return completion(true) }
        effectiveUIDelegate.webContents(self, runBeforeUnloadDialogForReload: isReload, completion: completion)
    }

    func closeNow() {
        guard state != .closed else { return }
        fakeDevTools.close()
        state = .closed
        isLoading = false
        isAudible = false
        pageView?.removeFromSuperview()
        profile?.didClose(self)
        uiDelegate?.webContentsDidClose(self)
    }

    // MARK: Tools

    public func captureViewport() async throws -> NSImage {
        guard state != .closed else { throw EngineError.closed }
        let view = nativeView
        guard !view.bounds.isEmpty, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw EngineError.failed("the page view has no size")
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    public var devTools: (any DevTools)? { fakeDevTools }

    public func executeJavaScript(_ script: String) async throws -> String {
        guard state == .alive else { throw state == .closed ? EngineError.closed : EngineError.notRunning }
        switch script.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ";"))) {
        case "document.title":
            return try Self.json(title ?? "")
        case "location.href", "window.location.href", "document.URL":
            return try Self.json(url?.absoluteString ?? "about:blank")
        default:
            guard let javaScriptHandler else {
                throw EngineError.javaScriptException("FakeEngine cannot evaluate: \(script)")
            }
            return try javaScriptHandler(script)
        }
    }

    public func print() {
        printCount += 1
    }

    // MARK: Simulated page state (more in FakeWebContents+Simulation.swift)

    /// Media starts or stops playing.
    public func simulateAudio(_ audible: Bool) {
        guard state == .alive, audible != isAudible else { return }
        isAudible = audible
        uiDelegate?.webContents(self, didChangeAudible: audible)
    }

    /// The renderer process dies; the page stays blank until reloaded.
    public func simulateCrash(_ status: TerminationStatus = .crashed) {
        guard state == .alive else { return }
        isCrashed = true
        isLoading = false
        loadProgress = 1
        isAudible = false
        updatePageView()
        uiDelegate?.webContents(self, processGone: status)
    }

    /// The page sets `document.title`.
    public func simulateTitle(_ title: String?) {
        self.title = title
        updatePageView()
    }

    /// The page reports a favicon (FakeEngine's own is a template globe).
    public func simulateFavicon(_ image: NSImage?) {
        favicon = image
    }

    /// The page's `theme-color` meta tag and root background.
    public func simulateColors(theme: NSColor?, rootBackground: NSColor?) {
        themeColor = theme
        rootBackgroundColor = rootBackground
    }

    private static func json(_ string: String) throws -> String {
        String(decoding: try JSONEncoder().encode(string), as: UTF8.self)
    }

    // MARK: View

    private func updatePageView() {
        pageView?.show(lines: [
            url?.absoluteString ?? "about:blank",
            title ?? "",
            statusLine,
        ])
    }

    private var statusLine: String {
        if isCrashed { return "Renderer gone" }
        return switch state {
        case .alive: isLoading ? "Loading…" : ""
        case .discarded: "Discarded"
        case .frozen: "Frozen"
        case .closed: "Closed"
        }
    }

    /// The UI delegate, or one with the engine's default behavior.
    var effectiveUIDelegate: any WebContentsUIDelegate {
        uiDelegate ?? DefaultUIDelegate.shared
    }
}

/// Answers every UI request with the protocol's default behavior.
private final class DefaultUIDelegate: WebContentsUIDelegate {
    static let shared = DefaultUIDelegate()
}

private extension String {
    func ranges(of needle: String, options: CompareOptions) -> Int {
        var count = 0
        var searchRange = startIndex..<endIndex
        while let found = range(of: needle, options: options, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<endIndex
        }
        return count
    }
}
