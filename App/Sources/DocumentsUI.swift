import AppKit
import Chrome
import Design
import Engine
import Model
import UniformTypeIdentifiers

/// Phase 4.7a's documents: File ▸ Save Page… (⇧⌘S) over
/// `WebContents.savePage`, View ▸ Developer ▸ View Source, and ⇧⌘2's
/// screenshot overlay (`ScreenshotController`).
extension AppDelegate {
    /// The folder downloads go to (Settings ▸ Downloads), where Save Page's
    /// panel starts and screenshots are saved.
    var documentsFolder: URL {
        downloads?.list.folder() ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    // MARK: Save Page

    /// ⇧⌘S: a save panel with a format popup, then the engine's save and a
    /// toast with Show. A page Chromium cannot save (a PDF, an image) says
    /// so in the toast (the PDF viewer's own Download button saves PDFs).
    @objc func savePageAs(_ sender: Any?) {
        guard let page = tabs?.focusedPage, let window = windowController?.window else { return }
        let panel = NSSavePanel()
        let formats = SavePageFormatPopup(panel: panel, title: page.title, url: page.url)
        panel.directoryURL = documentsFolder
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.accessoryView = formats.view
        savePanelFormats = formats
        panel.beginSheetModal(for: window) { [weakSelf = MainActorWeak(self), weak page] response in
            MainActor.assumeIsolated {
                guard let self = weakSelf.value else { return }
                self.savePanelFormats = nil
                guard response == .OK, let chosen = panel.url, let page else { return }
                // The format's extension, whatever the name field kept (the panel is out of process).
                let url = chosen.deletingLastPathComponent().appending(path: SavePageRules.renamed(chosen.lastPathComponent, to: formats.format))
                Task { await self.savePage(page, as: formats.format, to: url) }
            }
        }
    }

    /// The save itself (the panel's answer; the spikes call it directly).
    func savePage(_ page: any WebContents, as format: SavePageFormat, to url: URL) async {
        do {
            try await page.savePage(as: format, to: url)
            NSLog("Room: saved the page as %@ to %@", format.rawValue, url.path)
            toastCenter?.show(Toast(id: "save-page", symbol: .savePage, message: "Saved “\(url.lastPathComponent)”",
                                    action: Toast.Action(title: "Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }))
        } catch {
            NSLog("Room: Save Page failed: %@", "\(error)")
            toastCenter?.show(Toast(id: "save-page", symbol: .info, message: "Could not save the page: \(Self.message(error))"))
        }
    }

    static func message(_ error: any Error) -> String {
        if case EngineError.failed(let text) = error { return text }
        return "\(error)"
    }

    // MARK: View Source

    /// View ▸ Developer ▸ View Source: `view-source:<url>` as a Today tab
    /// under the current entry, shown (Chromium renders it). The page's
    /// context menu has Chrome's own View Page Source, which opens the same
    /// through the engine's new-tab path.
    @objc func viewPageSource(_ sender: Any?) {
        guard let page = tabs?.focusedPage, let source = Self.viewSourceURL(for: page.url) else { return }
        guard let id = tabs?.openLink(source, from: page) else { return }
        sidebar?.select(id)
    }

    /// `view-source:` for a web or file page; nil for the rest (and for a source view itself).
    static func viewSourceURL(for url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else { return nil }
        return URL(string: "view-source:" + url.absoluteString)
    }

    // MARK: Page Setup (4.7b)

    /// File ▸ Page Setup…: macOS's page layout sheet on the shared print
    /// info. Chrome's print preview starts each job from a copy of it
    /// (`PrintingContextMac`), and its own Layout and paper choices override it.
    @objc func showPageSetup(_ sender: Any?) {
        guard let window = windowController?.window else { return }
        NSPageLayout().beginSheet(using: NSPrintInfo.shared, on: window) { response in
            NSLog("Room: page setup %@: %@, %@", response == .changed ? "changed" : "cancelled",
                  NSPrintInfo.shared.orientation == .landscape ? "landscape" : "portrait", NSPrintInfo.shared.paperName?.rawValue ?? "?")
        }
    }

    // MARK: Screenshots

    /// ⇧⌘2: the crop overlay over the focused page (again: closes it).
    @objc func captureScreenshot(_ sender: Any?) {
        if let screenshot {
            screenshot.close()
            return
        }
        guard let page = tabs?.focusedPage, let rootView = windowController?.rootView else { return }
        let controller = ScreenshotController(page: page, rootView: rootView, toasts: toastCenter, folder: { [weakSelf = MainActorWeak(self)] in
            weakSelf.value?.documentsFolder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }, tabsFolder: Self.stateDirectory.appending(path: "Screenshots", directoryHint: .isDirectory))
        controller.openTab = { [weakSelf = MainActorWeak(self)] url, page in
            guard let self = weakSelf.value, let id = self.tabs?.openLink(url, from: page) else { return }
            self.sidebar?.select(id)
        }
        controller.onClose = { [weakSelf = MainActorWeak(self)] in weakSelf.value?.screenshot = nil }
        screenshot = controller
        controller.show()
    }
}

/// The save panel's format popup (an accessory view); the file name's
/// extension follows the choice.
@MainActor
final class SavePageFormatPopup: NSObject {
    let view: NSView
    private let popup = NSPopUpButton()
    private weak var panel: NSSavePanel?
    private(set) var format: SavePageFormat = SavePageRules.formats[0]

    init(panel: NSSavePanel, title: String?, url: URL?) {
        self.panel = panel
        let label = NSTextField(labelWithString: "Format:")
        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.spacing = Spacing.s
        stack.edgeInsets = NSEdgeInsets(top: Spacing.s, left: Spacing.l, bottom: Spacing.s, right: Spacing.l)
        view = stack
        super.init()
        popup.addItems(withTitles: SavePageRules.formats.map(SavePageRules.title))
        popup.target = self
        popup.action = #selector(formatChanged(_:))
        panel.nameFieldStringValue = SavePageRules.fileName(title: title, url: url, format: format)
        apply()
    }

    /// The popup's choice (the spikes pick one the same way).
    func choose(_ format: SavePageFormat) {
        guard let index = SavePageRules.formats.firstIndex(of: format) else { return }
        popup.selectItem(at: index)
        formatChanged(popup)
    }

    var titles: [String] { popup.itemTitles }

    @objc private func formatChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard SavePageRules.formats.indices.contains(index), let panel else { return }
        format = SavePageRules.formats[index]
        panel.nameFieldStringValue = SavePageRules.renamed(panel.nameFieldStringValue, to: format)
        apply()
    }

    private func apply() {
        let type = format == .mhtml ? (UTType(filenameExtension: "mhtml") ?? .data) : .html
        panel?.allowedContentTypes = [type]
    }
}

/// One ⇧⌘2: the overlay over the focused page, the capture cut to the
/// selection at the capture's own scale, then Copy (PNG and TIFF on the
/// pasteboard), Save (the downloads folder, a toast with Show), Open as Tab
/// (a `file://` Today tab under the page) and Full Page (the DevTools
/// protocol's `Page.captureScreenshot` beyond the viewport).
@MainActor
final class ScreenshotController {
    let page: any WebContents
    let overlay: ScreenshotOverlayView
    private weak var rootView: NSView?
    private weak var toasts: ToastCenter?
    private let folder: () -> URL
    private let tabsFolder: URL
    var openTab: ((URL, any WebContents) -> Void)?
    var onClose: (() -> Void)?

    /// The image now (the selection, or the full page), its PNG and how it was taken.
    private(set) var image: CGImage?
    private(set) var png: Data?
    private(set) var isFullPage = false
    private(set) var savedURL: URL?
    private var previousResponder: NSResponder?
    private var frameObserver: NSObjectProtocol?

    init(page: any WebContents, rootView: NSView, toasts: ToastCenter?, folder: @escaping () -> URL, tabsFolder: URL) {
        self.page = page
        self.rootView = rootView
        self.toasts = toasts
        self.folder = folder
        self.tabsFolder = tabsFolder
        let view = page.nativeView
        overlay = ScreenshotOverlayView(frame: view.convert(view.bounds, to: rootView))
        overlay.onSelect = { [weak self] rect in self?.capture(rect) }
        overlay.onCancel = { [weak self] in self?.close() }
        overlay.onAction = { [weak self] action in self?.perform(action) }
    }

    func show() {
        guard let rootView else { return }
        rootView.addSubview(overlay, positioned: .above, relativeTo: nil)
        previousResponder = rootView.window?.firstResponder
        rootView.window?.makeFirstResponder(overlay)
        // The page's frame moved (the window resized, the sidebar toggled): the selection is stale.
        page.nativeView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: page.nativeView,
                                                               queue: .main) { [weakSelf = MainActorWeak(self)] _ in
            MainActor.assumeIsolated { weakSelf.value?.close() }
        }
        NSLog("Room: screenshot overlay over %@", NSStringFromRect(overlay.frame))
    }

    func close() {
        if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        frameObserver = nil
        overlay.removeFromSuperview()
        if let previousResponder, overlay.window == nil { rootView?.window?.makeFirstResponder(previousResponder) }
        onClose?()
    }

    /// The selection from the engine's capture of the viewport.
    func capture(_ rect: CGRect) {
        overlay.showBar("Capturing…", fullPageAvailable: false)
        Task {
            do {
                let viewport = try await page.captureViewport()
                guard let full = viewport.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let pixels = ScreenshotRules.pixelRect(for: rect, viewSize: overlay.bounds.size,
                                                             pixelSize: CGSize(width: full.width, height: full.height)),
                      let cropped = full.cropping(to: pixels)
                else { throw EngineError.failed("the capture could not be cut to the selection") }
                setImage(cropped, fullPage: false)
            } catch {
                toasts?.show(Toast(id: "screenshot", symbol: .info, message: "Could not capture the page: \(AppDelegate.message(error))"))
                close()
            }
        }
    }

    private func setImage(_ cgImage: CGImage, fullPage: Bool, png data: Data? = nil) {
        image = cgImage
        png = data ?? NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        isFullPage = fullPage
        savedURL = nil
        let scale = page.nativeView.window?.backingScaleFactor ?? 2
        let text = String(format: "%.0f × %.0f%@", Double(cgImage.width) / scale, Double(cgImage.height) / scale, fullPage ? " · full page" : "")
        overlay.showBar(text, fullPageAvailable: !fullPage)
        NSLog("Room: screenshot %ldx%ld px%@", cgImage.width, cgImage.height, fullPage ? " (full page)" : "")
    }

    func perform(_ action: ScreenshotOverlayView.Action) {
        switch action {
        case .copy: copy()
        case .save: _ = save()
        case .openAsTab: openAsTab()
        case .fullPage: captureFullPage()
        case .close: close()
        }
    }

    func copy() {
        guard let png, let image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        toasts?.show(Toast(id: "screenshot", symbol: .screenshot, message: "Copied the screenshot"))
        close()
    }

    /// Writes the PNG to the downloads folder; the URL, or nil after a toast saying why.
    @discardableResult
    func save() -> URL? {
        guard let png else { return nil }
        let url = ScreenshotRules.uniqueURL(for: ScreenshotRules.fileName(at: Date()), in: folder()) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
        } catch {
            toasts?.show(Toast(id: "screenshot", symbol: .info, message: "Could not save the screenshot: \(error.localizedDescription)"))
            return nil
        }
        savedURL = url
        toasts?.show(Toast(id: "screenshot", symbol: .screenshot, message: "Saved “\(url.lastPathComponent)”",
                           action: Toast.Action(title: "Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }))
        close()
        return url
    }

    /// The image as a `file://` Today tab under the page (the saved file, or one in the state's Screenshots folder).
    func openAsTab() {
        guard let png else { return }
        var url = savedURL
        if url == nil {
            let target = ScreenshotRules.uniqueURL(for: ScreenshotRules.fileName(at: Date()), in: tabsFolder) {
                FileManager.default.fileExists(atPath: $0.path)
            }
            do {
                try FileManager.default.createDirectory(at: tabsFolder, withIntermediateDirectories: true)
                try png.write(to: target, options: .atomic)
                url = target
            } catch {
                toasts?.show(Toast(id: "screenshot", symbol: .info, message: "Could not open the screenshot: \(error.localizedDescription)"))
                return
            }
        }
        guard let url else { return }
        let page = page
        close()
        openTab?(url, page)
    }

    /// The whole page through the DevTools protocol (bounded, 4.7a); the
    /// viewport's selection stays when it fails.
    func captureFullPage() {
        overlay.setBarText("Capturing the full page…")
        Task {
            do {
                let (data, _) = try await FullPageCapture.png(of: page)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw EngineError.failed("the page's PNG could not be read") }
                overlay.select(nil)
                setImage(image, fullPage: true, png: data)
            } catch {
                NSLog("Room: full-page capture failed: %@", "\(error)")
                toasts?.show(Toast(id: "screenshot", symbol: .info, message: "Full page capture failed: \(AppDelegate.message(error))"))
                if let image { setImage(image, fullPage: false, png: png) }
            }
        }
    }
}

/// A full-page PNG through `WebContents.sendDevToolsCommand` (Puppeteer's
/// recipe: `Page.getLayoutMetrics`' CSS content size as the clip,
/// `captureBeyondViewport`), clipped to Chromium's largest capture.
@MainActor
enum FullPageCapture {
    static func png(of page: any WebContents) async throws -> (png: Data, clip: CGSize) {
        let metrics = try await page.sendDevToolsCommand("Page.getLayoutMetrics", params: [:])
        let content = (metrics["cssContentSize"] ?? metrics["contentSize"]) as? [String: Any]
        let size = CGSize(width: (content?["width"] as? NSNumber)?.doubleValue ?? 0, height: (content?["height"] as? NSNumber)?.doubleValue ?? 0)
        guard size.width > 0, size.height > 0 else { throw EngineError.failed("the page reported no content size") }
        let scale = page.nativeView.window?.backingScaleFactor ?? 2
        let clip = ScreenshotRules.fullPageClip(contentSize: size, scale: scale, maximumPixels: ScreenshotMetrics.maximumCapturePixels)
        let result = try await page.sendDevToolsCommand("Page.captureScreenshot", params: [
            "format": "png", "captureBeyondViewport": true, "fromSurface": true,
            "clip": ["x": 0, "y": 0, "width": clip.width, "height": clip.height, "scale": 1],
        ])
        guard let base64 = result["data"] as? String, let png = Data(base64Encoded: base64) else {
            throw EngineError.failed("Page.captureScreenshot answered without an image")
        }
        return (png, clip)
    }
}
