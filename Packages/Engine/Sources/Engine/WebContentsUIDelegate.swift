import AppKit

/// Everything Chrome would draw for a page: dialogs, prompts, menus, new
/// windows, status text. The engine never shows UI of its own for these.
///
/// Every member has a default implementation (the engine's "no UI" behavior:
/// dialogs dismissed, prompts denied, keys passed to the main menu), so a
/// delegate implements only what it presents. Completion handlers must be
/// called exactly once, on the main thread.
@MainActor
public protocol WebContentsUIDelegate: AnyObject {
    // MARK: New contents and fullscreen

    /// The page opened a new window (`window.open`, `target=_blank`, a
    /// middle-click). The delegate must keep `newContents` alive (put it in a
    /// tab, popup or Peek) or call `close()` on it.
    func webContents(
        _ webContents: any WebContents,
        didCreate newContents: any WebContents,
        targetURL: URL?,
        disposition: Disposition
    )
    /// The page asked for element fullscreen (video, `requestFullscreen()`).
    func webContentsDidRequestEnterFullscreen(_ webContents: any WebContents, origin: URL?)
    func webContentsDidRequestExitFullscreen(_ webContents: any WebContents)

    // MARK: Status and menus

    /// Hovered-link URL or page status; `nil` clears the status pill.
    func webContents(_ webContents: any WebContents, didChangeStatusText text: String?)
    /// Return `true` if the delegate presents `menu` itself (and later calls
    /// `menu.select` or `menu.cancel`); `false` lets the engine show its own.
    func webContents(
        _ webContents: any WebContents,
        willShowContextMenu menu: MenuModel,
        for element: ContextMenuElement
    ) -> Bool

    // MARK: JavaScript dialogs

    func webContents(
        _ webContents: any WebContents,
        runJavaScriptAlert message: String,
        origin: URL?,
        completion: @escaping () -> Void
    )
    func webContents(
        _ webContents: any WebContents,
        runJavaScriptConfirm message: String,
        origin: URL?,
        completion: @escaping (Bool) -> Void
    )
    /// `completion(nil)` cancels the prompt.
    func webContents(
        _ webContents: any WebContents,
        runJavaScriptPrompt message: String,
        defaultText: String,
        origin: URL?,
        completion: @escaping (String?) -> Void
    )
    /// `completion(true)` leaves (or reloads) the page.
    func webContents(
        _ webContents: any WebContents,
        runBeforeUnloadDialogForReload isReload: Bool,
        completion: @escaping (Bool) -> Void
    )
    /// The engine dismissed pending dialogs on its own (navigation, close).
    /// Their completions must no longer be called.
    func webContentsDidDismissJavaScriptDialogs(_ webContents: any WebContents)

    // MARK: Permissions, auth, certificates, files

    /// One prompt for one origin, possibly covering several permissions
    /// (camera + microphone). `quietReason` is set when Chromium would show
    /// the quiet (non-modal) UI.
    func webContents(
        _ webContents: any WebContents,
        willAskForPermission requests: [PermissionRequest],
        quietReason: PermissionQuietReason?,
        completion: @escaping (PermissionResponse) -> Void
    )
    /// The engine withdrew the pending permission prompt (navigation, close).
    func webContentsDidDismissPermissionPrompt(_ webContents: any WebContents)
    /// HTTP or proxy authentication. `completion(nil)` cancels.
    func webContents(
        _ webContents: any WebContents,
        didReceiveAuthChallenge challenge: AuthChallenge,
        completion: @escaping (URLCredential?) -> Void
    )
    /// `completion(true)` proceeds to the site despite the error.
    func webContents(
        _ webContents: any WebContents,
        didFailCertificateCheck error: CertificateError,
        completion: @escaping (Bool) -> Void
    )
    /// `<input type=file>` and `showOpenFilePicker`. `completion(nil)` cancels.
    func webContents(
        _ webContents: any WebContents,
        runFileChooser request: FileChooserRequest,
        completion: @escaping ([URL]?) -> Void
    )

    // MARK: Keyboard

    /// Called before the page sees a key-down. Return `true` to keep it from
    /// the page (reserved shortcuts such as ⌘T, ⌘L, ⌘W); the engine then
    /// sends it to the main menu.
    func webContents(_ webContents: any WebContents, isReservedKeyEvent event: NSEvent) -> Bool
    /// The page did not handle a key event. Return `true` if the delegate
    /// handled it; the default sends it to the main menu once.
    func webContents(_ webContents: any WebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool
    /// The page handled (called `preventDefault()` on) a key event.
    func webContents(_ webContents: any WebContents, didConsumeKey key: KeyEventInfo)

    // MARK: Page state notifications

    func webContents(_ webContents: any WebContents, didChangeAudible isAudible: Bool)
    func webContents(_ webContents: any WebContents, didChangeMuted isMuted: Bool)
    func webContents(_ webContents: any WebContents, didChangeSecurityState state: SecurityState)
    /// The renderer died. The page shows nothing until reloaded.
    func webContents(_ webContents: any WebContents, processGone status: TerminationStatus)
    /// `close()` finished, or the page closed itself (`window.close()`).
    func webContentsDidClose(_ webContents: any WebContents)
}

public extension WebContentsUIDelegate {
    func webContents(_ webContents: any WebContents, didCreate newContents: any WebContents, targetURL: URL?, disposition: Disposition) {
        newContents.close()
    }
    func webContentsDidRequestEnterFullscreen(_ webContents: any WebContents, origin: URL?) {}
    func webContentsDidRequestExitFullscreen(_ webContents: any WebContents) {}
    func webContents(_ webContents: any WebContents, didChangeStatusText text: String?) {}
    func webContents(_ webContents: any WebContents, willShowContextMenu menu: MenuModel, for element: ContextMenuElement) -> Bool {
        false
    }
    func webContents(_ webContents: any WebContents, runJavaScriptAlert message: String, origin: URL?, completion: @escaping () -> Void) {
        completion()
    }
    func webContents(_ webContents: any WebContents, runJavaScriptConfirm message: String, origin: URL?, completion: @escaping (Bool) -> Void) {
        completion(false)
    }
    func webContents(_ webContents: any WebContents, runJavaScriptPrompt message: String, defaultText: String, origin: URL?, completion: @escaping (String?) -> Void) {
        completion(nil)
    }
    func webContents(_ webContents: any WebContents, runBeforeUnloadDialogForReload isReload: Bool, completion: @escaping (Bool) -> Void) {
        completion(true)
    }
    func webContentsDidDismissJavaScriptDialogs(_ webContents: any WebContents) {}
    func webContents(_ webContents: any WebContents, willAskForPermission requests: [PermissionRequest], quietReason: PermissionQuietReason?, completion: @escaping (PermissionResponse) -> Void) {
        completion(.dismissed)
    }
    func webContentsDidDismissPermissionPrompt(_ webContents: any WebContents) {}
    func webContents(_ webContents: any WebContents, didReceiveAuthChallenge challenge: AuthChallenge, completion: @escaping (URLCredential?) -> Void) {
        completion(nil)
    }
    func webContents(_ webContents: any WebContents, didFailCertificateCheck error: CertificateError, completion: @escaping (Bool) -> Void) {
        completion(false)
    }
    func webContents(_ webContents: any WebContents, runFileChooser request: FileChooserRequest, completion: @escaping ([URL]?) -> Void) {
        completion(nil)
    }
    func webContents(_ webContents: any WebContents, isReservedKeyEvent event: NSEvent) -> Bool {
        false
    }
    func webContents(_ webContents: any WebContents, handleUnhandledKeyEvent event: NSEvent) -> Bool {
        NSApp?.mainMenu?.performKeyEquivalent(with: event) ?? false
    }
    func webContents(_ webContents: any WebContents, didConsumeKey key: KeyEventInfo) {}
    func webContents(_ webContents: any WebContents, didChangeAudible isAudible: Bool) {}
    func webContents(_ webContents: any WebContents, didChangeMuted isMuted: Bool) {}
    func webContents(_ webContents: any WebContents, didChangeSecurityState state: SecurityState) {}
    func webContents(_ webContents: any WebContents, processGone status: TerminationStatus) {}
    func webContentsDidClose(_ webContents: any WebContents) {}
}

/// Context-menu target: what was under the pointer.
nonisolated public struct ContextMenuElement: Sendable, Hashable {
    public enum MediaType: Sendable, Hashable {
        case none, image, video, audio, canvas, file, plugin
    }

    /// In the web contents' `nativeView` coordinates (flipped, top-left origin).
    public var location: NSPoint
    public var pageURL: URL?
    public var frameURL: URL?
    public var linkURL: URL?
    public var linkText: String?
    /// `src` of the image/media element.
    public var sourceURL: URL?
    public var mediaType: MediaType
    public var selectionText: String?
    public var isEditable: Bool
    public var misspelledWord: String?
    public var dictionarySuggestions: [String]

    public init(
        location: NSPoint,
        pageURL: URL? = nil,
        frameURL: URL? = nil,
        linkURL: URL? = nil,
        linkText: String? = nil,
        sourceURL: URL? = nil,
        mediaType: MediaType = .none,
        selectionText: String? = nil,
        isEditable: Bool = false,
        misspelledWord: String? = nil,
        dictionarySuggestions: [String] = []
    ) {
        self.location = location
        self.pageURL = pageURL
        self.frameURL = frameURL
        self.linkURL = linkURL
        self.linkText = linkText
        self.sourceURL = sourceURL
        self.mediaType = mediaType
        self.selectionText = selectionText
        self.isEditable = isEditable
        self.misspelledWord = misspelledWord
        self.dictionarySuggestions = dictionarySuggestions
    }
}

/// A context menu the engine built for a page. The presenter shows `items`
/// and reports the outcome exactly once with `select(_:)` or `cancel()`.
@MainActor
public final class MenuModel {
    public let items: [MenuItem]
    private var handler: ((MenuItem.ID?) -> Void)?

    /// `handler` receives the chosen command id, or `nil` when cancelled.
    public init(items: [MenuItem], handler: @escaping (MenuItem.ID?) -> Void) {
        self.items = items
        self.handler = handler
    }

    /// `false` once `select` or `cancel` was called.
    public var isPending: Bool { handler != nil }

    public func select(_ id: MenuItem.ID) {
        finish(id)
    }

    public func cancel() {
        finish(nil)
    }

    /// Finds an item at any depth.
    public func item(withID id: MenuItem.ID) -> MenuItem? {
        MenuItem.find(id, in: items)
    }

    private func finish(_ id: MenuItem.ID?) {
        guard let handler else { return }
        self.handler = nil
        handler(id)
    }
}

/// One context-menu row.
nonisolated public struct MenuItem: Sendable, Hashable, Identifiable {
    /// The engine's command id (Chromium `IDC_*`, CEF `MENU_ID_*`).
    public typealias ID = Int

    public enum Kind: Sendable, Hashable {
        case command
        case checkbox
        case radio(group: Int)
        case separator
        case submenu([MenuItem])
    }

    public var id: ID
    public var kind: Kind
    public var title: String
    public var isEnabled: Bool
    public var isChecked: Bool
    /// Key equivalent shown in the menu (characters, as `NSMenuItem` takes them).
    public var keyEquivalent: String
    public var keyEquivalentModifiers: NSEvent.ModifierFlags

    public init(
        id: ID,
        kind: Kind = .command,
        title: String,
        isEnabled: Bool = true,
        isChecked: Bool = false,
        keyEquivalent: String = "",
        keyEquivalentModifiers: NSEvent.ModifierFlags = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.keyEquivalent = keyEquivalent
        self.keyEquivalentModifiers = keyEquivalentModifiers
    }

    public static func separator() -> MenuItem {
        MenuItem(id: -1, kind: .separator, title: "")
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(kind)
        hasher.combine(title)
        hasher.combine(isEnabled)
        hasher.combine(isChecked)
        hasher.combine(keyEquivalent)
        hasher.combine(keyEquivalentModifiers.rawValue)
    }

    static func find(_ id: ID, in items: [MenuItem]) -> MenuItem? {
        for item in items {
            if item.id == id, item.kind != .separator { return item }
            if case .submenu(let children) = item.kind, let match = find(id, in: children) {
                return match
            }
        }
        return nil
    }
}

/// HTTP or proxy authentication request.
nonisolated public struct AuthChallenge: Sendable, Hashable {
    /// Scheme, host and port asking for credentials.
    public var origin: URL
    public var realm: String?
    /// `Basic`, `Digest`, `NTLM`, …
    public var scheme: String
    public var isProxy: Bool

    public init(origin: URL, realm: String? = nil, scheme: String, isProxy: Bool = false) {
        self.origin = origin
        self.realm = realm
        self.scheme = scheme
        self.isProxy = isProxy
    }
}

/// A TLS certificate problem on a navigation.
nonisolated public struct CertificateError: Sendable, Hashable {
    public var url: URL
    /// Chromium `net::Error` code, e.g. -202 `ERR_CERT_AUTHORITY_INVALID`.
    public var code: Int
    public var description: String
    /// DER-encoded certificate chain, leaf first.
    public var certificateChain: [Data]
    /// `false` for HSTS hosts and other errors that must not be bypassed.
    public var isOverridable: Bool

    public init(url: URL, code: Int, description: String, certificateChain: [Data] = [], isOverridable: Bool) {
        self.url = url
        self.code = code
        self.description = description
        self.certificateChain = certificateChain
        self.isOverridable = isOverridable
    }
}

/// A page asking the user to pick files.
nonisolated public struct FileChooserRequest: Sendable, Hashable {
    public enum Mode: Sendable, Hashable {
        case open, openMultiple, openFolder, save
    }

    public var mode: Mode
    public var title: String?
    public var defaultPath: URL?
    /// MIME types (`image/*`) and extensions (`.pdf`) from the `accept` attribute.
    public var acceptTypes: [String]

    public init(mode: Mode, title: String? = nil, defaultPath: URL? = nil, acceptTypes: [String] = []) {
        self.mode = mode
        self.title = title
        self.defaultPath = defaultPath
        self.acceptTypes = acceptTypes
    }
}

/// A key event the renderer handled.
nonisolated public struct KeyEventInfo: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        case keyDown, keyUp, character
    }

    /// macOS virtual key code (`kVK_*`).
    public var keyCode: UInt16
    public var modifiers: NSEvent.ModifierFlags
    public var phase: Phase

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, phase: Phase) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.phase = phase
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
        hasher.combine(phase)
    }
}

/// Why a renderer process went away.
nonisolated public enum TerminationStatus: Sendable, Hashable {
    case normal
    case abnormal
    case killed
    case crashed
    case outOfMemory
    case launchFailed
    case integrityFailure
}
