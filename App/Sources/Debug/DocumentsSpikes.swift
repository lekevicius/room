#if DEBUG
import AppKit
import Engine
import Model
import Sidebar
import Tabs
import Chrome
import UIKitCore

/// Phase 4.7a spike `documents` (`Room -RoomSpike documents`; the tour's step
/// `documents` through `scripts/documents-check.sh`, which serves
/// `research/spikes` on :8777). Fixtures under `phase-4.7/`: `page.html`
/// with `swatch.png` (an orange image with a blue band, never white),
/// `tall.html` (4,000 px of coloured bands), `sample.pdf` (three pages,
/// "zebracorn" three times). Sections (`-RoomSpikeOnly` picks): `engine`
/// the `savePage` and `sendDevToolsCommand` members (the files, the MHTML
/// reopened with its image, a full-page capture with DevTools closed and
/// open); `pdf` Chrome's viewer (its DOM, find, zoom, print, save);
/// `viewsource` View Source from the menu and the context menu; `savepage`
/// File ▸ Save Page…'s path through the host; `screenshot` ⇧⌘2's overlay,
/// Copy, Save, Open as tab and the full page.
extension SpikeRunner.Context {
    static var documentsBase: String { UserDefaults.standard.string(forKey: "RoomDocumentsFixtureBase") ?? "http://127.0.0.1:8777" }
    static func documentsPage(_ name: String) -> URL { URL(string: "\(documentsBase)/phase-4.7/\(name)")! }

    /// Where the spike writes its files (`-RoomDocumentsWorkDirectory`, else a temporary directory).
    static var documentsWork: URL {
        let directory = UserDefaults.standard.string(forKey: "RoomDocumentsWorkDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "room-documents-\(getpid())", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func documentsChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        await activate()
        SpikeRunner.record("documents_work", Self.documentsWork.path)
        if runs("engine") { await documentsEngine() }
        if runs("pdf") { await documentsPDF() }
        if runs("viewsource") { await documentsViewSource() }
        if runs("savepage") { await documentsSavePagePanel() }
        if runs("screenshot") { await documentsScreenshot() }
        // The setting's two launches (`documents-check.sh --pdf-setting`): the first stores
        // PDFs ▸ Download, the second (its features at launch) opens the PDF.
        if only.contains("pdfsetting") { documentsPDFSetting() }
        if only.contains("pdfdownload") { await documentsPDFDownload() }
    }

    // MARK: Helpers

    func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? -1
    }

    /// Writes `data` beside the tour's captures when it has a directory (evidence for the reviewer).
    func keepCapture(_ data: Data, _ name: String) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "phase-4.7-\(name)")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// The RGB at a point of `image` given in points from its top-left corner, or nil.
    func pixel(_ image: NSImage, at point: CGPoint) -> (Int, Int, Int)? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        let scale = image.size.width > 0 ? CGFloat(rep.pixelsWide) / image.size.width : 1
        let x = Int(point.x * scale), y = Int(point.y * scale)
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
        return (Int(colour.redComponent * 255), Int(colour.greenComponent * 255), Int(colour.blueComponent * 255))
    }

    /// The element's rect in page CSS pixels, or nil.
    func rect(of selector: String, in page: any WebContents) async -> CGRect? {
        let json = await js(page, "(() => { const e = document.querySelector('\(selector)'); if (!e) return null; const r = e.getBoundingClientRect(); return [r.x, r.y, r.width, r.height] })()")
        guard let values = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Double], values.count == 4 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    func fullPageCapture(_ page: any WebContents) async throws -> (png: Data, contentSize: CGSize) {
        let (png, clip) = try await FullPageCapture.png(of: page)
        return (png, clip)
    }

    func pngPixels(_ data: Data) -> String {
        guard let rep = NSBitmapImageRep(data: data) else { return "unreadable" }
        return "\(rep.pixelsWide)x\(rep.pixelsHigh)"
    }

    // MARK: pdf: Chrome's viewer on a Room page

    var documentsDownloads: URL {
        let folder = Self.documentsWork.appending(path: "downloads", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func downloadRows() -> String {
        guard let list = AppDelegate.current?.downloads?.list else { return "no list" }
        return "[" + list.rows.map { "\($0.item.destination?.lastPathComponent ?? "?") \($0.item.state)" }.joined(separator: ", ") + "]"
    }

    func folderListing(_ folder: URL) -> String {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        return "[" + names.map { "\($0) \(fileSize(folder.appending(path: $0)))" }.joined(separator: ", ") + "]"
    }

    /// Share of pixels that are not near-white, and the image's size.
    func inkShare(_ image: NSImage) -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "no image" }
        let rep = NSBitmapImageRep(cgImage: cg)
        var ink = 0, total = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
                guard let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                total += 1
                if colour.redComponent < 0.9 || colour.greenComponent < 0.9 || colour.blueComponent < 0.9 { ink += 1 }
            }
        }
        return String(format: "%dx%d px, %.1f %% not white", rep.pixelsWide, rep.pixelsHigh, total > 0 ? Double(ink) * 100 / Double(total) : 0)
    }

    static let pdfDOMProbe = """
    JSON.stringify((() => { const e = document.querySelector('embed'); return { type: document.contentType, \
    embed: e ? { type: e.getAttribute('type'), w: e.clientWidth, h: e.clientHeight, internal: e.getAttribute('internalid') !== null } : null, \
    children: document.body ? document.body.children.length : -1 }; })())
    """

    func documentsPDF() async {
        let folder = documentsDownloads
        let downloadDirectoryWas = sidebar.store.settings.settings.downloadDirectory
        defer { sidebar.store.settings.update { $0.downloadDirectory = downloadDirectoryWas } }
        sidebar.store.settings.update { $0.downloadDirectory = folder.path }
        let start = ContinuousClock.now
        guard let page = await open(Self.documentsPage("sample.pdf")) else {
            return SpikeRunner.record("error", "documents: sample.pdf did not open")
        }
        let loadedMs = ms(since: start)
        try? await Task.sleep(for: .milliseconds(1500))
        SpikeRunner.record("pdf_opened", String(format: "loaded in %.0f ms url=%@ title=%@ dom=%@ features=%@", loadedMs, page.url?.lastPathComponent ?? "nil",
                                                page.title ?? "nil", await js(page, Self.pdfDOMProbe), (AppDelegate.current?.engine.features.enabled.sorted() ?? []).joined(separator: ",")))
        if let capture = await PageDriver.capture(page, "documents: the PDF") {
            SpikeRunner.record("pdf_rendered", inkShare(capture))
            if let png = pngData(capture) { keepCapture(png, "pdf-viewport.png") }
        }
        // Find: the host's find (⌘F) through the engine's FindTabHelper.
        let findStart = ContinuousClock.now
        page.find("zebracorn", forward: true, matchCase: false)
        _ = await waitUntil(5) { page.findResult?.isFinal == true }
        let first = page.findResult
        page.find("zebracorn", forward: true, matchCase: false)
        _ = await waitUntil(3) { page.findResult?.activeMatch == 2 }
        SpikeRunner.record("pdf_find", String(format: "matches=%d active=%d final=%@ in %.0f ms; next → active=%d", first?.matchCount ?? -1, first?.activeMatch ?? -1,
                                              "\(first?.isFinal ?? false)", ms(since: findStart), page.findResult?.activeMatch ?? -1))
        page.stopFind(clearSelection: true)
        // Zoom: the page's zoom (⌘=) and what the viewer drew.
        let before = await PageDriver.capture(page, "documents: PDF before zoom").flatMap(pngData)
        page.zoomFactor = 1.5
        try? await Task.sleep(for: .milliseconds(1000))
        let after = await PageDriver.capture(page, "documents: PDF after zoom")
        SpikeRunner.record("pdf_zoom", "zoomFactor=\(page.zoomFactor) drawing_changed=\(after.flatMap(pngData) != before)")
        if let after, let png = pngData(after) { keepCapture(png, "pdf-zoomed.png") }
        page.zoomFactor = 1
        try? await Task.sleep(for: .milliseconds(800))
        // Print: Chrome's preview (Views) over the window, closed with Esc.
        await documentsPrintPreview(page)
        // Save from the viewer's toolbar: its download button (top right of the viewer).
        await documentsPDFToolbarSave(page, folder: folder)
    }

    func documentsPrintPreview(_ page: any WebContents) async {
        let windowsBefore = Set(NSApp.windows.map { ObjectIdentifier($0) })
        let start = ContinuousClock.now
        page.print()
        var preview: NSWindow?
        _ = await waitUntil(15) {
            preview = NSApp.windows.first { !windowsBefore.contains(ObjectIdentifier($0)) && $0.isVisible && $0.frame.width > 200 }
            return preview != nil
        }
        guard let preview else { return SpikeRunner.record("pdf_print", "no preview window in 15 s") }
        let shown = ms(since: start)
        try? await Task.sleep(for: .milliseconds(1500))
        SpikeRunner.record("pdf_print", String(format: "%@ after %.0f ms frame %@", "\(Swift.type(of: preview))", shown, NSStringFromRect(preview.frame)))
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: preview.windowNumber, context: nil, characters: "\u{1b}",
                                            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                NSApp.sendEvent(event)
            }
        }
        let gone = await waitUntil(5) { !preview.isVisible || !NSApp.windows.contains(preview) }
        SpikeRunner.record("pdf_print_closed", gone ? "closed by Esc" : "still open")
    }

    /// The viewer's toolbar is Chrome's (in the PDF extension's frame, out of
    /// reach of the isolated world): its Download button is clicked where it sits,
    /// `RoomPdfSaveFromRight` points left of the viewer's right edge, 28 pt down.
    func documentsPDFToolbarSave(_ page: any WebContents, folder: URL) async {
        let fromRight = UserDefaults.standard.object(forKey: "RoomPdfSaveFromRight") as? Double ?? 116
        let width = page.nativeView.bounds.width
        let rowsBefore = AppDelegate.current?.downloads?.list.rows.count ?? 0
        PageDriver.click(page, at: CGPoint(x: width - 300, y: 300), "documents: focus the PDF")
        try? await Task.sleep(for: .milliseconds(400))
        let start = ContinuousClock.now
        PageDriver.click(page, at: CGPoint(x: width - fromRight, y: 28), "documents: the viewer's Download button")
        // Chrome's viewer asks where to save (its file picker: an NSSavePanel sheet on Room's window).
        _ = await waitUntil(8) { self.window.attachedSheet is NSSavePanel }
        let sheetMs = ms(since: start)
        guard let panel = window.attachedSheet as? NSSavePanel else {
            return SpikeRunner.record("pdf_toolbar_save", String(format: "no save panel in 8 s; rows %d→%d %@ folder=%@ sheet=%@", rowsBefore,
                                                                 AppDelegate.current?.downloads?.list.rows.count ?? 0, downloadRows(), folderListing(folder),
                                                                 "\(window.attachedSheet.map { "\(Swift.type(of: $0))" } ?? "none")"))
        }
        // The panel is out of process (ViewBridge): a session cannot type into it or press Save
        // (`-[NSSavePanel ok:]` is not implemented there), and its directory is Chrome's download
        // pref, not the run's folder: cancelled here, the landing is a by-hand step.
        SpikeRunner.record("pdf_toolbar_save", String(format: "Chrome's save panel (%@) after %.0f ms, proposed \"%@\" in %@; cancelled (download rows %d→%d)",
                                                      "\(Swift.type(of: panel))", sheetMs, panel.nameFieldStringValue,
                                                      panel.directoryURL?.lastPathComponent ?? "nil", rowsBefore, AppDelegate.current?.downloads?.list.rows.count ?? 0))
        window.endSheet(panel, returnCode: .cancel)
        _ = await waitUntil(3) { self.window.attachedSheet == nil }
    }

    /// First launch: Settings ▸ Downloads ▸ PDFs ▸ Download, stored (the next launch passes the feature).
    func documentsPDFSetting() {
        sidebar.store.settings.update { $0.pdfsOpenInRoom = false; $0.downloadDirectory = documentsDownloads.path }
        SpikeRunner.record("pdf_setting", "pdfsOpenInRoom=\(sidebar.store.settings.settings.pdfsOpenInRoom) features_now=\((AppDelegate.current?.engine.features.enabled.sorted() ?? []))")
    }

    /// Second launch: the feature is on and a PDF navigation downloads.
    func documentsPDFDownload() async {
        let folder = documentsDownloads
        SpikeRunner.record("pdf_download_launch", "pdfsOpenInRoom=\(sidebar.store.settings.settings.pdfsOpenInRoom) features=\((AppDelegate.current?.engine.features.enabled.sorted() ?? []))")
        let start = ContinuousClock.now
        let page = session.newPage(Self.documentsPage("sample.pdf"))
        let landed = await waitUntil(15) {
            AppDelegate.current?.downloads?.list.rows.contains { $0.item.state == .complete && $0.item.destination?.lastPathComponent.hasSuffix(".pdf") == true } ?? false
        }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("pdf_download", String(format: "downloaded=%@ in %.0f ms rows=%@ folder=%@ page=%@ dom=%@", "\(landed)", ms(since: start), downloadRows(),
                                                  folderListing(folder), page?.url?.absoluteString ?? "nil",
                                                  page.map { _ in "" } ?? ""))
        if let page { SpikeRunner.record("pdf_download_page", "url=\(page.url?.absoluteString ?? "nil") state=\(page.state) dom=\(await js(page, Self.pdfDOMProbe))") }
        // Back to the default for the state's next launch.
        sidebar.store.settings.update { $0.pdfsOpenInRoom = true }
    }

    // MARK: viewsource

    func rightClickPage(_ page: any WebContents, _ selector: String) async {
        guard let point = await PageDriver.center(of: selector, in: page, "right-click \(selector)") else { return }
        Task { PageDriver.click(page, at: point, button: .rightMouseDown, "right-click \(selector)") }
    }

    /// The Today entry right below `entry` in the active space, or nil.
    func entryBelow(_ entry: UUID?) -> Entry? {
        let today = store.today(space: sidebar.activeSpaceID)
        guard let index = today.firstIndex(where: { $0.id == entry }), today.indices.contains(index + 1) else { return nil }
        return today[index + 1]
    }

    func sourceProbe(_ page: any WebContents) async -> String {
        await js(page, "JSON.stringify({ lines: document.querySelectorAll('td.line-content').length, mentions: document.body.textContent.includes('Room Save Page fixture') })")
    }

    func documentsViewSource() async {
        guard let app = AppDelegate.current, let page = await open(Self.documentsPage("page.html")) else {
            return SpikeRunner.record("error", "documents: page.html did not open")
        }
        let entry = tabs.entryID(for: page)
        // The menu item (View ▸ Developer ▸ View Source).
        var start = ContinuousClock.now
        app.viewPageSource(nil)
        _ = await waitUntil(5) { self.entryBelow(entry)?.currentURL?.hasPrefix("view-source:") == true && self.sidebar.selectedEntryID == self.entryBelow(entry)?.id }
        let menuEntry = entryBelow(entry)
        if let id = menuEntry?.id, let source = tabs.contents(for: id) {
            await waitLoaded(source)
            SpikeRunner.record("viewsource_menu", String(format: "in %.0f ms below_entry=%@ selected=%@ url=%@ dom=%@", ms(since: start), "\(menuEntry != nil)",
                                                         "\(sidebar.selectedEntryID == id)", source.url?.absoluteString ?? "nil", await sourceProbe(source)))
        } else {
            SpikeRunner.record("viewsource_menu", "no view-source tab under the page (below: \(menuEntry?.currentURL ?? "none"))")
        }
        // The page's context menu: Chrome's View Page Source (IDC_VIEW_SOURCE 35002).
        if let entry { sidebar.select(entry) }
        try? await Task.sleep(for: .milliseconds(500))
        let chrome = session.pageDelegate.chrome
        let presentMenu = chrome.presentMenu
        defer { chrome.presentMenu = presentMenu }
        let driver = MenuDriver()
        chrome.presentMenu = { menu, point, view in driver.show(menu, at: point, in: view) }
        driver.chooseTag = 35002
        var items = ""
        driver.onOpen = { menu in
            driver.offered = menu.menu.item(withTag: 35002) != nil
            items = menu.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | ")
            driver.finish()
        }
        let before = Set(store.today(space: sidebar.activeSpaceID).map(\.id))
        start = ContinuousClock.now
        // An empty spot of the page (a word would get the selection's menu).
        let size = page.nativeView.bounds.size
        Task { PageDriver.click(page, at: CGPoint(x: size.width - 120, y: size.height - 120), button: .rightMouseDown, "right-click the page") }
        _ = await waitUntil(8) { driver.closed }
        _ = await waitUntil(5) { self.store.today(space: self.sidebar.activeSpaceID).contains { !before.contains($0.id) } }
        let added = store.today(space: sidebar.activeSpaceID).first { !before.contains($0.id) }
        var line = String(format: "offered=%@ added in %.0f ms", "\(driver.offered)", ms(since: start))
        if let added, let source = tabs.contents(for: added.id) {
            await waitLoaded(source)
            let today = store.today(space: sidebar.activeSpaceID)
            let position = (today.firstIndex { $0.id == added.id } ?? -1) - (today.firstIndex { $0.id == entry } ?? -1)
            line += " position_from_page=\(position) selected=\(sidebar.selectedEntryID == added.id) url=\(source.url?.absoluteString ?? "nil") dom=\(await sourceProbe(source))"
        } else {
            line += " no new tab"
        }
        SpikeRunner.record("viewsource_context_menu", line)
        SpikeRunner.record("viewsource_context_menu_items", items)
    }

    // MARK: savepage: File ▸ Save Page… through its panel

    func documentsSavePagePanel() async {
        guard let app = AppDelegate.current, let page = await open(Self.documentsPage("page.html")) else {
            return SpikeRunner.record("error", "documents: page.html did not open")
        }
        let folder = Self.documentsWork.appending(path: "savepanel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let downloadDirectoryWas = sidebar.store.settings.settings.downloadDirectory
        defer { sidebar.store.settings.update { $0.downloadDirectory = downloadDirectoryWas } }
        sidebar.store.settings.update { $0.downloadDirectory = folder.path }
        _ = await waitUntilAsync(5) { await self.js(page, "String(document.images[0].complete)") == "\"true\"" }
        app.savePageAs(nil)
        _ = await waitUntil(5) { self.window.attachedSheet is NSSavePanel }
        guard let panel = window.attachedSheet as? NSSavePanel, let formats = app.savePanelFormats else {
            return SpikeRunner.record("savepage_panel", "no save panel")
        }
        let proposed = panel.nameFieldStringValue
        formats.choose(.mhtml)
        SpikeRunner.record("savepage_panel", "proposed=\"\(proposed)\" formats=\(formats.titles) after MHTML: \"\(panel.nameFieldStringValue)\" types=\(panel.allowedContentTypes.map(\.identifier))")
        // The panel is out of process: Save is pressed by ending its sheet with OK (its directory
        // is the downloads folder the run set; the name the title's, its extension the format's).
        let start = ContinuousClock.now
        window.endSheet(panel, returnCode: .OK)
        let target = folder.appending(path: SavePageRules.fileName(title: page.title, url: page.url, format: .mhtml))
        let written = await waitUntil(10) { self.fileSize(target) > 0 && app.toastCenter?.currentToast?.id == "save-page" }
        SpikeRunner.record("savepage_written", String(format: "%@ in %.0f ms size=%d toast=\"%@\" action=%@", "\(written)", ms(since: start), fileSize(target),
                                                      app.toastCenter?.currentToast?.message ?? "none", app.toastCenter?.currentToast?.action?.title ?? "none"))
        // The archive reopens with its image (a file:// Today tab).
        if written, let reopened = await open(target) {
            _ = await waitUntilAsync(5) { await self.js(reopened, "String(!!document.images[0] && document.images[0].complete)") == "\"true\"" }
            SpikeRunner.record("savepage_reopened", "title=\(reopened.title ?? "nil") image=\(await js(reopened, "(() => { const i = document.querySelector('#swatch'); return i ? [i.complete, i.naturalWidth, i.naturalHeight] : null })()"))")
        }
        // A page Chromium cannot save (the PDF): the toast says so.
        if let pdf = await open(Self.documentsPage("sample.pdf")) {
            try? await Task.sleep(for: .milliseconds(1000))
            await app.savePage(pdf, as: .completeHTML, to: folder.appending(path: "sample.html"))
            SpikeRunner.record("savepage_pdf", "toast=\"\(app.toastCenter?.currentToast?.message ?? "none")\" file=\(fileSize(folder.appending(path: "sample.html")))")
        }
    }

    // MARK: screenshot: ⇧⌘2

    /// A drag on the overlay with real mouse events, from and to page points.
    func dragOverlay(_ overlay: NSView, from start: CGPoint, to end: CGPoint) {
        func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent? {
            let location = overlay.convert(point, to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, mid), (.leftMouseDragged, end), (.leftMouseUp, end)] {
            if let event = event(type, point) { window.sendEvent(event) }
        }
    }

    func pasteboardPNG() -> String {
        guard let data = NSPasteboard.general.data(forType: .png), let rep = NSBitmapImageRep(data: data) else { return "none" }
        let centre = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 4)?.usingColorSpace(.sRGB)
        return "\(rep.pixelsWide)x\(rep.pixelsHigh) (\(data.count) B) pixel@(1/2,1/4)=" + (centre.map { String(format: "(%.0f, %.0f, %.0f)", $0.redComponent * 255, $0.greenComponent * 255, $0.blueComponent * 255) } ?? "nil")
    }

    func openOverlay(_ app: AppDelegate) async -> ScreenshotController? {
        let start = ContinuousClock.now
        app.captureScreenshot(nil)
        guard let controller = app.screenshot else { return nil }
        let up = await waitUntil(3) { controller.overlay.window != nil && self.window.firstResponder === controller.overlay }
        SpikeRunner.record("screenshot_overlay", String(format: "shown=%@ in %.0f ms frame=%@ page=%@ first_responder=%@", "\(up)", ms(since: start),
                                                        NSStringFromRect(controller.overlay.frame),
                                                        NSStringFromRect(controller.page.nativeView.convert(controller.page.nativeView.bounds, to: window.contentView)),
                                                        "\(window.firstResponder === controller.overlay)"))
        return controller
    }

    func documentsScreenshot() async {
        guard let app = AppDelegate.current, let page = await open(Self.documentsPage("page.html")) else {
            return SpikeRunner.record("error", "documents: page.html did not open")
        }
        let folder = documentsDownloads
        let downloadDirectoryWas = sidebar.store.settings.settings.downloadDirectory
        defer { sidebar.store.settings.update { $0.downloadDirectory = downloadDirectoryWas } }
        sidebar.store.settings.update { $0.downloadDirectory = folder.path }
        _ = await waitUntilAsync(5) { await self.js(page, "String(document.images[0].complete)") == "\"true\"" }
        let scale = window.backingScaleFactor
        // 1. A dragged rectangle around the swatch, copied.
        guard let swatch = await rect(of: "#swatch", in: page), let controller = await openOverlay(app) else {
            return SpikeRunner.record("screenshot_drag", "no overlay or no swatch")
        }
        var start = ContinuousClock.now
        dragOverlay(controller.overlay, from: CGPoint(x: swatch.minX, y: swatch.minY), to: CGPoint(x: swatch.maxX, y: swatch.maxY))
        var captured = await waitUntil(5) { controller.image != nil }
        SpikeRunner.record("screenshot_drag", String(format: "%@ in %.0f ms selection=%@ image=%ldx%ld px (expected %.0fx%.0f at %.0f×) bar=%@ %@",
                                                     "\(captured)", ms(since: start), controller.overlay.selection.map { NSStringFromRect($0) } ?? "nil",
                                                     controller.image?.width ?? 0, controller.image?.height ?? 0, swatch.width * scale, swatch.height * scale, scale,
                                                     "\(controller.overlay.isBarShown)", NSStringFromRect(controller.overlay.barFrame)))
        if let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") {
            let url = URL(fileURLWithPath: directory).appending(path: "phase-4.7-screenshot-overlay.png")
            SpikeRunner.record("capture_screenshot_overlay", (try? WindowSnapshot.writePNG(window, to: url)) != nil ? url.lastPathComponent : "failed")
        }
        NSPasteboard.general.clearContents()
        controller.perform(.copy)
        SpikeRunner.record("screenshot_copy", "pasteboard png=\(pasteboardPNG()) types=\(NSPasteboard.general.types?.map(\.rawValue) ?? []) overlay_closed=\(app.screenshot == nil) toast=\"\(app.toastCenter?.currentToast?.message ?? "none")\"")

        // 2. Return: the whole viewport, saved to the downloads folder.
        guard let second = await openOverlay(app) else { return }
        PageDriver.key(window, characters: "\r", keyCode: 36)
        captured = await waitUntil(5) { second.image != nil }
        let viewport = page.nativeView.bounds.size
        start = ContinuousClock.now
        let saved = second.save()
        SpikeRunner.record("screenshot_save", String(format: "return_captured=%@ image=%ldx%ld px (viewport %.0fx%.0f pt) file=%@ size=%d png=%@ in %.0f ms toast=\"%@\" show=%@",
                                                     "\(captured)", second.image?.width ?? 0, second.image?.height ?? 0, viewport.width, viewport.height,
                                                     saved?.lastPathComponent ?? "nil", saved.map(fileSize) ?? -1,
                                                     saved.flatMap { try? Data(contentsOf: $0) }.map(pngPixels) ?? "none", ms(since: start),
                                                     app.toastCenter?.currentToast?.message ?? "none", app.toastCenter?.currentToast?.action?.title ?? "none"))

        // 3. Open as Tab: a file:// Today tab under the page, shown.
        if let entry = tabs.entryID(for: page) { sidebar.select(entry) }
        try? await Task.sleep(for: .milliseconds(400))
        guard let third = await openOverlay(app) else { return }
        dragOverlay(third.overlay, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 410, y: 310))
        _ = await waitUntil(5) { third.image != nil }
        let entry = tabs.entryID(for: page)
        third.perform(.openAsTab)
        _ = await waitUntil(5) { self.entryBelow(entry)?.currentURL?.hasPrefix("file:") == true }
        if let below = entryBelow(entry), let tab = tabs.contents(for: below.id) {
            await waitLoaded(tab)
            SpikeRunner.record("screenshot_open_as_tab", "url=\(tab.url?.lastPathComponent ?? "nil") selected=\(sidebar.selectedEntryID == below.id) image=\(await js(tab, "(() => { const i = document.images[0]; return i ? [i.naturalWidth, i.naturalHeight] : null })()"))")
        } else {
            SpikeRunner.record("screenshot_open_as_tab", "no file:// tab under the page")
        }

        // 4. Esc cancels.
        if let entry { sidebar.select(entry) }
        try? await Task.sleep(for: .milliseconds(400))
        if let fourth = await openOverlay(app) {
            PageDriver.key(window, characters: "\u{1b}", keyCode: 53)
            let gone = await waitUntil(3) { app.screenshot == nil && fourth.overlay.window == nil }
            SpikeRunner.record("screenshot_escape", "closed=\(gone) first_responder=\(window.firstResponder.map { "\(Swift.type(of: $0))" } ?? "nil")")
        }

        // 5. Full page on the tall fixture.
        guard let tall = await open(Self.documentsPage("tall.html")) else { return }
        try? await Task.sleep(for: .milliseconds(500))
        guard let fifth = await openOverlay(app) else { return }
        PageDriver.key(window, characters: "\r", keyCode: 36)
        _ = await waitUntil(5) { fifth.image != nil }
        start = ContinuousClock.now
        fifth.perform(.fullPage)
        let full = await waitUntil(10) { fifth.isFullPage }
        let tallViewport = tall.nativeView.bounds.size
        SpikeRunner.record("screenshot_full_page", String(format: "%@ in %.0f ms image=%ldx%ld px viewport=%.0fx%.0f pt (taller=%@) bar=%@",
                                                          "\(full)", ms(since: start), fifth.image?.width ?? 0, fifth.image?.height ?? 0, tallViewport.width, tallViewport.height,
                                                          "\(CGFloat(fifth.image?.height ?? 0) > tallViewport.height * scale)", "\(fifth.overlay.isBarShown)"))
        let fullFile = fifth.save()
        SpikeRunner.record("screenshot_full_page_saved", "file=\(fullFile?.lastPathComponent ?? "nil") png=\(fullFile.flatMap { try? Data(contentsOf: $0) }.map(pngPixels) ?? "none")")
        SpikeRunner.record("screenshot_folder", folderListing(folder))
    }

    // MARK: engine: the members

    func documentsEngine() async {
        let saved = Self.documentsWork.appending(path: "saved", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
        guard let page = await open(Self.documentsPage("page.html")) else {
            return SpikeRunner.record("error", "documents: page.html did not open")
        }
        _ = await waitUntilAsync(5) { await self.js(page, "String(document.images[0] && document.images[0].complete)") == "\"true\"" }
        for format in SavePageFormat.allCases {
            let file = saved.appending(path: "Page-\(format.rawValue).\(format.fileExtension)")
            let start = ContinuousClock.now
            do {
                try await page.savePage(as: format, to: file)
                var line = String(format: "ok in %.0f ms file=%@ size=%d", ms(since: start), file.lastPathComponent, fileSize(file))
                if let directory = format.resourcesDirectory(for: file) {
                    let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
                    line += " resources=[" + names.map { "\($0) \(fileSize(directory.appending(path: $0)))" }.joined(separator: ", ") + "]"
                }
                SpikeRunner.record("engine_save_\(format.rawValue)", line)
            } catch {
                SpikeRunner.record("engine_save_\(format.rawValue)", String(format: "failed in %.0f ms: %@", ms(since: start), "\(error)"))
            }
        }
        // The MHTML reopened as a file:// page: the image from the archive.
        let archive = saved.appending(path: "Page-mhtml.mhtml")
        if FileManager.default.fileExists(atPath: archive.path), let reopened = await open(archive) {
            _ = await waitUntilAsync(5) { await self.js(reopened, "String(!!document.images[0] && document.images[0].complete)") == "\"true\"" }
            let image = await js(reopened, "(() => { const i = document.querySelector('#swatch'); return i ? [i.complete, i.naturalWidth, i.naturalHeight, i.currentSrc.slice(0, 40)] : null })()")
            var pixelLine = "no capture"
            if let rect = await rect(of: "#swatch", in: reopened), let capture = await PageDriver.capture(reopened, "documents: the reopened MHTML") {
                let centre = pixel(capture, at: CGPoint(x: rect.midX, y: rect.minY + 20))
                let band = pixel(capture, at: CGPoint(x: rect.midX, y: rect.minY + 60))
                pixelLine = "image rect \(NSStringFromRect(rect)) pixel(orange part)=\(centre.map { "\($0)" } ?? "nil") pixel(blue band)=\(band.map { "\($0)" } ?? "nil")"
                if let png = pngData(capture) { keepCapture(png, "mhtml-reopened-viewport.png") }
            }
            SpikeRunner.record("engine_mhtml_reopened", "url=\(reopened.url?.scheme ?? "nil"):…\(reopened.url?.lastPathComponent ?? "") title=\(reopened.title ?? "nil") image=\(image) \(pixelLine)")
        } else {
            SpikeRunner.record("engine_mhtml_reopened", "no archive to reopen")
        }

        // Full page through the DevTools protocol, then again with DevTools' own front-end open.
        guard let tall = await open(Self.documentsPage("tall.html")) else {
            return SpikeRunner.record("error", "documents: tall.html did not open")
        }
        try? await Task.sleep(for: .milliseconds(500))
        let viewport = tall.nativeView.bounds.size
        let scale = tall.nativeView.window?.backingScaleFactor ?? 2
        let innerBefore = await js(tall, "[innerWidth, innerHeight, document.documentElement.scrollHeight]")
        for devToolsOpen in [false, true] {
            if devToolsOpen {
                session.host.toggleDevTools()
                _ = await waitUntil(5) { tall.devTools?.isOpen == true }
                try? await Task.sleep(for: .milliseconds(800))
            }
            let start = ContinuousClock.now
            do {
                let (png, content) = try await fullPageCapture(tall)
                let pixels = pngPixels(png)
                keepCapture(png, devToolsOpen ? "fullpage-devtools-open.png" : "fullpage.png")
                SpikeRunner.record("engine_fullpage\(devToolsOpen ? "_devtools_open" : "")", String(
                    format: "ok in %.0f ms png=%@ (%d B) content=%.0fx%.0f css viewport=%.0fx%.0f pt scale=%.0f devtools_open=%@",
                    ms(since: start), pixels, png.count, content.width, content.height, viewport.width, viewport.height, scale, "\(tall.devTools?.isOpen == true)"))
            } catch {
                SpikeRunner.record("engine_fullpage\(devToolsOpen ? "_devtools_open" : "")", String(format: "failed in %.0f ms: %@ devtools_open=%@", ms(since: start), "\(error)", "\(tall.devTools?.isOpen == true)"))
            }
            if devToolsOpen {
                session.host.toggleDevTools()
                _ = await waitUntil(5) { tall.devTools?.isOpen != true }
            }
        }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("engine_fullpage_viewport_after", "before=\(innerBefore) after=\(await js(tall, "[innerWidth, innerHeight, document.documentElement.scrollHeight]"))")
        // A command the protocol refuses comes back as an error.
        do {
            _ = try await tall.sendDevToolsCommand("Room.noSuchMethod", params: [:])
            SpikeRunner.record("engine_devtools_unknown", "answered (unexpected)")
        } catch {
            SpikeRunner.record("engine_devtools_unknown", "error \(error)")
        }
    }

    func waitUntilAsync(_ seconds: Double, _ condition: () async -> Bool) async -> Bool {
        let start = Date()
        while !(await condition()) {
            if Date().timeIntervalSince(start) > seconds { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }
}
#endif
