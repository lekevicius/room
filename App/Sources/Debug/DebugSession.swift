import AppKit
import Engine
import Observation

/// Chapter 1 throwaway: a flat list of pages in one window, driven by the
/// debug toolbar, acting as every page's UI and navigation delegate with
/// minimal AppKit UI. Chapter 2 replaces it with the sidebar model.
@Observable
final class DebugSession {
    let profile: any Profile
    @ObservationIgnored let host: PageHost

    private(set) var pages: [any WebContents] = []
    private(set) var currentIndex: Int?
    var statusText: String?
    /// Bumped by ⌘L; the toolbar focuses its address field.
    var addressFocusRequest = 0
    /// Every key the engine reported as reserved or unhandled, for the keyboard spike.
    @ObservationIgnored private(set) var keyLog: [String] = []
    @ObservationIgnored private(set) var downloads: [DownloadItem.ID: DownloadItem] = [:]

    init(profile: any Profile, host: PageHost) {
        self.profile = profile
        self.host = host
        profile.downloadsDelegate = self
    }

    var current: (any WebContents)? { currentIndex.map { pages[$0] } }

    // MARK: Pages

    @discardableResult
    func newPage(_ url: URL?, hidden: Bool = false, select: Bool = true) -> (any WebContents)? {
        do {
            let contents = try profile.createWebContents(WebContentsConfiguration(initiallyHidden: hidden))
            adopt(contents, select: select)
            if let url { contents.load(url) }
            return contents
        } catch {
            NSLog("Room: createWebContents failed: \(error)")
            return nil
        }
    }

    func select(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        currentIndex = index
        host.show(pages[index])
    }

    func open(_ text: String) {
        guard let url = Self.url(from: text) else { return }
        if let current { current.load(url, transition: .typed, fromAddressBar: true) } else { newPage(url) }
    }

    func closeCurrent() {
        current?.close()
    }

    private func adopt(_ contents: any WebContents, select: Bool) {
        contents.uiDelegate = self
        contents.navigationDelegate = self
        pages.append(contents)
        if select || currentIndex == nil { self.select(pages.count - 1) }
    }

    /// Typed text → URL: a scheme or a dot means a URL, anything else a search.
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") || trimmed.hasPrefix("about:") || trimmed.hasPrefix("data:") || trimmed.hasPrefix("file:") {
            return URL(string: trimmed)
        }
        if trimmed.contains("."), !trimmed.contains(" ") { return URL(string: "https://" + trimmed) }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }

    private func logKey(_ kind: String, _ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        keyLog.append("\(kind) keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "") flags=\(flags.rawValue)")
    }
}

// MARK: - UI delegate

extension DebugSession: WebContentsUIDelegate {
    func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?, disposition: Disposition) {
        adopt(newContents, select: disposition != .newBackgroundTab)
    }

    func webContentsDidClose(_ webContents: any WebContents) {
        guard let index = pages.firstIndex(where: { $0 === webContents }) else { return }
        pages.remove(at: index)
        if pages.isEmpty {
            currentIndex = nil
            host.show(nil)
        } else if let currentIndex {
            if currentIndex == index {
                select(min(index, pages.count - 1))
            } else if currentIndex > index {
                self.currentIndex = currentIndex - 1
            }
        }
    }

    func webContents(_ webContents: any WebContents, didChangeStatusText text: String?) {
        if webContents === current { statusText = text }
    }

    func webContents(_ webContents: any WebContents, isReservedKeyEvent event: NSEvent) -> Bool {
        let reserved = ReservedShortcuts.matches(event)
        if reserved { logKey("reserved", event) }
        return reserved
    }

    func webContents(_ webContents: any WebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        logKey("unhandled", event)
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    func webContents(_ webContents: any WebContents, willShowContextMenu menu: MenuModel, for element: ContextMenuElement) -> Bool {
        let view = webContents.nativeView
        // Present on the next turn, outside CEF's callback.
        Task { @MainActor in ContextMenuPresenter.present(menu, at: element.location, in: view) }
        return true
    }

    func webContents(_ webContents: any WebContents, runJavaScriptAlert message: String, origin: URL?, completion: @escaping () -> Void) {
        sheet(title: origin?.host() ?? "Page", message: message, buttons: ["OK"]) { _ in completion() }
    }

    func webContents(_ webContents: any WebContents, runJavaScriptConfirm message: String, origin: URL?, completion: @escaping (Bool) -> Void) {
        sheet(title: origin?.host() ?? "Page", message: message, buttons: ["OK", "Cancel"]) { completion($0 == 0) }
    }

    func webContents(_ webContents: any WebContents, runJavaScriptPrompt message: String, defaultText: String, origin: URL?, completion: @escaping (String?) -> Void) {
        let field = NSTextField(string: defaultText)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        sheet(title: origin?.host() ?? "Page", message: message, buttons: ["OK", "Cancel"], accessory: field) {
            completion($0 == 0 ? field.stringValue : nil)
        }
    }

    func webContents(_ webContents: any WebContents, runBeforeUnloadDialogForReload isReload: Bool, completion: @escaping (Bool) -> Void) {
        sheet(title: isReload ? "Reload this page?" : "Leave this page?", message: "Changes you made may not be saved.",
              buttons: [isReload ? "Reload" : "Leave", "Stay"]) { completion($0 == 0) }
    }

    func webContents(_ webContents: any WebContents, willAskForPermission requests: [PermissionRequest], quietReason: PermissionQuietReason?, completion: @escaping (PermissionResponse) -> Void) {
        let kinds = requests.map { "\($0.kind)" }.joined(separator: ", ")
        sheet(title: "\(requests.first?.origin.host() ?? "Page") wants: \(kinds)", message: "", buttons: ["Allow", "Don’t Allow"]) {
            completion($0 == 0 ? .granted : .denied)
        }
    }

    func webContents(_ webContents: any WebContents, didFailCertificateCheck error: CertificateError, completion: @escaping (Bool) -> Void) {
        sheet(title: "Certificate error", message: "\(error.url.host() ?? ""): \(error.description)", buttons: ["Go Back", "Proceed"]) {
            completion($0 == 1)
        }
    }

    func webContents(_ webContents: any WebContents, runFileChooser request: FileChooserRequest, completion: @escaping ([URL]?) -> Void) {
        guard let window = host.container.window else { return completion(nil) }
        if request.mode == .save {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = request.defaultPath?.lastPathComponent ?? ""
            panel.beginSheetModal(for: window) { completion($0 == .OK ? panel.url.map { [$0] } : nil) }
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = request.mode == .openMultiple
        panel.canChooseDirectories = request.mode == .openFolder
        panel.canChooseFiles = request.mode != .openFolder
        panel.beginSheetModal(for: window) { completion($0 == .OK ? panel.urls : nil) }
    }

    private func sheet(title: String, message: String, buttons: [String], accessory: NSView? = nil, completion: @escaping (Int) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        alert.accessoryView = accessory
        guard let window = host.container.window else {
            completion(alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
            return
        }
        alert.beginSheetModal(for: window) { response in
            completion(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
        }
    }
}

// MARK: - Navigation delegate

extension DebugSession: NavigationDelegate {
    func webContents(_ webContents: any WebContents, decidePolicyFor action: NavigationAction) -> Disposition {
        action.disposition
    }
}

// MARK: - Downloads

extension DebugSession: DownloadsDelegate {
    func profile(_ profile: any Profile, willBeginDownload item: DownloadItem, completion: @escaping (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var destination = folder.appending(path: item.suggestedFilename)
        var counter = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = (item.suggestedFilename as NSString).deletingPathExtension
            let ext = (item.suggestedFilename as NSString).pathExtension
            destination = folder.appending(path: "\(base) \(counter)" + (ext.isEmpty ? "" : ".\(ext)"))
            counter += 1
        }
        completion(destination)
    }

    func profile(_ profile: any Profile, didUpdateDownload item: DownloadItem) {
        downloads[item.id] = item
        statusText = "\(item.suggestedFilename): \(item.state) \(item.receivedBytes)/\(item.totalBytes.map(String.init) ?? "?")"
    }
}

/// Runs an engine `MenuModel` as an `NSMenu` and reports the choice once.
enum ContextMenuPresenter {
    static func present(_ model: MenuModel, at location: NSPoint, in view: NSView) {
        let target = Target(model: model)
        let menu = build(model.items, target: target)
        let point = view.isFlipped ? location : NSPoint(x: location.x, y: view.bounds.height - location.y)
        menu.popUp(positioning: nil, at: point, in: view)
        if model.isPending { model.cancel() }
    }

    private static func build(_ items: [MenuItem], target: Target) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            switch item.kind {
            case .separator:
                menu.addItem(.separator())
            case .submenu(let children):
                let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                entry.submenu = build(children, target: target)
                menu.addItem(entry)
            case .command, .checkbox, .radio:
                let entry = NSMenuItem(title: item.title, action: #selector(Target.choose(_:)), keyEquivalent: item.keyEquivalent)
                entry.keyEquivalentModifierMask = item.keyEquivalentModifiers
                entry.target = target
                entry.tag = item.id
                entry.isEnabled = item.isEnabled
                entry.state = item.isChecked ? .on : .off
                // The target must outlive the menu; NSMenuItem holds it weakly.
                entry.representedObject = target
                menu.addItem(entry)
            }
        }
        return menu
    }

    private final class Target: NSObject {
        let model: MenuModel
        init(model: MenuModel) { self.model = model }
        @objc func choose(_ sender: NSMenuItem) { model.select(sender.tag) }
    }
}
