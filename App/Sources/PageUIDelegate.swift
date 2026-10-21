import AppKit
import Chrome
import Engine
import Observation
import UIKitCore

/// The page presentation the tab controller hands on: the page's prompts,
/// context menus and file choosers through `chrome` (Chrome package, Phase
/// 2.6a), the reserved-key routing, the status text, element fullscreen and
/// the crashed-page view (2.6b). Downloads go to `DownloadsUI.list`.
@Observable
final class PageUIDelegate {
    @ObservationIgnored let host: PageHost
    /// Dialogs, permission prompts, auth, certificate errors, context menus,
    /// file choosers, the crashed-page view.
    @ObservationIgnored let chrome = PageChrome()
    /// Element fullscreen (2.6b).
    @ObservationIgnored var fullscreen: PageFullscreen?
    /// The selected page's status text (link hover).
    var statusText: String?
    /// The status pill follows it.
    @ObservationIgnored var onStatusText: ((String?) -> Void)?
    /// The window's toasts (the engine's notices, 3.4b); spikes read the one on screen.
    @ObservationIgnored weak var toasts: ToastCenter?
    /// A page closed (the find bar forgets its text).
    @ObservationIgnored var onPageClosed: ((any WebContents) -> Void)?
    /// The engine asked for the address field (Chromium's IDC_FOCUS_LOCATION, 3.5): the palette as ⌘L.
    @ObservationIgnored var onFocusLocationBar: ((any WebContents) -> Void)?
    /// How often the engine asked (the spike reads it).
    @ObservationIgnored private(set) var focusLocationBarRequests = 0
    /// Where the engine's own bubbles point (RoomCore's Views bubbles, 3.7a),
    /// in the window's coordinates: the site button, or the card's corner
    /// while the sidebar is hidden.
    @ObservationIgnored var bubbleAnchor: (() -> CGRect?)?
    /// How often the engine asked where its bubbles point (the spikes read it).
    @ObservationIgnored private(set) var bubbleAnchorQueries = 0
    /// The last keys the engine reported as reserved, unhandled or consumed, for the keyboard spike.
    @ObservationIgnored private(set) var keyLog: [String] = []
    /// Keys the page consumed so far (the keyboard spike counts them).
    @ObservationIgnored private(set) var consumedKeyCount = 0
    /// The keys the page never sees: the reserved actions' current keys
    /// (`ShortcutTable.reservedKeys`; 4.4a: they follow a remap).
    @ObservationIgnored var reservedKeys = Set(ReservedShortcuts.all)

    init(host: PageHost) {
        self.host = host
    }

    private func logKey(_ kind: String, _ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        appendKeyLog("\(kind) keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "") flags=\(flags.rawValue)")
    }

    private func appendKeyLog(_ line: String) {
        keyLog.append(line)
        if keyLog.count > 200 { keyLog.removeFirst(keyLog.count - 200) }
    }
}

// MARK: - UI delegate

extension PageUIDelegate: WebContentsUIDelegate {
    func webContents(_ webContents: any WebContents, didChangeStatusText text: String?) {
        statusText = text
        onStatusText?(text)
    }

    /// The engine's confirmation toasts (B-58): Chrome's copy commands get
    /// Room's toast; other kinds show nothing (Room has its own notices).
    func webContents(_ webContents: any WebContents, didRequestToast kind: ToastKind) {
        guard let toast = Self.toast(for: kind) else {
            NSLog("Room: the engine's toast %@ not shown", String(describing: kind))
            return
        }
        toasts?.show(toast)
    }

    static func toast(for kind: ToastKind) -> Toast? {
        switch kind {
        case .linkCopied: Toast(id: "copy-link", symbol: .copyURL, message: "Copied Link")
        case .imageCopied: Toast(id: "copy-image", symbol: .copied, message: "Copied Image")
        case .videoFrameCopied: Toast(id: "copy-video-frame", symbol: .copied, message: "Copied Video Frame")
        case .linkToHighlightCopied: Toast(id: "copy-link-to-highlight", symbol: .copyURL, message: "Copied Link to Highlight")
        case .other: nil
        }
    }

    func bubbleAnchorRect(for webContents: any WebContents) -> CGRect? {
        bubbleAnchorQueries += 1
        return bubbleAnchor?()
    }

    func webContentsDidRequestFocusOnLocationBar(_ webContents: any WebContents) {
        focusLocationBarRequests += 1
        NSLog("Room: the engine asked to focus the location bar (%ld)", focusLocationBarRequests)
        onFocusLocationBar?(webContents)
    }

    func webContents(_ webContents: any WebContents, isReservedKeyEvent event: NSEvent) -> Bool {
        let reserved = ReservedShortcuts.matches(event, in: reservedKeys)
        // RoomCore offers the event to the menu next, as a fresh copy when ⌥ changed its character
        // ("†" for ⌥⌘T: B-86, engine-side since 4.4b).
        if reserved { logKey("reserved", event) }
        return reserved
    }

    func webContents(_ webContents: any WebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        logKey("unhandled", event)
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return true }
        // The same as above for a page-first ⌥ key (⌥⌘P remapped onto Pin, 4.4a): a fresh copy matches.
        guard Self.optionChangedCharacter(event), let copy = Self.fresh(event) else { return false }
        let handled = NSApp.mainMenu?.performKeyEquivalent(with: copy) ?? false
        appendKeyLog("unhandled sent fresh handled=\(handled)")
        return handled
    }

    /// ⌥ produced another character than the key's ("π" for ⌥P).
    private static func optionChangedCharacter(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.modifierFlags.contains(.option)
            && event.characters?.lowercased() != event.charactersIgnoringModifiers?.lowercased()
    }

    private static func fresh(_ event: NSEvent) -> NSEvent? {
        NSEvent.keyEvent(with: event.type, location: event.locationInWindow, modifierFlags: event.modifierFlags, timestamp: event.timestamp,
                         windowNumber: event.windowNumber, context: nil, characters: event.characters ?? "",
                         charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "", isARepeat: event.isARepeat, keyCode: event.keyCode)
    }

    /// Nothing to do with a key the page used (RoomCore reports them from the
    /// input-event ack); logged for the keyboard spike only.
    func webContents(_ webContents: any WebContents, didConsumeKey key: KeyEventInfo) {
        let flags = key.modifiers.intersection([.command, .shift, .option, .control])
        consumedKeyCount += 1
        appendKeyLog("consumed keyCode=\(key.keyCode) phase=\(key.phase) flags=\(flags.rawValue)")
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
        onPageClosed?(webContents)
    }

    func webContents(_ webContents: any WebContents, processGone status: TerminationStatus) {
        chrome.webContents(webContents, processGone: status)
        fullscreen?.exit(webContents)
    }

    // The renderer, other applications, notices, capture (3.4b).

    func webContentsDidBecomeUnresponsive(_ webContents: any WebContents, completion: @escaping (UnresponsiveRendererAction) -> Void) {
        NSLog("Room: page unresponsive: %@", webContents.url?.absoluteString ?? "-")
        chrome.webContentsDidBecomeUnresponsive(webContents, completion: completion)
    }

    func webContentsDidBecomeResponsive(_ webContents: any WebContents) {
        NSLog("Room: page responsive again: %@", webContents.url?.absoluteString ?? "-")
        chrome.webContentsDidBecomeResponsive(webContents)
    }

    func webContents(_ webContents: any WebContents, shouldOpenExternalURL request: ExternalURLRequest, completion: @escaping (Bool) -> Void) {
        let asks = !chrome.externalApps.isAllowed(request.scheme)
        NSLog("Room: external URL %@ (%@)%@", request.url.absoluteString, request.applicationName, asks ? ", asking" : ", scheme already allowed")
        chrome.webContents(webContents, shouldOpenExternalURL: request) { open in
            NSLog("Room: external URL %@ %@", request.url.absoluteString, open ? "opened" : "blocked")
            completion(open)
        }
    }

    func webContents(_ webContents: any WebContents, didAddInfoBar infoBar: InfoBar) {
        NSLog("Room: notice added %d \"%@\" %@", infoBar.id, infoBar.message, "\(infoBar.kind)")
        chrome.webContents(webContents, didAddInfoBar: infoBar)
    }

    func webContents(_ webContents: any WebContents, didRemoveInfoBar infoBar: InfoBar) {
        NSLog("Room: notice removed %d", infoBar.id)
        chrome.webContents(webContents, didRemoveInfoBar: infoBar)
    }

    /// The row shows the indicator (`TabController.pageState`); logged here.
    func webContents(_ webContents: any WebContents, didChangeCaptureState state: CaptureState) {
        NSLog("Room: capture state %d (camera %d, microphone %d, screen %d) %@", state.rawValue, state.contains(.camera) ? 1 : 0,
              state.contains(.microphone) ? 1 : 0, state.isSharingScreen ? 1 : 0, webContents.url?.absoluteString ?? "-")
    }

    func webContentsDidRequestEnterFullscreen(_ webContents: any WebContents, origin: URL?) {
        fullscreen?.enter(webContents, shown: host.contents)
    }

    func webContentsDidRequestExitFullscreen(_ webContents: any WebContents) {
        fullscreen?.exit(webContents)
    }
}
