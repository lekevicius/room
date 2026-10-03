import AppKit
import Design
import RoomCore
import UIKitCore

/// Drives the embryo: once RoomCore has launched, opens the Phase 1.3 window,
/// binds a RoomBrowser to it and shows the active page in the card. The
/// sidebar carries a throwaway navigation strip (address field, back,
/// forward, reload) until Chapter 3 brings `EngineRoomCore`.
final class HostController: NSObject, RoomApplicationDelegate, RoomBrowserDelegate {
    private var windowController: RoomWindowController?
    private var browser: RoomBrowser?
    // Lazy: HostController exists before RoomCore creates NSApp, and creating
    // AppKit controls would create a plain NSApplication first.
    private lazy var strip = NavigationStrip()
    private var observations: [NSKeyValueObservation] = []
    private var closingFromEngine = false
    private(set) var current: RoomWebContents?

    static let startURL = URL(string: UserDefaults.standard.string(forKey: "RoomStartURL") ?? "https://en.wikipedia.org/wiki/Web_browser")!

    // MARK: RoomApplicationDelegate

    func roomApplicationDidFinishLaunching(_ application: RoomApplication) {
        NSApp.mainMenu = HostMenu.make()
        guard let profile = application.defaultProfile else {
            NSLog("Room: RoomCore loaded no profile; nothing to show")
            return
        }
        let controller = RoomWindowController()
        controller.spaceTitle = "RoomCore"
        windowController = controller
        guard let window = controller.window else { return }

        let browser = RoomBrowser(profile: profile, window: window)
        browser.delegate = self
        self.browser = browser

        strip.install(in: controller.sidebarView.contentView)
        strip.onNavigate = { [weak self] url in
            self?.current?.loadURL(url)
            self?.current?.focus()
        }
        strip.onBack = { [weak self] in self?.current?.goBack() }
        strip.onForward = { [weak self] in self?.current?.goForward() }
        strip.onReload = { [weak self] in self?.current?.reload() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)

        controller.showWindow(nil)
        NSApp.activate()

        if let spike = HostSpike.requested {
            HostSpike.run(spike, host: self, profile: profile)
        } else {
            open(Self.startURL, in: profile, activate: true)
        }
    }

    func roomApplicationWillTerminate(_ application: RoomApplication) {
        NSLog("Room: RoomCore will terminate")
    }

    // MARK: RoomBrowserDelegate

    func browser(_ browser: RoomBrowser, didActivate webContents: RoomWebContents?) {
        show(webContents)
    }

    func browserWillClose(_ browser: RoomBrowser) {
        closingFromEngine = true
        windowController?.close()
    }

    func browserDidClose(_ browser: RoomBrowser) {
        self.browser = nil
        show(nil)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        // The user closed the window: let Chromium close the browser (its
        // tabs and session state) behind it.
        guard !closingFromEngine, let browser, !browser.isClosed else { return }
        browser.close()
    }

    // MARK: Pages

    @discardableResult
    func open(_ url: URL, in profile: RoomProfile, activate: Bool) -> RoomWebContents? {
        guard let browser else { return nil }
        let page = profile.createWebContents()
        browser.add(page, activate: activate)
        page.loadURL(url)
        return page
    }

    func newPage() {
        guard let browser else { return }
        open(Self.startURL, in: browser.profile, activate: true)
        focusAddressField()
    }

    func focusAddressField() {
        strip.focusAddress()
    }

    var pages: [RoomWebContents] { browser?.webContents ?? [] }

    func runSpikeCommand(_ command: Int) throws {
        let selector = NSSelectorFromString("roomSpikeCommand:")
        guard let browser, browser.responds(to: selector) else {
            throw HostCDP.Failure("missing test-only Chrome command hook")
        }
        let result = browser.perform(selector, with: NSNumber(value: command))?.takeUnretainedValue() as? NSNumber
        guard result?.boolValue == true else {
            throw HostCDP.Failure("Chrome command \(command) disabled or rejected")
        }
    }

    func runSpikeAction(_ action: String) throws -> Int {
        let selector = NSSelectorFromString("roomSpikeAction:")
        guard let browser, browser.responds(to: selector),
              let result = browser.perform(selector, with: action as NSString)?.takeUnretainedValue() as? NSNumber else {
            throw HostCDP.Failure("missing private fixture action hook")
        }
        return result.intValue
    }

    private func show(_ page: RoomWebContents?) {
        guard page !== current || windowController?.cardView.contentView !== page?.nativeView else { return }
        current = page
        windowController?.cardView.contentView = page?.nativeView
        windowController?.cardView.backgroundColor = Palette.cardBackground
        observations = []
        guard let page else {
            strip.update(url: nil, title: "", canGoBack: false, canGoForward: false, isLoading: false)
            return
        }
        // KVO from RoomCore arrives on the main thread.
        observations = [
            page.observe(\.url) { [weak self] page, _ in MainActor.assumeIsolated { self?.refresh(page) } },
            page.observe(\.title) { [weak self] page, _ in MainActor.assumeIsolated { self?.refresh(page) } },
            page.observe(\.isLoading) { [weak self] page, _ in MainActor.assumeIsolated { self?.refresh(page) } },
            page.observe(\.canGoBack) { [weak self] page, _ in MainActor.assumeIsolated { self?.refresh(page) } },
            page.observe(\.canGoForward) { [weak self] page, _ in MainActor.assumeIsolated { self?.refresh(page) } },
        ]
        refresh(page)
        page.focus()
    }

    private func refresh(_ page: RoomWebContents) {
        guard page === current else { return }
        strip.update(
            url: page.url, title: page.title, canGoBack: page.canGoBack,
            canGoForward: page.canGoForward, isLoading: page.isLoading)
        windowController?.spaceTitle = page.title.isEmpty ? "RoomCore" : page.title
    }
}

/// Address field and back/forward/reload, laid out under the traffic lights
/// in the sidebar (throwaway, like Phase 1.4's DebugToolbar).
final class NavigationStrip: NSObject, NSTextFieldDelegate {
    let address = NSTextField()
    private let back = NSButton()
    private let forward = NSButton()
    private let reload = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")

    var onNavigate: ((URL) -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var onReload: (() -> Void)?

    func install(in view: NSView) {
        let buttons = NSStackView(views: [back, forward, reload])
        buttons.spacing = 4
        for (button, symbol, action) in [
            (back, "chevron.left", #selector(goBack)),
            (forward, "chevron.right", #selector(goForward)),
            (reload, "arrow.clockwise", #selector(doReload)),
        ] {
            button.bezelStyle = .accessoryBarAction
            button.isBordered = false
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.target = self
            button.action = action
        }
        address.placeholderString = "Search or enter address"
        address.bezelStyle = .roundedBezel
        address.font = .systemFont(ofSize: 13)
        address.delegate = self
        address.target = self
        address.action = #selector(commit)
        address.setAccessibilityIdentifier("address-field")
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [buttons, address, titleLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 56),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            address.widthAnchor.constraint(equalTo: stack.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    func update(url: URL?, title: String, canGoBack: Bool, canGoForward: Bool, isLoading: Bool) {
        if address.currentEditor() == nil {
            address.stringValue = url?.absoluteString ?? ""
        }
        titleLabel.stringValue = isLoading ? "Loading…" : title
        back.isEnabled = canGoBack
        forward.isEnabled = canGoForward
    }

    func focusAddress() {
        address.window?.makeFirstResponder(address)
        address.currentEditor()?.selectAll(nil)
    }

    @objc private func commit() {
        let text = address.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onNavigate?(Self.url(from: text))
    }

    @objc private func goBack() { onBack?() }
    @objc private func goForward() { onForward?() }
    @objc private func doReload() { onReload?() }

    static func url(from text: String) -> URL {
        if let url = URL(string: text), url.scheme != nil { return url }
        if text.contains("."), !text.contains(" "), let url = URL(string: "https://" + text) { return url }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url!
    }
}
