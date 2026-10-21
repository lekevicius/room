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
    /// Set by `simulateBlockedRequests`; 0 again at the next navigation.
    public internal(set) var blockedRequestCount = 0
    public private(set) var state = WebContentsState.alive
    public private(set) var findResult: FindResult?
    /// Set by `simulateCrash`; cleared by the next reload or navigation.
    public private(set) var isCrashed = false
    public private(set) var printCount = 0
    /// Element fullscreen, entered by `simulateFullscreenRequest(enter:)`.
    public internal(set) var isFullscreen = false
    /// Set by `simulateCapture`; `stopCapturing` clears the kinds it names.
    public internal(set) var captureState = CaptureState()
    /// Set by `simulateMediaSession`; the media controls change its state.
    public internal(set) var mediaSession: MediaSessionInfo?
    /// The media controls the host called, in order.
    public internal(set) var mediaControls: [FakeMediaControl] = []
    /// The pages `savePage(as:to:)` wrote, in order.
    public internal(set) var savedPages: [FakeSavedPage] = []
    /// The DevTools protocol methods the host sent, in order.
    public internal(set) var devToolsCommands: [String] = []
    /// Answers `sendDevToolsCommand`; without one the fake throws
    /// `EngineError.notSupported` (an engine that cannot attach).
    @ObservationIgnored public var devToolsCommandHandler: ((String, [String: Any]) throws -> [String: Any])?
    /// Ended by `simulateUnresponsive` answered `.terminate`.
    public internal(set) var terminatedUnresponsiveCount = 0
    /// URLs the UI delegate allowed to open in another application.
    public internal(set) var openedExternalURLs: [URL] = []

    /// Committed history and the index of the current entry.
    public private(set) var backForwardList: [URL] = []
    public private(set) var currentIndex = -1

    private var muted: Bool
    private var zoom = 1.0
    private var lastFind: (text: String, matchCase: Bool)?

    @ObservationIgnored weak var profile: FakeProfile?
    /// The password offer the delegate presents, until answered or withdrawn (5.8a).
    @ObservationIgnored var pendingPasswordOffer: ((FakeWebContents.PasswordSubmitOutcome) -> Void)?
    @ObservationIgnored private var pageView: FakePageView?
    @ObservationIgnored private lazy var fakeDevTools = FakeDevTools(contents: self)

    /// What `discardBlockers` reports (a test sets it: a dirty form, Picture-in-Picture…).
    @ObservationIgnored public var simulatedDiscardBlockers: DiscardBlockers = []
    /// `true` when the page started from `restoredNavigationState`.
    public private(set) var wasRestored = false
    /// The restored current entry waits for the first `reload()` (as Chromium's
    /// `NavigationController::Restore` then `LoadIfNecessary`).
    private var needsRestoreLoad = false

    /// The window the page is in (`configuration.hostWindow`, then each
    /// `move(toHostWindow:)`); pages it opens open there.
    @ObservationIgnored public private(set) weak var hostWindow: NSWindow?
    /// How many times `move(toHostWindow:)` moved the page.
    public private(set) var moveCount = 0

    init(profile: FakeProfile, configuration: WebContentsConfiguration) {
        self.profile = profile
        self.configuration = configuration
        hostWindow = configuration.hostWindow
        self.muted = configuration.initiallyMuted
        if configuration.transparentBackground { rootBackgroundColor = nil }
        if let data = configuration.restoredNavigationState, let saved = try? JSONDecoder().decode(SavedHistory.self, from: data),
           saved.index >= 0, saved.index < saved.urls.count {
            backForwardList = saved.urls
            currentIndex = saved.index
            url = saved.urls[saved.index]
            title = saved.titles.indices.contains(saved.index) ? saved.titles[saved.index] : nil
            wasRestored = true
            needsRestoreLoad = true
        }
    }

    /// FakeEngine's navigation state: the committed URLs, their titles and the
    /// current index, as JSON (opaque to the host, like the engines' own).
    struct SavedHistory: Codable {
        var urls: [URL]
        var titles: [String?]
        var index: Int
    }

    /// The titles each committed entry showed last, by index.
    private var entryTitles: [Int: String] = [:]

    public var navigationState: Data? {
        guard currentIndex >= 0, !backForwardList.isEmpty else { return nil }
        var titles = backForwardList.indices.map { entryTitles[$0] }
        if let title { titles[currentIndex] = title }
        return try? JSONEncoder().encode(SavedHistory(urls: backForwardList, titles: titles, index: currentIndex))
    }

    public var discardBlockers: DiscardBlockers { state == .alive ? simulatedDiscardBlockers : [] }

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

    /// Every `load(_:transition:fromAddressBar:)` asked of the page, in order
    /// (the transition is what the engine's history records the visit as).
    public private(set) var loads: [(url: URL, transition: PageTransition)] = []

    public func load(_ url: URL, transition: PageTransition, fromAddressBar: Bool) {
        loads.append((url, transition))
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
        if currentIndex >= 0, let title { entryTitles[currentIndex] = title }
        needsRestoreLoad = false
        backForwardList.removeSubrange((currentIndex + 1)...)
        entryTitles = entryTitles.filter { $0.key <= currentIndex }
        backForwardList.append(url)
        currentIndex = backForwardList.count - 1
        startLoading(url, transition: transition)
        navigationDelegate?.webContentsDidChangeNavigationState(self)
    }

    private func traverse(to index: Int) {
        let action = NavigationAction(url: backForwardList[index], kind: .backForward, transition: .other)
        guard navigationDelegate?.webContents(self, decidePolicyFor: action) != .ignore else { return }
        if currentIndex >= 0, let title { entryTitles[currentIndex] = title }
        needsRestoreLoad = false
        currentIndex = index
        startLoading(backForwardList[index], transition: .other)
        navigationDelegate?.webContentsDidChangeNavigationState(self)
    }

    private func reload(ignoringCache: Bool) {
        guard state != .closed, let url else { return }
        if needsRestoreLoad {
            // The restored entry loads now (Chromium: `LoadIfNecessary`).
            needsRestoreLoad = false
            startLoading(url, transition: .reload)
            return
        }
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
        blockedRequestCount = 0
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
        // As RoomCore: a page opens in its opener's window.
        // Off the record: the page belongs to the profile's twin (RoomCore's
        // navigator hook); the host moves it into its incognito window.
        let target = disposition == .offTheRecord && !profile.isOffTheRecord ? profile.makeOffTheRecord() : profile
        let contents = target.makeWebContents(WebContentsConfiguration(initiallyHidden: disposition == .newBackgroundTab,
                                                                       hostWindow: hostWindow))
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

    // MARK: Windows (4.8b)

    /// RoomCore's move between two windows' Browsers: the same page, its
    /// history and state kept; only the window changes.
    public func move(toHostWindow window: NSWindow) throws {
        guard state != .closed else { throw EngineError.closed }
        guard hostWindow !== window else { return }
        hostWindow = window
        moveCount += 1
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

    public func exitFullscreen() {
        guard isFullscreen else { return }
        isFullscreen = false
        effectiveUIDelegate.webContentsDidRequestExitFullscreen(self)
    }

    public func print() {
        printCount += 1
    }

    public func stopCapturing(_ kinds: CaptureKinds) {
        var state = captureState
        if kinds.contains(.userMedia) { state.subtract([.camera, .microphone]) }
        if kinds.contains(.displayMedia) { state.subtract([.display, .tab, .window]) }
        simulateCapture(state)
    }

    // MARK: Media session controls

    /// Play, as a page whose handler resumes its player: the session plays
    /// and the page is audible. Nothing without a session.
    public func mediaPlay() {
        mediaControls.append(.play)
        guard var session = mediaSession else { return }
        session.playbackState = .playing
        if var position = session.position { position.rate = 1; session.position = position }
        mediaSession = session
        simulateAudio(true)
    }

    /// Pause: the session is paused and the page silent.
    public func mediaPause() {
        mediaControls.append(.pause)
        guard var session = mediaSession else { return }
        session.playbackState = .paused
        if var position = session.position { position.rate = 0; session.position = position }
        mediaSession = session
        simulateAudio(false)
    }

    /// Recorded; the page's handler (if any) is the test's: `simulateMediaSession`.
    public func mediaNextTrack() { mediaControls.append(.nextTrack) }
    public func mediaPreviousTrack() { mediaControls.append(.previousTrack) }

    /// Recorded; a reported position moves there.
    public func mediaSeek(to seconds: TimeInterval) {
        mediaControls.append(.seek(seconds))
        guard var session = mediaSession, var position = session.position else { return }
        position.position = min(max(0, seconds), position.duration)
        session.position = position
        mediaSession = session
    }

    // MARK: Documents

    /// Writes a small stub of the page in `format`: an HTML document naming
    /// the URL and title, the "_files" directory for `.completeHTML`, or an
    /// MHTML header. Throws when the page is closed or has no document.
    public func savePage(as format: SavePageFormat, to url: URL) async throws {
        guard state != .closed else { throw EngineError.closed }
        guard let pageURL = self.url else { throw EngineError.failed("the page has no document to save") }
        let title = self.title ?? ""
        let text: String
        switch format {
        case .html, .completeHTML:
            text = "<!DOCTYPE html><html><head><title>\(title)</title></head><body>\(pageURL.absoluteString)</body></html>\n"
        case .mhtml:
            text = "From: <Saved by FakeEngine>\r\nSnapshot-Content-Location: \(pageURL.absoluteString)\r\nSubject: \(title)\r\nMIME-Version: 1.0\r\nContent-Type: text/html\r\n\r\n<html><body>\(pageURL.absoluteString)</body></html>\r\n"
        }
        if let directory = format.resourcesDirectory(for: url) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(text.utf8).write(to: url)
        savedPages.append(FakeSavedPage(format: format, url: url))
    }

    public func sendDevToolsCommand(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        guard state != .closed else { throw EngineError.closed }
        devToolsCommands.append(method)
        guard let devToolsCommandHandler else { throw EngineError.notSupported("sendDevToolsCommand(\(method))") }
        return try devToolsCommandHandler(method, params)
    }

    // MARK: Simulated page state (more in FakeWebContents+Simulation.swift)

    /// Room's blocker stops `count` more of the page's requests.
    public func simulateBlockedRequests(_ count: Int = 1) {
        guard state == .alive, count > 0 else { return }
        blockedRequestCount += count
    }

    /// Room's blocker handled the page's cookie banner.
    public func simulateCookieBanner(_ consentPlatform: String, optedOut: Bool = true) {
        guard state == .alive else { return }
        uiDelegate?.webContents(self, didHandleCookieBanner: consentPlatform, optedOut: optedOut)
    }

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
        navigationDelegate?.webContentsDidChangeNavigationState(self)
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

/// A page `FakeWebContents.savePage(as:to:)` wrote.
public struct FakeSavedPage: Hashable, Sendable {
    public var format: SavePageFormat
    public var url: URL
}

/// A media session control `FakeWebContents` recorded.
public enum FakeMediaControl: Hashable, Sendable {
    case play, pause, nextTrack, previousTrack
    case seek(TimeInterval)
}
