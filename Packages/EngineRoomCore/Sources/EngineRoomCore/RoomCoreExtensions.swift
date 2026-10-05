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

    /// `ExtensionAction` for the page's tab id (or the defaults).
    public func action(for id: InstalledExtension.ID, in webContents: (any WebContents)?) -> ExtensionActionState? {
        let page = (webContents as? RoomCoreWebContents)?.page
        return extensions.action(forExtension: id, webContents: page).map(ExtensionActionState.init)
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

    // MARK: RoomProfileExtensionsDelegate

    public func profileExtensionsDidChange(_ extensions: RoomProfileExtensions) {
        delegate?.extensionsDidChange(self)
    }

    public func profileExtensions(_ extensions: RoomProfileExtensions, didUpdateActionOfExtension identifier: String,
                                  webContents: RoomWebContents?) {
        delegate?.extensions(self, didUpdateActionOf: identifier, in: webContents.flatMap { profile?.contents(for: $0) })
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
                  permissionMessages: item.permissionMessages, hostPermissions: item.hostPermissions)
    }
}

extension ExtensionActionState {
    init(_ action: RoomExtensionAction) {
        self.init(title: action.title, badgeText: action.badgeText, badgeBackgroundColor: action.badgeBackgroundColor,
                  badgeTextColor: action.badgeTextColor, icon: action.icon, isEnabled: action.isEnabled,
                  hasPopup: action.hasPopup)
    }
}
