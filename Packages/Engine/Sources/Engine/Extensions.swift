import AppKit

/// Chromium's extension system for one profile (Phase 3.6a): the installed
/// extensions with their actions, management with the host's consent
/// (uninstall asks the delegate first; installs from the Chrome Web Store
/// ask it for the permissions), unpacked loads, the options and management
/// pages the host opens as tabs, the pinned order, and update checks that
/// run only when the host asks, and (3.6b) the action popups the host shows
/// in a popover. RoomCore: `ExtensionRegistry`, `ExtensionRegistrar`,
/// `ExtensionActionManager`, `ToolbarActionsModel`, `ExtensionUpdater`,
/// `ExtensionViewHost`; CEF: none (`Profile.extensions` is `nil`).
@MainActor public protocol ProfileExtensions: AnyObject {
    /// Hears list changes, action changes and the consent questions. Held weakly.
    var delegate: (any ProfileExtensionsDelegate)? { get set }
    /// Every installed extension (enabled or not), pinned first in their
    /// order, then by name. A new value after every `extensionsDidChange`.
    var installed: [InstalledExtension] { get }
    /// The engine has loaded the installed extensions (`installed` is complete).
    var isReady: Bool { get }

    func setEnabled(_ enabled: Bool, extension id: InstalledExtension.ID)
    /// Reloads an extension (an unpacked one re-reads its folder).
    func reload(_ id: InstalledExtension.ID)
    /// Asks the delegate's `willUninstall` first; `true` once it is removed,
    /// `false` when the host said no (or nobody could be asked).
    func uninstall(_ id: InstalledExtension.ID) async -> Bool
    /// Loads an unpacked extension from a folder; its id.
    func loadUnpacked(at directory: URL) async throws -> InstalledExtension.ID
    /// The extension's options page, for the host to open as a tab.
    func optionsPageURL(for id: InstalledExtension.ID) -> URL?
    /// The engine's own management page (`chrome://extensions`), opened as a tab.
    var managementPageURL: URL { get }
    /// Pins or unpins the action (the header shows pinned actions, 3.6b).
    func setPinned(_ pinned: Bool, extension id: InstalledExtension.ID)
    /// The action as `webContents` shows it (badges are per page), or its defaults.
    func action(for id: InstalledExtension.ID, in webContents: (any WebContents)?) -> ExtensionActionState?
    /// A click on the action's button for `page` (3.6b; RoomCore: Chrome's
    /// `ExtensionActionRunner::RunAction` with tab permissions, then
    /// `ExtensionViewHostFactory::CreatePopupHost`): `true` when the
    /// action's popup is opening, and `didOpenPopup` follows once its page
    /// loaded; an action without a popup gets `action.onClicked`. A click
    /// while that action's popup shows closes it. Side panels are not
    /// supported (an action set to open one does nothing).
    func openPopup(extensionID id: InstalledExtension.ID, in page: any WebContents) -> Bool
    /// The host's popover closed (focus loss, Esc): the engine destroys the
    /// popup's page; `popupDidClose` follows.
    func closePopup(_ popup: any WebContents)
    /// One update check for every installed extension: the only way an
    /// extension update check reaches the network (the engine's own
    /// schedule is off). Updates found install when the extension is idle.
    func checkForUpdates() async -> ExtensionUpdateCheck
}

/// Receives a profile's extension changes and answers its consent questions.
@MainActor public protocol ProfileExtensionsDelegate: AnyObject {
    func extensionsDidChange(_ extensions: any ProfileExtensions)
    /// An action's title, badge, icon or state changed for one page (`nil`: every page).
    func extensions(_ extensions: any ProfileExtensions, didUpdateActionOf id: InstalledExtension.ID,
                    in webContents: (any WebContents)?)
    /// Before an uninstall: the host shows its consent; `false` keeps the extension.
    func extensions(_ extensions: any ProfileExtensions, willUninstall installed: InstalledExtension,
                    completion: @escaping (Bool) -> Void)
    /// An install (the Web Store's "Add to Chrome") or new permissions want
    /// the user's consent: the host shows the permissions; `false` cancels.
    func extensions(_ extensions: any ProfileExtensions, willInstall request: ExtensionInstallRequest,
                    completion: @escaping (Bool) -> Void)
    /// An action popup opened (3.6b): `popup` is its page, loaded, at the
    /// size its own layout asked for (`ExtensionPopupBounds`); `page` is the
    /// page the action ran for, whose window shows the popup in a popover on
    /// the action's button. After `openPopup`, the action's keyboard
    /// shortcut, or the extension's own `action.openPopup()`.
    func extensions(_ extensions: any ProfileExtensions, didOpenPopup popup: any WebContents,
                    for id: InstalledExtension.ID, in page: (any WebContents)?, preferredSize: CGSize)
    /// The popup's page changed its size (clamped to `ExtensionPopupBounds`).
    func extensions(_ extensions: any ProfileExtensions, popup: any WebContents, didResizeTo size: CGSize)
    /// The popup is gone (`closePopup`, `window.close()` or Esc in it, the
    /// window's page changed, the extension unloaded): close the popover.
    func extensions(_ extensions: any ProfileExtensions, popupDidClose popup: any WebContents)
}

public extension ProfileExtensionsDelegate {
    func extensionsDidChange(_ extensions: any ProfileExtensions) {}
    func extensions(_ extensions: any ProfileExtensions, didUpdateActionOf id: InstalledExtension.ID,
                    in webContents: (any WebContents)?) {}
    /// No answer is no consent.
    func extensions(_ extensions: any ProfileExtensions, willUninstall installed: InstalledExtension,
                    completion: @escaping (Bool) -> Void) { completion(false) }
    func extensions(_ extensions: any ProfileExtensions, willInstall request: ExtensionInstallRequest,
                    completion: @escaping (Bool) -> Void) { completion(false) }
    func extensions(_ extensions: any ProfileExtensions, didOpenPopup popup: any WebContents,
                    for id: InstalledExtension.ID, in page: (any WebContents)?, preferredSize: CGSize) {}
    func extensions(_ extensions: any ProfileExtensions, popup: any WebContents, didResizeTo size: CGSize) {}
    func extensions(_ extensions: any ProfileExtensions, popupDidClose popup: any WebContents) {}
}

/// An action popup's size bounds (Chrome's `ExtensionPopup::kMinSize`/`kMaxSize`).
public enum ExtensionPopupBounds {
    public static let minimum = CGSize(width: 25, height: 25)
    public static let maximum = CGSize(width: 800, height: 600)

    /// `size` within the bounds.
    public static func clamp(_ size: CGSize) -> CGSize {
        CGSize(width: min(max(size.width, minimum.width), maximum.width),
               height: min(max(size.height, minimum.height), maximum.height))
    }
}

/// One installed extension, as the engine last reported it.
public struct InstalledExtension: Identifiable, Equatable {
    public typealias ID = String
    public var id: ID
    public var name: String
    public var version: String
    public var summary: String
    /// The extension's icon at 16 and 32 pt; `nil` while loading.
    public var icon16: NSImage?
    public var icon32: NSImage?
    public var isEnabled: Bool
    /// Loaded from a folder: Reload re-reads it.
    public var isUnpacked: Bool
    public var isFromWebStore: Bool
    /// The action's defaults; `nil` for an extension without an action.
    public var action: ExtensionActionState?
    public var isPinned: Bool
    public var optionsPageURL: URL?
    /// What it may do, as the engine words it.
    public var permissionMessages: [String]
    /// The sites it can read and change, as match patterns (`<all_urls>`: every site).
    public var hostPermissions: [String]

    public init(id: ID, name: String, version: String = "1.0", summary: String = "", icon16: NSImage? = nil,
                icon32: NSImage? = nil, isEnabled: Bool = true, isUnpacked: Bool = false, isFromWebStore: Bool = false,
                action: ExtensionActionState? = nil, isPinned: Bool = false, optionsPageURL: URL? = nil,
                permissionMessages: [String] = [], hostPermissions: [String] = []) {
        self.id = id
        self.name = name
        self.version = version
        self.summary = summary
        self.icon16 = icon16
        self.icon32 = icon32
        self.isEnabled = isEnabled
        self.isUnpacked = isUnpacked
        self.isFromWebStore = isFromWebStore
        self.action = action
        self.isPinned = isPinned
        self.optionsPageURL = optionsPageURL
        self.permissionMessages = permissionMessages
        self.hostPermissions = hostPermissions
    }
}

/// An extension's action for one page or its defaults.
public struct ExtensionActionState: Equatable {
    public var title: String
    /// "" for none.
    public var badgeText: String
    /// `nil`: the engine's default colours.
    public var badgeBackgroundColor: NSColor?
    public var badgeTextColor: NSColor?
    public var icon: NSImage?
    public var isEnabled: Bool
    public var hasPopup: Bool

    public init(title: String, badgeText: String = "", badgeBackgroundColor: NSColor? = nil, badgeTextColor: NSColor? = nil,
                icon: NSImage? = nil, isEnabled: Bool = true, hasPopup: Bool = false) {
        self.title = title
        self.badgeText = badgeText
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeTextColor = badgeTextColor
        self.icon = icon
        self.isEnabled = isEnabled
        self.hasPopup = hasPopup
    }
}

/// What an install asks the user to allow.
public struct ExtensionInstallRequest {
    public enum Kind: Hashable, Sendable {
        case install
        /// An installed extension wants more permissions or is re-enabled.
        case permissions
    }

    public var id: InstalledExtension.ID
    public var name: String
    public var kind: Kind
    /// The engine's question, e.g. "Add “Dark Reader”?".
    public var title: String
    /// "It can:", or "" when it asks for nothing.
    public var permissionsHeading: String
    /// One line per permission.
    public var permissions: [String]
    /// Detail lines per permission (the same index).
    public var permissionDetails: [[String]]
    public var icon: NSImage?
    /// The page that asked (the Web Store's tab), when there is one.
    public weak var webContents: (any WebContents)?

    public init(id: InstalledExtension.ID, name: String, kind: Kind = .install, title: String? = nil,
                permissionsHeading: String = "", permissions: [String] = [], permissionDetails: [[String]] = [],
                icon: NSImage? = nil, webContents: (any WebContents)? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.title = title ?? "Add “\(name)”?"
        self.permissionsHeading = permissionsHeading
        self.permissions = permissions
        self.permissionDetails = permissionDetails
        self.icon = icon
        self.webContents = webContents
    }
}

/// What one update check did.
nonisolated public struct ExtensionUpdateCheck: Hashable, Sendable {
    /// A check ran (none when nothing is installed or the engine is not ready).
    public var checked: Bool
    /// Extensions asked about (unpacked ones are not).
    public var extensions: Int
    public var updatesFound: Int

    public init(checked: Bool, extensions: Int = 0, updatesFound: Int = 0) {
        self.checked = checked
        self.extensions = extensions
        self.updatesFound = updatesFound
    }
}

/// The engine could not load an unpacked extension.
nonisolated public struct ExtensionLoadError: Error, Hashable, Sendable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
