import AppKit
import Engine
import FakeEngine

/// A UI delegate that records every call and answers with configurable values.
final class RecordingUIDelegate: WebContentsUIDelegate {
    enum Call: Equatable {
        case didCreate(targetURL: URL?, disposition: Disposition)
        case statusText(String?)
        case enterFullscreen(origin: URL?)
        case exitFullscreen
        case alert(String, origin: URL?)
        case confirm(String)
        case prompt(String, defaultText: String)
        case beforeUnload(isReload: Bool)
        case dialogsDismissed
        case permission([PermissionRequest], quietReason: PermissionQuietReason?)
        case permissionDismissed
        case auth(AuthChallenge)
        case certificate(CertificateError)
        case fileChooser(FileChooserRequest)
        case contextMenu(ContextMenuElement)
        case reservedKey(UInt16)
        case unhandledKey(UInt16)
        case consumedKey(KeyEventInfo)
        case audible(Bool)
        case muted(Bool)
        case security(SecurityState)
        case processGone(TerminationStatus)
        case didClose
    }

    private(set) var calls: [Call] = []
    private(set) var createdContents: [any WebContents] = []

    var keepsNewContents = true
    var confirmAnswer = true
    var promptAnswer: String? = "answer"
    var beforeUnloadAnswer = true
    var permissionAnswer = PermissionResponse.granted
    var credential: URLCredential? = URLCredential(user: "u", password: "p", persistence: .forSession)
    var proceedPastCertificateError = false
    var chosenFiles: [URL]? = [URL(filePath: "/tmp/a.txt")]
    /// When set, the delegate presents context menus and picks this command.
    var contextMenuChoice: MenuItem.ID?
    var reservedKeyCodes: Set<UInt16> = []
    var handlesUnhandledKeys = false

    func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?, disposition: Disposition) {
        calls.append(.didCreate(targetURL: targetURL, disposition: disposition))
        if keepsNewContents { createdContents.append(newContents) } else { newContents.close() }
    }
    func webContentsDidRequestEnterFullscreen(_ webContents: any WebContents, origin: URL?) {
        calls.append(.enterFullscreen(origin: origin))
    }
    func webContentsDidRequestExitFullscreen(_ webContents: any WebContents) {
        calls.append(.exitFullscreen)
    }
    func webContents(_ webContents: any WebContents, didChangeStatusText text: String?) {
        calls.append(.statusText(text))
    }
    func webContents(_ webContents: any WebContents, willShowContextMenu menu: MenuModel, for element: ContextMenuElement) -> Bool {
        calls.append(.contextMenu(element))
        guard let contextMenuChoice else { return false }
        menu.select(contextMenuChoice)
        return true
    }
    func webContents(_ webContents: any WebContents, runJavaScriptAlert message: String, origin: URL?, completion: @escaping () -> Void) {
        calls.append(.alert(message, origin: origin))
        completion()
    }
    func webContents(_ webContents: any WebContents, runJavaScriptConfirm message: String, origin: URL?, completion: @escaping (Bool) -> Void) {
        calls.append(.confirm(message))
        completion(confirmAnswer)
    }
    func webContents(_ webContents: any WebContents, runJavaScriptPrompt message: String, defaultText: String, origin: URL?, completion: @escaping (String?) -> Void) {
        calls.append(.prompt(message, defaultText: defaultText))
        completion(promptAnswer)
    }
    func webContents(_ webContents: any WebContents, runBeforeUnloadDialogForReload isReload: Bool, completion: @escaping (Bool) -> Void) {
        calls.append(.beforeUnload(isReload: isReload))
        completion(beforeUnloadAnswer)
    }
    func webContentsDidDismissJavaScriptDialogs(_ webContents: any WebContents) {
        calls.append(.dialogsDismissed)
    }
    func webContents(_ webContents: any WebContents, willAskForPermission requests: [PermissionRequest], quietReason: PermissionQuietReason?, completion: @escaping (PermissionResponse) -> Void) {
        calls.append(.permission(requests, quietReason: quietReason))
        completion(permissionAnswer)
    }
    func webContentsDidDismissPermissionPrompt(_ webContents: any WebContents) {
        calls.append(.permissionDismissed)
    }
    func webContents(_ webContents: any WebContents, didReceiveAuthChallenge challenge: AuthChallenge, completion: @escaping (URLCredential?) -> Void) {
        calls.append(.auth(challenge))
        completion(credential)
    }
    func webContents(_ webContents: any WebContents, didFailCertificateCheck error: CertificateError, completion: @escaping (Bool) -> Void) {
        calls.append(.certificate(error))
        completion(proceedPastCertificateError)
    }
    func webContents(_ webContents: any WebContents, runFileChooser request: FileChooserRequest, completion: @escaping ([URL]?) -> Void) {
        calls.append(.fileChooser(request))
        completion(chosenFiles)
    }
    func webContents(_ webContents: any WebContents, isReservedKeyEvent event: NSEvent) -> Bool {
        guard reservedKeyCodes.contains(event.keyCode) else { return false }
        calls.append(.reservedKey(event.keyCode))
        return true
    }
    func webContents(_ webContents: any WebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        calls.append(.unhandledKey(event.keyCode))
        return handlesUnhandledKeys
    }
    func webContents(_ webContents: any WebContents, didConsumeKey key: KeyEventInfo) {
        calls.append(.consumedKey(key))
    }
    func webContents(_ webContents: any WebContents, didChangeAudible isAudible: Bool) {
        calls.append(.audible(isAudible))
    }
    func webContents(_ webContents: any WebContents, didChangeMuted isMuted: Bool) {
        calls.append(.muted(isMuted))
    }
    func webContents(_ webContents: any WebContents, didChangeSecurityState state: SecurityState) {
        calls.append(.security(state))
    }
    func webContents(_ webContents: any WebContents, processGone status: TerminationStatus) {
        calls.append(.processGone(status))
    }
    func webContentsDidClose(_ webContents: any WebContents) {
        calls.append(.didClose)
    }
}

/// A navigation delegate that records actions and answers from a closure.
final class RecordingNavigationDelegate: NavigationDelegate {
    private(set) var actions: [NavigationAction] = []
    private(set) var commits: [(url: URL, transition: PageTransition)] = []
    var decide: (NavigationAction) -> Disposition = { $0.disposition }

    func webContents(_ webContents: any WebContents, decidePolicyFor action: NavigationAction) -> Disposition {
        actions.append(action)
        return decide(action)
    }

    func webContents(_ webContents: any WebContents, didCommitNavigation url: URL, transition: PageTransition) {
        commits.append((url, transition))
    }
}

final class RecordingDownloadsDelegate: DownloadsDelegate {
    var destination: URL? = URL(filePath: "/tmp/downloads/file.zip")
    private(set) var began: [DownloadItem] = []
    private(set) var updates: [DownloadItem] = []

    func profile(_ profile: any Profile, willBeginDownload item: DownloadItem, completion: @escaping (URL?) -> Void) {
        began.append(item)
        completion(destination)
    }

    func profile(_ profile: any Profile, didUpdateDownload item: DownloadItem) {
        updates.append(item)
    }
}

/// An initialized fake engine with one profile.
func makeProfile(name: String = "Default") throws -> (FakeApplication, FakeProfile) {
    let app = FakeApplication()
    try app.initialize(EngineConfiguration(userDataDirectory: URL(filePath: "/tmp/room-tests")))
    return (app, try app.profile(named: name))
}

func url(_ string: String) -> URL {
    URL(string: string)!
}

func keyDown(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = .command) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters,
        isARepeat: false,
        keyCode: keyCode
    )!
}
