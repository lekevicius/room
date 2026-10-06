import AppKit
import Chrome
import Design
import Engine
import Model
import Store
import Tabs

/// Reader mode (4.7b, ⌥⇧⌘R): Chrome's DOM Distiller (`Resources/Reader/
/// domdistiller.js`) runs in the page's isolated world through
/// `executeJavaScript`; an article becomes Room's reader page
/// (`Resources/Reader/reader.html` with the token CSS) written to
/// `<state>/Reader/<entry>.html` and shown in the card in place of the
/// entry's page (`TabController.openReader`), which stays loaded behind it
/// and is never navigated. A page with less than
/// `ReaderMetrics.minimumArticleCharacters` of text gets a toast instead.
/// The reader page follows the window's appearance and Settings ▸
/// Appearance ▸ Reader text size while it shows.
@MainActor
final class ReaderController {
    private weak var tabs: TabController?
    private weak var settings: SettingsStore?
    private weak var toasts: ToastCenter?
    private let folder: URL
    private var appearanceObservation: NSKeyValueObservation?
    /// Entries whose page is being distilled (a second ⌥⇧⌘R waits for the first).
    private(set) var distilling: Set<UUID> = []

    /// What the last ⌥⇧⌘R did (the `reader` spike reads it).
    enum Outcome {
        case shown(reader: any WebContents, article: ReaderArticle, distillMilliseconds: Double, loadMilliseconds: Double)
        case notArticle(ReaderArticle?, distillMilliseconds: Double)
        case failed(String)
    }

    private(set) var lastOutcome: Outcome?

    init(tabs: TabController, settings: SettingsStore, toasts: ToastCenter?, folder: URL) {
        self.tabs = tabs
        self.settings = settings
        self.toasts = toasts
        self.folder = folder
        tabs.onReaderEnded = { [weakSelf = MainActorWeak(self)] entry, file, _ in
            weakSelf.value?.ended(entry, file: file)
        }
        observeTextSize()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weakSelf = MainActorWeak(self)] _, _ in
            Task { @MainActor in weakSelf.value?.applyToReaders() }
        }
    }

    // MARK: Resources

    static let distillerSource: String? = {
        guard let url = Bundle.main.url(forResource: "domdistiller", withExtension: "js", subdirectory: "Reader") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    static let template: String? = {
        guard let url = Bundle.main.url(forResource: "reader", withExtension: "html", subdirectory: "Reader") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()

    // MARK: Toggling

    /// ⌥⇧⌘R on the card's entry: exits reader mode, or enters it.
    func toggle() {
        guard let tabs, let entry = tabs.currentEntryID else { return }
        if tabs.readerContents(for: entry) != nil {
            tabs.exitReader(entry)
            return
        }
        guard let page = tabs.contents(for: entry), !distilling.contains(entry) else { return }
        Task { await enter(page, entry: entry) }
    }

    /// Whether ⌥⇧⌘R can act now (the menu's validation).
    var canToggle: Bool {
        guard let tabs, let entry = tabs.currentEntryID else { return false }
        if tabs.readerContents(for: entry) != nil { return true }
        guard let page = tabs.contents(for: entry), let scheme = page.url?.scheme?.lowercased() else { return false }
        return ["http", "https", "file"].contains(scheme) && page.state == .alive
    }

    /// Distills `page` and shows the reader page for `entry`, or says why not.
    @discardableResult
    func enter(_ page: any WebContents, entry: UUID) async -> Outcome {
        let outcome = await distillAndShow(page, entry: entry)
        lastOutcome = outcome
        switch outcome {
        case .shown(_, let article, let distill, let load):
            NSLog("Room: reader mode on %@: \"%@\" %ld characters, %ld images, distilled in %.0f ms, page in %.0f ms",
                  page.url?.host() ?? "?", article.title, article.textLength, article.imageURLs.count, distill, load)
        case .notArticle(let article, let distill):
            NSLog("Room: reader mode: no article on %@ (%ld characters in %.0f ms)", page.url?.host() ?? "?", article?.textLength ?? 0, distill)
            toasts?.show(Toast(id: "reader", symbol: .readerMode, message: "No article found on this page"))
        case .failed(let reason):
            NSLog("Room: reader mode failed on %@: %@", page.url?.host() ?? "?", reason)
            toasts?.show(Toast(id: "reader", symbol: .info, message: "Reader mode is not available on this page"))
        }
        return outcome
    }

    private func distillAndShow(_ page: any WebContents, entry: UUID) async -> Outcome {
        guard let distiller = Self.distillerSource, let template = Self.template else { return .failed("the reader resources are missing") }
        guard let source = page.url else { return .failed("the page has no URL") }
        distilling.insert(entry)
        defer { distilling.remove(entry) }
        let start = ContinuousClock.now
        let json: String
        do {
            json = try await page.executeJavaScript(ReaderRules.distillerScript(distiller, url: source))
        } catch {
            return .failed("the distiller: \(error)")
        }
        let distillMs = Self.ms(since: start)
        let article: ReaderArticle
        do {
            article = try ReaderRules.parse(json)
        } catch ReaderError.noResult {
            return .notArticle(nil, distillMilliseconds: distillMs)
        } catch {
            return .failed("the distiller's answer: \(error)")
        }
        guard ReaderRules.isArticle(article) else { return .notArticle(article, distillMilliseconds: distillMs) }
        // The page may have moved on while the script ran.
        guard let tabs, tabs.contents(for: entry) === page, page.url == source else { return .failed("the page navigated while it was distilled") }
        let html = ReaderRules.page(template: template, article: article, source: source, style: ReaderStyle.css(),
                                    textSize: settings?.settings.readerTextSize.rawValue ?? ReaderTextSize.medium.rawValue,
                                    appearance: Self.appearanceName)
        let file = folder.appending(path: "\(entry.uuidString).html")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(html.utf8).write(to: file, options: .atomic)
        } catch {
            return .failed("the reader page could not be written: \(error.localizedDescription)")
        }
        let loadStart = ContinuousClock.now
        guard let reader = tabs.openReader(file, for: entry) else { return .failed("no reader page") }
        // Loaded when the engine says so (bounded): the reader page's own load time.
        for _ in 0..<300 {
            try? await Task.sleep(for: .milliseconds(10))
            if reader.url != nil, !reader.isLoading { break }
        }
        let loadMs = Self.ms(since: loadStart)
        forgetHistory(of: file, entry: entry)
        return .shown(reader: reader, article: article, distillMilliseconds: distillMs, loadMilliseconds: loadMs)
    }

    // MARK: Settings and appearance

    /// "light" or "dark": the window's appearance as the page should draw it.
    static var appearanceName: String { NSApp.effectiveAppearance.isDark ? "dark" : "light" }

    private func observeTextSize() {
        guard let settings else { return }
        _ = withObservationTracking {
            settings.settings.readerTextSize
        } onChange: { [weakSelf = MainActorWeak(self)] in
            Task { @MainActor in
                weakSelf.value?.applyToReaders()
                weakSelf.value?.observeTextSize()
            }
        }
    }

    /// Writes the appearance and the text size into every reader page's root element.
    func applyToReaders() {
        guard let tabs else { return }
        let size = settings?.settings.readerTextSize.rawValue ?? ReaderTextSize.medium.rawValue
        let script = "(() => { const r = document.documentElement; r.dataset.appearance = '\(Self.appearanceName)'; r.dataset.size = '\(size)'; return r.dataset.size; })()"
        for entry in tabs.readerEntryIDs {
            guard let reader = tabs.readerContents(for: entry) else { continue }
            Task { _ = try? await reader.executeJavaScript(script) }
        }
    }

    // MARK: Ending

    private func ended(_ entry: UUID, file: URL) {
        try? FileManager.default.removeItem(at: file)
        forgetHistory(of: file, entry: entry)
    }

    /// The reader page's `file://` URL is no visit of the user's: its history row goes.
    private func forgetHistory(of file: URL, entry: UUID) {
        guard let tabs, let page = tabs.contents(for: entry), let profile = tabs.engineProfile(for: page) else { return }
        profile.history?.delete(url: file)
    }

    static func ms(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
}

extension AppDelegate {
    /// View ▸ Reader Mode (⌥⇧⌘R): the card's page in reader mode, or back.
    @objc func readerMode(_ sender: Any?) {
        reader?.toggle()
    }

    func installReader(tabs: TabController, settings: SettingsStore, toasts: ToastCenter?) {
        reader = ReaderController(tabs: tabs, settings: settings, toasts: toasts,
                                  folder: Self.stateDirectory.appending(path: "Reader", directoryHint: .isDirectory))
        // The keyboard goes to the page now in the card (Esc and the arrows work at once).
        tabs.onReaderToggled = { [weakSelf = MainActorWeak(self)] _, _ in weakSelf.value?.pageHost?.focusPage() }
        // Reader files of a session that ended without Exit (a quit, a crash).
        try? FileManager.default.removeItem(at: Self.stateDirectory.appending(path: "Reader", directoryHint: .isDirectory))
    }
}
