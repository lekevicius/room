import AppKit
import Chrome
import Engine
import Observation
import UIKitCore

/// The page presentation the tab controller hands on: the page's prompts,
/// context menus and file choosers through `chrome` (Chrome package, Phase
/// 2.6a), the reserved-key routing, the status text and the profile's
/// downloads (their UI is 2.6b).
@Observable
final class PageUIDelegate {
    @ObservationIgnored let host: PageHost
    /// Dialogs, permission prompts, auth, certificate errors, context menus,
    /// file choosers, the crashed-page view.
    @ObservationIgnored let chrome = PageChrome()
    /// Element fullscreen (2.6b).
    @ObservationIgnored var fullscreen: PageFullscreen?
    /// The selected page's status text (link hover), for the debug panel.
    var statusText: String?
    /// Every key the engine reported as reserved or unhandled, for the keyboard spike.
    @ObservationIgnored private(set) var keyLog: [String] = []
    @ObservationIgnored private(set) var downloads: [DownloadItem.ID: DownloadItem] = [:]

    init(host: PageHost) {
        self.host = host
    }

    private func logKey(_ kind: String, _ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        keyLog.append("\(kind) keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "") flags=\(flags.rawValue)")
    }
}

// MARK: - UI delegate

extension PageUIDelegate: WebContentsUIDelegate {
    func webContents(_ webContents: any WebContents, didChangeStatusText text: String?) {
        statusText = text
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

    // The page's prompts, menus and file choosers (ROADMAP 2.6 task 2) live in `chrome`.

    func webContents(_ webContents: any WebContents, willShowContextMenu menu: MenuModel, for element: ContextMenuElement) -> Bool {
        chrome.webContents(webContents, willShowContextMenu: menu, for: element)
    }

    func webContents(_ webContents: any WebContents, runJavaScriptAlert message: String, origin: URL?, completion: @escaping () -> Void) {
        chrome.webContents(webContents, runJavaScriptAlert: message, origin: origin, completion: completion)
    }

    func webContents(_ webContents: any WebContents, runJavaScriptConfirm message: String, origin: URL?, completion: @escaping (Bool) -> Void) {
        chrome.webContents(webContents, runJavaScriptConfirm: message, origin: origin, completion: completion)
    }

    func webContents(_ webContents: any WebContents, runJavaScriptPrompt message: String, defaultText: String, origin: URL?, completion: @escaping (String?) -> Void) {
        chrome.webContents(webContents, runJavaScriptPrompt: message, defaultText: defaultText, origin: origin, completion: completion)
    }

    func webContents(_ webContents: any WebContents, runBeforeUnloadDialogForReload isReload: Bool, completion: @escaping (Bool) -> Void) {
        chrome.webContents(webContents, runBeforeUnloadDialogForReload: isReload, completion: completion)
    }

    func webContentsDidDismissJavaScriptDialogs(_ webContents: any WebContents) {
        chrome.webContentsDidDismissJavaScriptDialogs(webContents)
    }

    func webContents(_ webContents: any WebContents, willAskForPermission requests: [PermissionRequest], quietReason: PermissionQuietReason?, completion: @escaping (PermissionResponse) -> Void) {
        chrome.webContents(webContents, willAskForPermission: requests, quietReason: quietReason, completion: completion)
    }

    func webContentsDidDismissPermissionPrompt(_ webContents: any WebContents) {
        chrome.webContentsDidDismissPermissionPrompt(webContents)
    }

    func webContents(_ webContents: any WebContents, didReceiveAuthChallenge challenge: AuthChallenge, completion: @escaping (URLCredential?) -> Void) {
        chrome.webContents(webContents, didReceiveAuthChallenge: challenge, completion: completion)
    }

    func webContents(_ webContents: any WebContents, didFailCertificateCheck error: CertificateError, completion: @escaping (Bool) -> Void) {
        chrome.webContents(webContents, didFailCertificateCheck: error, completion: completion)
    }

    func webContents(_ webContents: any WebContents, runFileChooser request: FileChooserRequest, completion: @escaping ([URL]?) -> Void) {
        chrome.webContents(webContents, runFileChooser: request, completion: completion)
    }

    func webContentsDidClose(_ webContents: any WebContents) {
        chrome.webContentsDidClose(webContents)
        fullscreen?.exit(webContents)
    }

    func webContents(_ webContents: any WebContents, processGone status: TerminationStatus) {
        chrome.webContents(webContents, processGone: status)
        fullscreen?.exit(webContents)
    }

    func webContentsDidRequestEnterFullscreen(_ webContents: any WebContents, origin: URL?) {
        fullscreen?.enter(webContents, shown: host.contents)
    }

    func webContentsDidRequestExitFullscreen(_ webContents: any WebContents) {
        fullscreen?.exit(webContents)
    }
}

// MARK: - Downloads

extension PageUIDelegate: DownloadsDelegate {
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
