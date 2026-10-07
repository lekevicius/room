import AppKit

/// Chromium's extension system for one profile (Phase 3.6a): the installed
/// extensions with their actions, management with the host's consent
/// (uninstall asks the delegate first; installs from the Chrome Web Store
/// ask it for the permissions), unpacked loads, the options and management
/// pages the host opens as tabs, the pinned order, and update checks that
/// run only when the host asks, and (3.6b) the action popups the host shows
/// in a popover. RoomCore: `ExtensionRegistry`, `ExtensionRegistrar`,
/// `ExtensionActionManager`, `ToolbarActionsModel`, `ExtensionUpdater`,
/// `ExtensionViewHost`; without an engine `Profile.extensions` is `nil`.
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

    // MARK: Site access and commands (Phase 4.5)

    /// What the extension may do on `page`'s site (RoomCore:
    /// `PermissionsManager::GetUserSiteAccess`, `GetSiteAccess`,
    /// `CanAffectExtension`, `CanUserSelectSiteAccess`, and
    /// `ExtensionActionRunner::WantsToRun` for the page); `nil` for an
    /// unknown extension or a page without a URL.
    func siteAccess(for page: any WebContents, extension id: InstalledExtension.ID) -> ExtensionSiteAccess?
    /// The user's site access for the extension on `host` (every scheme and
    /// port of it), as Chrome's site-access menu sets it (RoomCore:
    /// `ScriptingPermissionsModifier` as `SitePermissionsHelper::UpdateSiteAccess`
    /// does; pages of that host run what was blocked, or lose activeTab on
    /// "on click"). `false` when the extension cannot take `access` there.
    @discardableResult
    func setSiteAccess(_ access: ExtensionSiteAccess.Level, for id: InstalledExtension.ID, host: String) -> Bool
    /// The site panel's Run for an extension that `wantsToRun` on `page`
    /// (RoomCore: `ExtensionActionRunner::RunAction(extension, true)`: the
    /// activeTab grant runs the blocked scripts, no popup); `false` when it
    /// had nothing waiting.
    @discardableResult
    func runAction(for id: InstalledExtension.ID, in page: any WebContents) -> Bool
    /// The extension's keyboard commands with their current keys (RoomCore:
    /// `CommandService::GetNamedCommands` and `GetExtensionActionCommand`,
    /// active, any scope), the action's first.
    func commands(for id: InstalledExtension.ID) -> [ExtensionCommand]
    /// Runs a command as its key would (B-70: the host's key router asks this
    /// while the keyboard is in the sidebar or the palette): `_execute_action`
    /// clicks the action for `page`, a named command sends `commands.onCommand`
    /// with `page` as the tab (RoomCore: the window's keybinding registry);
    /// `false` when the extension has no such command.
    @discardableResult
    func performCommand(_ name: String, for id: InstalledExtension.ID, in page: (any WebContents)?) -> Bool

    // MARK: Incognito (Phase 4.8b)

    /// Whether the extension runs in the profile's off-the-record twin
    /// ("Allow in incognito"; the host applies `Settings.extensionsInIncognito`
    /// when it makes the twin and when the setting changes). RoomCore:
    /// `extensions::util::SetIsIncognitoEnabled` (the engine reloads an
    /// enabled extension for the change); the twin's pages, popups and
    /// commands offer only the allowed ones.
    func setAllowedInIncognito(_ allowed: Bool, extension id: InstalledExtension.ID)
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
    /// Where its files are (4.5: Settings ▸ Extensions shows the size on disk);
    /// `nil` when the engine does not say.
    public var directory: URL?

    public init(id: ID, name: String, version: String = "1.0", summary: String = "", icon16: NSImage? = nil,
                icon32: NSImage? = nil, isEnabled: Bool = true, isUnpacked: Bool = false, isFromWebStore: Bool = false,
                action: ExtensionActionState? = nil, isPinned: Bool = false, optionsPageURL: URL? = nil,
                permissionMessages: [String] = [], hostPermissions: [String] = [], directory: URL? = nil) {
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
        self.directory = directory
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

/// An extension's access to one site (Phase 4.5), as Chrome's site-access
/// menu shows it.
public struct ExtensionSiteAccess: Equatable, Sendable {
    /// Chrome's `PermissionsManager::UserSiteAccess`.
    public enum Level: Int, CaseIterable, Hashable, Sendable {
        /// Runs on the site only when the user clicks it (or Run).
        case onClick
        /// Always runs on this site.
        case onSite
        /// Runs on every site it asks for.
        case onAllSites
    }

    public var level: Level
    /// The levels the user can choose here (`CanUserSelectSiteAccess`).
    public var selectable: Set<Level>
    /// The extension asks for this site (its host permissions or content
    /// scripts match it, or it has activeTab): the site panel lists it.
    public var wantsSite: Bool
    /// Its site access can be changed (not policy-installed, asks for hosts).
    public var canAffect: Bool
    /// Something of it is blocked on the page (a content script, a request):
    /// Run would run it.
    public var wantsToRun: Bool

    public init(level: Level, selectable: Set<Level> = Set(Level.allCases), wantsSite: Bool = true, canAffect: Bool = true,
                wantsToRun: Bool = false) {
        self.level = level
        self.selectable = selectable
        self.wantsSite = wantsSite
        self.canAffect = canAffect
        self.wantsToRun = wantsToRun
    }

    /// What Settings and the site panel call each level.
    public static func title(_ level: Level) -> String {
        switch level {
        case .onClick: "On click"
        case .onSite: "On this site"
        case .onAllSites: "On all sites"
        }
    }
}

/// One keyboard command of an extension (Phase 4.5), with its current key.
public struct ExtensionCommand: Identifiable, Equatable, Sendable {
    /// The action's command: a press clicks the action.
    public static let executeAction = "_execute_action"

    /// The manifest's name (`_execute_action` for the action's).
    public var name: String
    public var description: String
    /// The key in Room's notation ("⇧⌘U"; `ShortcutTable`'s strings), or ""
    /// when the user cleared it or Room cannot name the key.
    public var shortcut: String
    /// `_execute_action` (or a Manifest V2 browser/page action's).
    public var isAction: Bool
    public var id: String { name }

    public init(name: String, description: String = "", shortcut: String = "", isAction: Bool? = nil) {
        self.name = name
        self.description = description
        self.shortcut = shortcut
        self.isAction = isAction ?? (name == Self.executeAction)
    }

    /// Chrome's accelerator text ("Command+Shift+U", "Ctrl+Alt+Comma",
    /// `Command::AcceleratorToString` on macOS: Ctrl is ⌃, Command ⌘) in
    /// Room's notation ("⇧⌘U"); "" for a key Room's table cannot name (media
    /// keys, Home, Insert …) or no key.
    public static func shortcut(fromChrome text: String) -> String {
        let parts = text.split(separator: "+").map(String.init)
        guard parts.count >= 2, let key = parts.last else { return "" }
        var control = false, option = false, shift = false, command = false
        for modifier in parts.dropLast() {
            switch modifier {
            case "Ctrl", "MacCtrl": control = true
            case "Alt": option = true
            case "Shift": shift = true
            case "Command", "Search": command = true
            default: return ""
            }
        }
        let name: String
        switch key {
        case "Comma": name = ","
        case "Period": name = "."
        case "Up": name = "↑"
        case "Down": name = "↓"
        case "Left": name = "←"
        case "Right": name = "→"
        case "Space": name = "Space"
        case "Tab": name = "Tab"
        default:
            guard key.count == 1, let scalar = key.unicodeScalars.first, scalar.isASCII,
                  CharacterSet.alphanumerics.contains(scalar) else { return "" }
            name = key.uppercased()
        }
        return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + name
    }
}
