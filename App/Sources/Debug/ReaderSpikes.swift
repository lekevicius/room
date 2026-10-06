#if DEBUG
import AppKit
import Chrome
import Engine
import Model
import Sidebar
import Tabs
import UIKitCore

/// Phase 4.7b spike `reader` (`Room -RoomSpike reader`; the tour's step
/// `reader` through `scripts/reader-check.sh`, which serves
/// `research/spikes` on :8777). Fixtures under `phase-4.7/`: `article1.html`
/// (a long article with headings, `swatch.png` and `field.png`, a sidebar of
/// links), `article2.html` (short, a `<figure>`), `notarticle.html` (a
/// dashboard of short widgets), `articlecsp.html` (article1 under a strict
/// `script-src`). Sections (`-RoomSpikeOnly` picks): `article` (article1:
/// ⌥⇧⌘R, the reader page's DOM, the three text sizes, light and dark with
/// captures, Esc back to the page with its scroll and history), `article2`
/// (the same once, the menu action to exit), `notarticle` (the toast, no
/// reader page), `csp`, `translate` (no Translate item anywhere, no offer),
/// `print` (⌘P's preview, the key window, Return → the PDF save panel, Esc),
/// `pagesetup` (File ▸ Page Setup…'s sheet).
extension SpikeRunner.Context {
    func readerChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        await activate()
        SpikeRunner.record("reader_resources", "distiller=\(ReaderController.distillerSource?.utf8.count ?? -1) B template=\(ReaderController.template?.utf8.count ?? -1) B")
        if runs("article") { await readerArticle1() }
        if runs("article2") { await readerArticle2() }
        if runs("notarticle") { await readerNotArticle() }
        if runs("csp") { await readerCSP() }
        if runs("translate") { await readerTranslate() }
        if runs("print") { await readerPrint() }
        if runs("pagesetup") { await readerPageSetup() }
    }

    // MARK: Helpers

    var readerController: ReaderController? { AppDelegate.current?.reader }

    /// Writes a capture for the reviewer (`research/screenshots/phase-4.7b/` is filled from the tour's capture directory).
    func keepReaderCapture(_ image: NSImage, _ name: String) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory"),
              let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "phase-4.7b-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
    }

    static let readerDOMProbe = """
    JSON.stringify({ title: (document.querySelector('#room-reader-title') || {}).textContent, \
    host: (document.querySelector('#room-reader-host') || {}).textContent, \
    exit: !!document.querySelector('#room-reader-exit'), \
    original: (document.querySelector('#room-reader-original') || {}).href, \
    headings: document.querySelectorAll('main h1, main h2, main h3').length, \
    paragraphs: document.querySelectorAll('main p').length, \
    figures: document.querySelectorAll('main figure').length, \
    asideLinks: [...document.querySelectorAll('main a')].filter(a => /Most read|Harbour board|Waterproof/.test(a.textContent)).length, \
    scripts: document.scripts.length, url: location.protocol })
    """

    static let readerImagesProbe = """
    JSON.stringify([...document.images].map(i => [i.complete && i.naturalWidth > 0, i.naturalWidth, i.naturalHeight, i.getAttribute('src')]))
    """

    static let readerStyleProbe = """
    JSON.stringify((() => { const p = document.querySelector('main p'); const r = document.documentElement; \
    return { size: r.dataset.size, appearance: r.dataset.appearance, font: p ? getComputedStyle(p).fontSize : null, \
    background: getComputedStyle(r).backgroundColor, color: getComputedStyle(r).color, \
    variable: getComputedStyle(r).getPropertyValue('--room-background').trim() }; })())
    """

    /// ⌥⇧⌘R through the application (the page sees it first, then the menu).
    func pressReaderKey() {
        PageDriver.key(window, characters: "‰", charactersIgnoringModifiers: "R", keyCode: 15, modifiers: [.command, .shift, .option])
    }

    func escapeKey() {
        PageDriver.key(window, characters: "\u{1b}", keyCode: 53)
    }

    /// Opens `start`, then navigates the same tab to `article` (so the entry has history), and scrolls it.
    func openArticle(_ name: String, after start: String? = "page.html") async -> (page: any WebContents, entry: UUID)? {
        guard let page = await open(Self.documentsPage(start ?? name)), let entry = tabs.entryID(for: page) else { return nil }
        if start != nil {
            page.load(Self.documentsPage(name))
            _ = await waitUntil(10) { page.url?.lastPathComponent == name }
            await waitLoaded(page)
        }
        return (page, entry)
    }

    // MARK: article: article1, ⌥⇧⌘R, sizes, appearances, Esc

    func readerArticle1() async {
        guard let app = AppDelegate.current, let reader = readerController,
              let (page, entry) = await openArticle("article1.html") else { return SpikeRunner.record("error", "reader: article1 did not open") }
        try? await Task.sleep(for: .milliseconds(500))
        _ = await js(page, "(() => { window.scrollTo(0, 420); return window.scrollY; })()")
        try? await Task.sleep(for: .milliseconds(300))
        let scrollBefore = await js(page, "window.scrollY")
        let canGoBackBefore = page.canGoBack
        let urlBefore = page.url
        SpikeRunner.record("reader_menu_item", readerMenuItemLine(app))
        // The key, as typed: the page first, then the menu's Reader Mode.
        let start = ContinuousClock.now
        pressReaderKey()
        let shown = await waitUntil(20) { self.tabs.readerContents(for: entry) != nil && reader.distilling.isEmpty }
        let keyMs = ms(since: start)
        guard shown, let readerPage = tabs.readerContents(for: entry), case .shown(_, let article, let distill, let load)? = reader.lastOutcome else {
            return SpikeRunner.record("reader_shown", "no reader page in 20 s (outcome \(String(describing: reader.lastOutcome)))")
        }
        await waitLoaded(readerPage)
        SpikeRunner.record("reader_shown", String(format: "by ⌥⇧⌘R in %.0f ms: distilled in %.0f ms (distiller's own %.1f ms), page loaded in %.0f ms; "
                                                  + "title=\"%@\" characters=%ld words=%ld images=%ld card_shows_reader=%@ focused=%@ entry_page_url=%@ row_glyph=%@",
                                                  keyMs, distill, article.distillerMilliseconds ?? -1, load, article.title, article.textLength, article.wordCount ?? -1,
                                                  article.imageURLs.count, "\(app.pageHost?.contents === readerPage)", "\(tabs.focusedPage === readerPage)",
                                                  page.url == urlBefore ? "unchanged" : (page.url?.absoluteString ?? "nil"),
                                                  "\(tabs.pageState(for: entry).isReader)"))
        SpikeRunner.record("reader_row", readerRowLine(entry))
        SpikeRunner.record("reader_url", "reader=\(readerPage.url?.scheme ?? "nil"):…/\(readerPage.url?.lastPathComponent ?? "nil") canGoBack=\(readerPage.canGoBack)")
        SpikeRunner.record("reader_dom", await js(readerPage, Self.readerDOMProbe))
        _ = await waitUntilAsync(8) { await self.js(readerPage, "[...document.images].every(i => i.complete)") == "true" }
        SpikeRunner.record("reader_images", await js(readerPage, Self.readerImagesProbe))
        // The three sizes from Settings ▸ Appearance ▸ Reader text size.
        let settings = sidebar.store.settings
        let sizeWas = settings.settings.readerTextSize
        var sizes: [String] = []
        for size in ReaderTextSize.allCases {
            settings.update { $0.readerTextSize = size }
            _ = await waitUntilAsync(3) { await self.js(readerPage, "document.documentElement.dataset.size") == "\"\(size.rawValue)\"" }
            sizes.append("\(size.rawValue)=\(await js(readerPage, "getComputedStyle(document.querySelector('main p')).fontSize"))")
        }
        settings.update { $0.readerTextSize = sizeWas }
        SpikeRunner.record("reader_sizes", sizes.joined(separator: " "))
        // Light and dark: the window's appearance reaches the page's data-appearance and its background.
        let appearanceWas = NSApp.appearance
        for name in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
            _ = await waitUntilAsync(3) { await self.js(readerPage, "document.documentElement.dataset.appearance") == "\"\(name)\"" }
            try? await Task.sleep(for: .milliseconds(400))
            SpikeRunner.record("reader_\(name)", await js(readerPage, Self.readerStyleProbe))
            if let image = await PageDriver.capture(readerPage, "reader: \(name)") {
                keepReaderCapture(image, "article1-\(name)")
                SpikeRunner.record("reader_\(name)_capture", "\(Int(image.size.width))x\(Int(image.size.height)) pt " + inkShare(image))
            }
        }
        NSApp.appearance = appearanceWas
        try? await Task.sleep(for: .milliseconds(300))
        // Back acts on the reader page (no history): the article's page does not move.
        app.goBack(nil)
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("reader_back_ignored", "entry_page_url=\(page.url == urlBefore ? "unchanged" : (page.url?.absoluteString ?? "nil")) still_reader=\(tabs.readerContents(for: entry) != nil)")
        // Esc, as typed into the reader page: back to the article.
        let escStart = ContinuousClock.now
        escapeKey()
        let exited = await waitUntil(5) { self.tabs.readerContents(for: entry) == nil }
        let exitMs = ms(since: escStart)
        try? await Task.sleep(for: .milliseconds(400))
        let scrollAfter = await js(page, "window.scrollY")
        SpikeRunner.record("reader_exit", String(format: "by Esc %@ in %.0f ms: card_shows_page=%@ url=%@ scroll %@→%@ canGoBack %@→%@ row_glyph=%@ reader_closed=%@ file_removed=%@",
                                                 exited ? "exited" : "did not exit", exitMs, "\(app.pageHost?.contents === page)",
                                                 page.url == urlBefore ? "unchanged" : (page.url?.absoluteString ?? "nil"), scrollBefore, scrollAfter,
                                                 "\(canGoBackBefore)", "\(page.canGoBack)", "\(tabs.pageState(for: entry).isReader)", "\(readerPage.state == .closed)",
                                                 "\(!FileManager.default.fileExists(atPath: AppDelegate.stateDirectory.appending(path: "Reader/\(entry.uuidString).html").path))"))
        // The reader file's visit is not in history.
        if let history = tabs.engineProfile(for: page)?.history {
            let hits = await history.search("Lighthouse Keepers", limit: 20)
            SpikeRunner.record("reader_history", "urls=[\(hits.map { $0.url.scheme == "file" ? "file:…/\($0.url.lastPathComponent)" : $0.url.lastPathComponent }.joined(separator: ", "))]")
        }
        // Back now moves the article's page.
        app.goBack(nil)
        _ = await waitUntil(5) { page.url?.lastPathComponent == "page.html" }
        SpikeRunner.record("reader_back_after_exit", "url=\(page.url?.lastPathComponent ?? "nil")")
    }

    func readerMenuItemLine(_ app: AppDelegate) -> String {
        guard let item = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu?.items.first(where: { $0.action == #selector(AppDelegate.readerMode(_:)) })
        else { return "no View ▸ Reader Mode item" }
        let enabled = AppDelegate.validators[#selector(AppDelegate.readerMode(_:))]?(app, item) ?? false
        return "title=\"\(item.title)\" key=\(item.keyEquivalentModifierMask.contains(.option) ? "⌥" : "")\(item.keyEquivalentModifierMask.contains(.command) ? "⌘" : "")\(item.keyEquivalent) enabled=\(enabled) tooltip=\(item.toolTip ?? "none")"
    }

    /// The sidebar row's reader glyph as drawn (the cell's image view by its identifier).
    func readerRowLine(_ entry: UUID) -> String {
        guard let row = sidebar.debugRowView(for: entry) else { return "row not found" }
        var queue: [NSView] = [row]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.accessibilityIdentifier() == "row-reader" {
                return "glyph shown=\(!view.isHidden) frame=\(NSStringFromRect(view.frame))"
            }
            queue += view.subviews
        }
        return "no glyph view"
    }

    // MARK: article2: the same once; the menu's item exits

    func readerArticle2() async {
        guard let app = AppDelegate.current, let reader = readerController,
              let (page, entry) = await openArticle("article2.html", after: nil) else { return SpikeRunner.record("error", "reader: article2 did not open") }
        try? await Task.sleep(for: .milliseconds(500))
        let canGoBackBefore = page.canGoBack
        let outcome = await reader.enter(page, entry: entry)
        guard case .shown(let readerPage, let article, let distill, let load) = outcome else {
            return SpikeRunner.record("reader2_shown", "not shown: \(outcome)")
        }
        await waitLoaded(readerPage)
        _ = await waitUntilAsync(8) { await self.js(readerPage, "[...document.images].every(i => i.complete)") == "true" }
        SpikeRunner.record("reader2_shown", String(format: "distilled in %.0f ms, page loaded in %.0f ms; title=\"%@\" characters=%ld images=%ld card_shows_reader=%@",
                                                   distill, load, article.title, article.textLength, article.imageURLs.count, "\(app.pageHost?.contents === readerPage)"))
        SpikeRunner.record("reader2_dom", await js(readerPage, Self.readerDOMProbe))
        SpikeRunner.record("reader2_images", await js(readerPage, Self.readerImagesProbe))
        SpikeRunner.record("reader2_style", await js(readerPage, Self.readerStyleProbe))
        if let image = await PageDriver.capture(readerPage, "reader: article2") { keepReaderCapture(image, "article2-\(Self.appearanceTag)") }
        // View ▸ Exit Reader Mode (the same action as ⌥⇧⌘R).
        app.readerMode(nil)
        let exited = await waitUntil(5) { self.tabs.readerContents(for: entry) == nil }
        SpikeRunner.record("reader2_exit", "by the menu action \(exited ? "exited" : "did not exit"): card_shows_page=\(app.pageHost?.contents === page) canGoBack \(canGoBackBefore)→\(page.canGoBack)")
        // A link in the reader page leaves reader mode and loads in the entry's page.
        guard case .shown(let again, _, _, _) = await reader.enter(page, entry: entry) else { return SpikeRunner.record("reader2_link", "not shown again") }
        await waitLoaded(again)
        let href = await js(again, "(() => { const a = document.querySelector('#room-reader-content a'); return a ? a.href : null; })()")
        // The link sits below the fold at the medium size: into view first, as a reader would scroll.
        // The link sits below the fold and wraps: into view, then a click on its first line's box.
        let box = await js(again, "(() => { const a = document.querySelector('#room-reader-content a'); a.scrollIntoView({ block: 'center' }); "
                           + "const r = a.getClientRects()[0]; return [r.x + Math.min(r.width / 2, 20), r.y + r.height / 2]; })()")
        try? await Task.sleep(for: .milliseconds(300))
        let xy = (try? JSONSerialization.jsonObject(with: Data(box.utf8))) as? [Double] ?? []
        let linkStart = ContinuousClock.now
        if xy.count == 2 { PageDriver.click(again, at: CGPoint(x: xy[0], y: xy[1]), "reader: the article's link") }
        let left = await waitUntil(5) { self.tabs.readerContents(for: entry) == nil }
        _ = await waitUntil(5) { page.url?.lastPathComponent == "article1.html" && page.canGoBack }
        SpikeRunner.record("reader2_link", String(format: "a link %@ in %.0f ms: entry_page_url=%@ card_shows_page=%@ canGoBack=%@ href=%@ reader_url=%@",
                                                  left ? "exits reader mode" : "kept reader mode", ms(since: linkStart), page.url?.lastPathComponent ?? "nil",
                                                  "\(app.pageHost?.contents === page)", "\(page.canGoBack)", href, again.url?.absoluteString ?? "nil"))
        if tabs.readerContents(for: entry) != nil { tabs.exitReader(entry) }
    }

    static var appearanceTag: String { NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light" }

    // MARK: notarticle: the toast, no reader page

    func readerNotArticle() async {
        guard let app = AppDelegate.current, let reader = readerController,
              let (page, entry) = await openArticle("notarticle.html", after: nil) else { return SpikeRunner.record("error", "reader: notarticle did not open") }
        try? await Task.sleep(for: .milliseconds(500))
        let start = ContinuousClock.now
        app.readerMode(nil)
        _ = await waitUntil(15) { reader.distilling.isEmpty && app.toastCenter?.currentToast?.id == "reader" }
        var detail = "no outcome"
        if case .notArticle(let article, let distill)? = reader.lastOutcome {
            detail = String(format: "not an article: %ld characters (threshold %ld) in %.0f ms", article?.textLength ?? 0, 400, distill)
        } else if let outcome = reader.lastOutcome {
            detail = "\(outcome)"
        }
        SpikeRunner.record("reader_notarticle", String(format: "%@ after %.0f ms; toast=\"%@\" reader_page=%@ card_shows_page=%@", detail, ms(since: start),
                                                       app.toastCenter?.currentToast?.message ?? "none", "\(tabs.readerContents(for: entry) != nil)",
                                                       "\(app.pageHost?.contents === page)"))
    }

    // MARK: csp: article1 under script-src 'self'

    func readerCSP() async {
        guard let reader = readerController, let (page, entry) = await openArticle("articlecsp.html", after: nil) else { return SpikeRunner.record("error", "reader: articlecsp did not open") }
        try? await Task.sleep(for: .milliseconds(500))
        let outcome = await reader.enter(page, entry: entry)
        switch outcome {
        case .shown(_, let article, let distill, _): SpikeRunner.record("reader_csp", String(format: "shown: %ld characters in %.0f ms", article.textLength, distill))
        case .notArticle(let article, _): SpikeRunner.record("reader_csp", "not an article (\(article?.textLength ?? 0) characters)")
        case .failed(let reason): SpikeRunner.record("reader_csp", "failed: \(reason)")
        }
        if tabs.readerContents(for: entry) != nil { tabs.exitReader(entry) }
    }

    // MARK: translate: absent without a key (B-63)

    func readerTranslate() async {
        guard let app = AppDelegate.current else { return }
        let url = URL(string: "\(Self.documentsBase)/phase-2.6/translate.html")!
        guard let page = await open(url) else { return SpikeRunner.record("error", "reader: translate.html did not open") }
        try? await Task.sleep(for: .seconds(3))
        var menuTitles: [String] = []
        func scan(_ menu: NSMenu, _ path: String) {
            for item in menu.items {
                if item.title.localizedCaseInsensitiveContains("translat") { menuTitles.append(path + item.title) }
                if let submenu = item.submenu { scan(submenu, path + item.title + " ▸ ") }
            }
        }
        if let main = NSApp.mainMenu { scan(main, "") }
        let chrome = session.pageDelegate.chrome
        let presentMenu = chrome.presentMenu
        defer { chrome.presentMenu = presentMenu }
        let driver = MenuDriver()
        chrome.presentMenu = { menu, point, view in driver.show(menu, at: point, in: view) }
        var items = ""
        var translateItems: [String] = []
        driver.onOpen = { menu in
            items = menu.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | ")
            translateItems = menu.menu.items.filter { $0.tag == 50161 || $0.title.localizedCaseInsensitiveContains("translat") }.map(\.title)
            driver.finish()
        }
        let size = page.nativeView.bounds.size
        Task { PageDriver.click(page, at: CGPoint(x: size.width - 120, y: size.height - 120), button: .rightMouseDown, "reader: right-click the German page") }
        _ = await waitUntil(8) { driver.closed }
        SpikeRunner.record("translate_absent", "lang=\(await js(page, "document.documentElement.lang")) main_menu_items=\(menuTitles) context_menu_translate=\(translateItems) "
                           + "offer_toast=\(app.toastCenter?.currentToast.map { "\"\($0.message)\"" } ?? "none") context_menu_opened=\(!items.isEmpty)")
        SpikeRunner.record("translate_context_menu_items", items)
    }

    // MARK: print: ⌘P's preview, the keyboard, Print to PDF's panel

    func readerPrint() async {
        guard let app = AppDelegate.current, let page = await open(Self.documentsPage("article2.html")) else { return SpikeRunner.record("error", "reader: no page to print") }
        try? await Task.sleep(for: .milliseconds(800))
        let windowsBefore = Set(NSApp.windows.map { ObjectIdentifier($0) })
        let start = ContinuousClock.now
        app.printPage(nil)
        var preview: NSWindow?
        _ = await waitUntil(15) {
            preview = NSApp.windows.first { !windowsBefore.contains(ObjectIdentifier($0)) && $0.isVisible && $0.frame.width > 200 }
            return preview != nil
        }
        guard let preview else { return SpikeRunner.record("print_preview", "no preview window in 15 s") }
        let shownMs = ms(since: start)
        // The preview's content loads (it is a chrome://print page); give it time to lay out its first page.
        try? await Task.sleep(for: .milliseconds(2500))
        let key = NSApp.keyWindow
        SpikeRunner.record("print_preview", String(format: "%@ after %.0f ms frame %@ over the window %@ (child of Room's window: %@)", "\(Swift.type(of: preview))", shownMs,
                                                   NSStringFromRect(preview.frame), NSStringFromRect(window.frame), "\(preview.parent.map { $0 === window || $0.parent === window } ?? false)"))
        SpikeRunner.record("print_keyboard", "key_window=\(key.map { "\(Swift.type(of: $0))" } ?? "none") key_is_preview=\(key === preview) "
                           + "first_responder=\(preview.firstResponder.map { "\(Swift.type(of: $0))" } ?? "none") page_keeps_keys=\(window.isKeyWindow)")
        // The keyboard path: Return in the preview presses its default button (Save, for Save as PDF):
        // Chrome then asks where to save the PDF (a save panel, out of process on macOS 26: cancelled here).
        let returnStart = ContinuousClock.now
        PageDriver.key(preview, characters: "\r", keyCode: 36)
        var panel: NSSavePanel?
        _ = await waitUntil(10) {
            panel = NSApp.windows.compactMap { $0 as? NSSavePanel }.first(where: \.isVisible)
                ?? NSApp.windows.compactMap { $0.attachedSheet as? NSSavePanel }.first
            return panel != nil
        }
        if let panel {
            SpikeRunner.record("print_to_pdf", String(format: "Return → Chrome's save panel after %.0f ms, proposed \"%@\"; cancelled (the landing is by hand)",
                                                      ms(since: returnStart), panel.nameFieldStringValue))
            if let parent = panel.sheetParent { parent.endSheet(panel, returnCode: .cancel) } else { panel.cancel(nil) }
            _ = await waitUntil(5) { !panel.isVisible }
        } else {
            SpikeRunner.record("print_to_pdf", "Return: no save panel in 10 s (preview visible=\(preview.isVisible); windows: \(NSApp.windows.filter(\.isVisible).map { "\(Swift.type(of: $0))" }))")
        }
        try? await Task.sleep(for: .milliseconds(1500))
        if preview.isVisible {
            // The keyboard back in the preview after the panel (as a person's next key would be).
            SpikeRunner.record("print_after_panel", "key_window=\(NSApp.keyWindow.map { "\(Swift.type(of: $0))" } ?? "none") key_is_preview=\(NSApp.keyWindow === preview)")
            preview.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(300))
            PageDriver.key(preview, characters: "\u{1b}", keyCode: 53)
            let gone = await waitUntil(5) { !preview.isVisible || !NSApp.windows.contains(preview) }
            SpikeRunner.record("print_closed", gone ? "closed by Esc" : "still open")
        } else {
            SpikeRunner.record("print_closed", "closed after the save panel")
        }
        _ = page
    }

    // MARK: pagesetup: File ▸ Page Setup…

    func readerPageSetup() async {
        guard let app = AppDelegate.current else { return }
        let item = NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu?.items.first { $0.action == #selector(AppDelegate.showPageSetup(_:)) }
        let before = NSPrintInfo.shared.orientation
        app.showPageSetup(nil)
        let sheet = await waitUntil(5) { self.window.attachedSheet != nil }
        SpikeRunner.record("page_setup", "item=\"\(item?.title ?? "missing")\" key=\"\(item?.keyEquivalent ?? "")\" sheet=\(sheet ? "\(Swift.type(of: window.attachedSheet!))" : "none") "
                           + "orientation=\(before == .landscape ? "landscape" : "portrait") paper=\(NSPrintInfo.shared.paperName?.rawValue ?? "?")")
        if let attached = window.attachedSheet {
            window.endSheet(attached, returnCode: .cancel)
            _ = await waitUntil(3) { self.window.attachedSheet == nil }
        }
    }
}
#endif
