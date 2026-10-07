import AppKit
import Engine
import RoomCore

/// `ProfileExtensions` over `RoomProfileExtensions` (Chromium's extension
/// system for the profile, Phase 3.6a): the list from `ExtensionRegistry`,
/// management through `ExtensionRegistrar`, actions, the pinned order from
/// `ToolbarActionsModel`, the Web Store's install prompt and the uninstall
/// consent handed to the host's delegate, update checks only on request.
public final class RoomCoreExtensions: NSObject, ProfileExtensions, RoomProfileExtensionsDelegate {
    public weak var delegate: (any ProfileExtensionsDelegate)?
    let extensions: RoomProfileExtensions
    private weak var profile: RoomCoreProfile?
    /// The open popups' pages, by RoomCore's page (3.6b).
    private var popups: [ObjectIdentifier: RoomCoreWebContents] = [:]

    init(extensions: RoomProfileExtensions, profile: RoomCoreProfile) {
        self.extensions = extensions
        self.profile = profile
        super.init()
        // Always the delegate: RoomCore then hands every install prompt of
        // this profile to the host (never Chrome's dialog) and asks before
        // an uninstall.
        extensions.delegate = self
    }

    public var installed: [InstalledExtension] { extensions.extensions.map(InstalledExtension.init) }
    public var isReady: Bool { extensions.isReady }
    public var managementPageURL: URL { RoomProfileExtensions.managementPageURL }

    /// `ExtensionRegistrar::EnableExtension` / `DisableExtension(DISABLE_USER_ACTION)`.
    public func setEnabled(_ enabled: Bool, extension id: InstalledExtension.ID) {
        extensions.setEnabled(enabled, forExtension: id)
    }

    /// `ExtensionRegistrar::ReloadExtension`.
    public func reload(_ id: InstalledExtension.ID) {
        extensions.reloadExtension(id)
    }

    /// The delegate's consent, then `ExtensionRegistrar::UninstallExtension`.
    public func uninstall(_ id: InstalledExtension.ID) async -> Bool {
        await withCheckedContinuation { continuation in
            extensions.uninstallExtension(id) { continuation.resume(returning: $0) }
        }
    }

    /// `UnpackedInstaller::Load`.
    public func loadUnpacked(at directory: URL) async throws -> InstalledExtension.ID {
        let (id, error): (String?, String?) = await withCheckedContinuation { continuation in
            extensions.loadUnpacked(at: directory) { continuation.resume(returning: ($0, $1)) }
        }
        guard let id else { throw ExtensionLoadError(error ?? "The extension could not be loaded") }
        return id
    }

    /// `OptionsPageInfo::GetOptionsPage`.
    public func optionsPageURL(for id: InstalledExtension.ID) -> URL? {
        extensions.optionsPageURL(forExtension: id)
    }

    /// `ToolbarActionsModel::SetActionVisibility`.
    public func setPinned(_ pinned: Bool, extension id: InstalledExtension.ID) {
        extensions.setPinned(pinned, forExtension: id)
    }

    /// `extensions::util::SetIsIncognitoEnabled` (4.8b; Chrome reloads an
    /// enabled extension for the change).
    public func setAllowedInIncognito(_ allowed: Bool, extension id: InstalledExtension.ID) {
        extensions.setAllowedInIncognito(allowed, forExtension: id)
    }

    /// `extensions::util::IsIncognitoEnabled` (spikes read it).
    public func isAllowedInIncognito(_ id: InstalledExtension.ID) -> Bool {
        extensions.isAllowedInIncognito(id)
    }

    /// `ExtensionAction` for the page's tab id (or the defaults).
    public func action(for id: InstalledExtension.ID, in webContents: (any WebContents)?) -> ExtensionActionState? {
        let page = (webContents as? RoomCoreWebContents)?.page
        return extensions.action(forExtension: id, webContents: page).map(ExtensionActionState.init)
    }

    /// `ExtensionActionRunner::RunAction` (tab permissions), then the popup's
    /// `ExtensionViewHost` when the action has one (3.6b).
    public func openPopup(extensionID id: InstalledExtension.ID, in page: any WebContents) -> Bool {
        guard let page = (page as? RoomCoreWebContents)?.page else { return false }
        return extensions.openPopup(forExtension: id, webContents: page)
    }

    /// The host's popover closed: RoomCore destroys the `ExtensionViewHost`.
    public func closePopup(_ popup: any WebContents) {
        guard let page = (popup as? RoomCoreWebContents)?.page else { return }
        extensions.closePopup(page)
    }

    /// `ExtensionUpdater::CheckNow` inside RoomCore's update gate (patch 0025).
    public func checkForUpdates() async -> ExtensionUpdateCheck {
        await withCheckedContinuation { continuation in
            extensions.checkForUpdates { result in
                continuation.resume(returning: ExtensionUpdateCheck(checked: result.checked.boolValue, extensions: result.extensions,
                                                                    updatesFound: result.updatesFound))
            }
        }
    }

    // MARK: Site access and commands (4.5)

    /// `PermissionsManager` (`GetUserSiteAccess`, `GetSiteAccess`,
    /// `CanUserSelectSiteAccess`, `CanAffectExtension`) and
    /// `ExtensionActionRunner::WantsToRun` for the page.
    public func siteAccess(for page: any WebContents, extension id: InstalledExtension.ID) -> ExtensionSiteAccess? {
        guard let page = (page as? RoomCoreWebContents)?.page,
              let answer = extensions.siteAccess(forExtension: id, webContents: page) else { return nil }
        let level = (answer["level"] as? NSNumber).flatMap { ExtensionSiteAccess.Level(rawValue: $0.intValue) } ?? .onClick
        let selectable = Set(((answer["selectable"] as? [NSNumber]) ?? []).compactMap { ExtensionSiteAccess.Level(rawValue: $0.intValue) })
        return ExtensionSiteAccess(level: level, selectable: selectable,
                                   wantsSite: (answer["wantsSite"] as? NSNumber)?.boolValue ?? false,
                                   canAffect: (answer["canAffect"] as? NSNumber)?.boolValue ?? false,
                                   wantsToRun: (answer["wantsToRun"] as? NSNumber)?.boolValue ?? false)
    }

    /// `ScriptingPermissionsModifier` for "*://host/*", as Chrome's
    /// `SitePermissionsHelper::UpdateSiteAccess`.
    public func setSiteAccess(_ access: ExtensionSiteAccess.Level, for id: InstalledExtension.ID, host: String) -> Bool {
        guard let level = RoomExtensionSiteAccessLevel(rawValue: access.rawValue) else { return false }
        return extensions.setSiteAccess(level, forExtension: id, host: host)
    }

    /// `ExtensionActionRunner::RunAction(extension, true)` when it wants to run.
    public func runAction(for id: InstalledExtension.ID, in page: any WebContents) -> Bool {
        guard let page = (page as? RoomCoreWebContents)?.page else { return false }
        return extensions.runAction(forExtension: id, webContents: page)
    }

    /// `CommandService::GetExtensionActionCommand` and `GetNamedCommands`.
    public func commands(for id: InstalledExtension.ID) -> [ExtensionCommand] {
        extensions.commands(forExtension: id).map { command in
            ExtensionCommand(name: command["name"] as? String ?? "", description: command["description"] as? String ?? "",
                             shortcut: ExtensionCommand.shortcut(fromChrome: command["shortcut"] as? String ?? ""),
                             isAction: (command["isAction"] as? NSNumber)?.boolValue ?? false)
        }
    }

    /// The window's keybinding registry, as the command's key (B-70).
    public func performCommand(_ name: String, for id: InstalledExtension.ID, in page: (any WebContents)?) -> Bool {
        extensions.performCommand(name, forExtension: id, webContents: (page as? RoomCoreWebContents)?.page)
    }

    // MARK: RoomProfileExtensionsDelegate

    public func profileExtensionsDidChange(_ extensions: RoomProfileExtensions) {
        delegate?.extensionsDidChange(self)
    }

    public func profileExtensions(_ extensions: RoomProfileExtensions, didUpdateActionOfExtension identifier: String,
                                  webContents: RoomWebContents?) {
        delegate?.extensions(self, didUpdateActionOf: identifier, in: webContents.flatMap { profile?.contents(for: $0) })
    }

    public func profileExtensions(_ extensions: RoomProfileExtensions, didOpenPopup popup: RoomWebContents,
                                  forExtension identifier: String, webContents: RoomWebContents?, preferredSize size: NSSize) {
        // The popup's page is Chrome's (an ExtensionViewHost's), adopted
        // like the DevTools front-end (3.3b): no profile list, no tab strip.
        let contents = RoomCoreWebContents(page: popup, configuration: WebContentsConfiguration(), profile: nil)
        popups[ObjectIdentifier(popup)] = contents
        delegate?.extensions(self, didOpenPopup: contents, for: identifier, in: webContents.flatMap { profile?.contents(for: $0) },
                             preferredSize: size)
    }

    public func profileExtensions(_ extensions: RoomProfileExtensions, popup: RoomWebContents, didResizeTo size: NSSize) {
        guard let contents = popups[ObjectIdentifier(popup)] else { return }
        delegate?.extensions(self, popup: contents, didResizeTo: size)
    }

    public func profileExtensions(_ extensions: RoomProfileExtensions, popupDidClose popup: RoomWebContents) {
        guard let contents = popups.removeValue(forKey: ObjectIdentifier(popup)) else { return }
        delegate?.extensions(self, popupDidClose: contents)
    }

    public func profileExtensions(_ extensions: RoomProfileExtensions, willUninstall item: RoomExtension,
                                  completion: @escaping (Bool) -> Void) {
        guard let delegate else { return completion(false) }
        delegate.extensions(self, willUninstall: InstalledExtension(item), completion: completion)
    }

    public func profileExtensions(_ extensions: RoomProfileExtensions, willInstall request: RoomExtensionInstallRequest,
                                  completion: @escaping (Bool) -> Void) {
        guard let delegate else { return completion(false) }
        let kind: ExtensionInstallRequest.Kind = request.kind == .permissions ? .permissions : .install
        let value = ExtensionInstallRequest(
            id: request.identifier, name: request.name, kind: kind, title: request.title,
            permissionsHeading: request.permissionsHeading, permissions: request.permissions,
            permissionDetails: request.permissionDetails, icon: request.icon,
            webContents: request.webContents.flatMap { profile?.contents(for: $0) })
        delegate.extensions(self, willInstall: value, completion: completion)
    }
}

extension InstalledExtension {
    init(_ item: RoomExtension) {
        self.init(id: item.identifier, name: item.name, version: item.version, summary: item.summary,
                  icon16: item.icon16, icon32: item.icon32, isEnabled: item.isEnabled, isUnpacked: item.isUnpacked,
                  isFromWebStore: item.fromWebStore, action: item.action.map(ExtensionActionState.init),
                  isPinned: item.isPinned, optionsPageURL: item.optionsPageURL,
                  permissionMessages: item.permissionMessages, hostPermissions: item.hostPermissions,
                  directory: item.directory)
    }
}

extension ExtensionActionState {
    init(_ action: RoomExtensionAction) {
        self.init(title: action.title, badgeText: action.badgeText, badgeBackgroundColor: action.badgeBackgroundColor,
                  badgeTextColor: action.badgeTextColor, icon: action.icon, isEnabled: action.isEnabled,
                  hasPopup: action.hasPopup)
    }
}
