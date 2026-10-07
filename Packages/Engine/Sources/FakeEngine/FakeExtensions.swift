import AppKit
import Engine

/// An in-memory `ProfileExtensions` (Phase 3.6a) for host tests: a settable
/// list, the consent questions through the delegate as RoomCore asks them,
/// and the update checks counted.
public final class FakeProfileExtensions: ProfileExtensions {
    public weak var delegate: (any ProfileExtensionsDelegate)?
    /// Setting it tells the delegate, as the engine does after a change.
    public var installed: [InstalledExtension] = [] {
        didSet { delegate?.extensionsDidChange(self) }
    }
    public var isReady = true
    public let managementPageURL = URL(string: "chrome://extensions/")!
    /// Every `checkForUpdates` call's time (`now`), in order.
    public private(set) var updateChecks: [Date] = []
    /// What the next checks report as found.
    public var updatesFound = 0
    public var now: () -> Date = Date.init
    /// Folders `loadUnpacked` was given.
    public private(set) var loadedFolders: [URL] = []
    /// Actions per extension and page (`ObjectIdentifier` of the page; `nil` key: defaults).
    public var actions: [InstalledExtension.ID: ExtensionActionState] = [:]

    /// The profile popups' pages belong to (set by `FakeProfile.fakeExtensions`).
    weak var profile: FakeProfile?
    /// Every `openPopup` call: the extension and the page it was for.
    public private(set) var popupRequests: [(id: InstalledExtension.ID, page: ObjectIdentifier)] = []
    /// The popup the engine shows now (its extension and page), as RoomCore keeps one per window.
    public private(set) var openPopup: (id: InstalledExtension.ID, popup: FakeWebContents)?
    /// Popups the host closed through `closePopup`, in order.
    public private(set) var closedByHost: [ObjectIdentifier] = []
    /// The size the next popup's page asks for.
    public var popupSize = CGSize(width: 240, height: 80)

    public init(installed: [InstalledExtension] = []) {
        self.installed = installed
    }

    private func index(_ id: InstalledExtension.ID) -> Int? { installed.firstIndex { $0.id == id } }

    public func setEnabled(_ enabled: Bool, extension id: InstalledExtension.ID) {
        guard let index = index(id) else { return }
        installed[index].isEnabled = enabled
    }

    public func reload(_ id: InstalledExtension.ID) {
        guard index(id) != nil else { return }
        delegate?.extensionsDidChange(self)
    }

    /// RoomCore's rule: the delegate is asked first; no delegate, no removal.
    public func uninstall(_ id: InstalledExtension.ID) async -> Bool {
        guard let index = index(id), let delegate else { return false }
        let target = installed[index]
        let consent = await withCheckedContinuation { continuation in
            delegate.extensions(self, willUninstall: target) { continuation.resume(returning: $0) }
        }
        guard consent else { return false }
        installed.removeAll { $0.id == id }
        return true
    }

    public func loadUnpacked(at directory: URL) async throws -> InstalledExtension.ID {
        loadedFolders.append(directory)
        let id = "unpacked-\(loadedFolders.count)"
        installed.append(InstalledExtension(id: id, name: directory.lastPathComponent, isUnpacked: true))
        return id
    }

    public func optionsPageURL(for id: InstalledExtension.ID) -> URL? {
        installed.first { $0.id == id }?.optionsPageURL
    }

    /// RoomCore's order (`ToolbarActionsModel`): pinned first in their pinned
    /// order, a newly pinned action at the end of them; the rest by name.
    public func setPinned(_ pinned: Bool, extension id: InstalledExtension.ID) {
        guard let index = index(id), installed[index].isPinned != pinned else { return }
        var item = installed[index]
        item.isPinned = pinned
        var list = installed
        list.remove(at: index)
        let pinnedItems = list.filter(\.isPinned)
        let others = list.filter { !$0.isPinned }
        installed = pinned ? pinnedItems + [item] + others
            : pinnedItems + (others + [item]).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func action(for id: InstalledExtension.ID, in webContents: (any WebContents)?) -> ExtensionActionState? {
        actions[id] ?? installed.first { $0.id == id }?.action
    }

    /// RoomCore's rules: only an action with a popup opens one (the page is
    /// "loaded" at once: `didOpenPopup` before this returns); a click while
    /// that action's popup shows closes it.
    public func openPopup(extensionID id: InstalledExtension.ID, in page: any WebContents) -> Bool {
        popupRequests.append((id, ObjectIdentifier(page)))
        if let current = openPopup, current.id == id {
            simulatePopupClose()
            return false
        }
        guard action(for: id, in: page)?.hasPopup == true, let profile else { return false }
        if openPopup != nil { simulatePopupClose() }
        let popup = FakeWebContents(profile: profile, configuration: WebContentsConfiguration())
        openPopup = (id, popup)
        delegate?.extensions(self, didOpenPopup: popup, for: id, in: page, preferredSize: ExtensionPopupBounds.clamp(popupSize))
        return true
    }

    public func closePopup(_ popup: any WebContents) {
        guard let current = openPopup, current.popup === popup else { return }
        closedByHost.append(ObjectIdentifier(popup))
        simulatePopupClose()
    }

    /// The popup's page resized itself.
    public func simulatePopupResize(_ size: CGSize) {
        guard let current = openPopup else { return }
        delegate?.extensions(self, popup: current.popup, didResizeTo: ExtensionPopupBounds.clamp(size))
    }

    /// The engine closed the popup (`window.close()`, Esc, a tab switch).
    public func simulatePopupClose() {
        guard let current = openPopup else { return }
        openPopup = nil
        delegate?.extensions(self, popupDidClose: current.popup)
    }

    public func checkForUpdates() async -> ExtensionUpdateCheck {
        let asked = installed.filter { !$0.isUnpacked }.count
        guard isReady, asked > 0 else { return ExtensionUpdateCheck(checked: false) }
        updateChecks.append(now())
        return ExtensionUpdateCheck(checked: true, extensions: asked, updatesFound: updatesFound)
    }

    // MARK: Site access and commands (4.5)

    /// The user's site access per extension and host (`setSiteAccess`); a
    /// host without an entry has `defaultSiteAccess` (`.onAllSites`, as an
    /// extension is installed in Chrome).
    public private(set) var siteAccessByHost: [InstalledExtension.ID: [String: ExtensionSiteAccess.Level]] = [:]
    public var defaultSiteAccess: [InstalledExtension.ID: ExtensionSiteAccess.Level] = [:]
    /// The levels each extension can take (all three when unset).
    public var selectableSiteAccess: [InstalledExtension.ID: Set<ExtensionSiteAccess.Level>] = [:]
    /// Hosts each extension asks for (every host when unset).
    public var requestedHosts: [InstalledExtension.ID: Set<String>] = [:]
    /// What is blocked on a page (its content script waiting for Run), by extension.
    public private(set) var blocked: [InstalledExtension.ID: Set<ObjectIdentifier>] = [:]
    /// Pages the extension ran on after Run (`runAction`) or with access, in order.
    public private(set) var ranOn: [(id: InstalledExtension.ID, page: ObjectIdentifier)] = []
    /// Commands per extension (`commands(for:)`).
    public var commandsByExtension: [InstalledExtension.ID: [ExtensionCommand]] = [:]
    /// Every `performCommand` that reached a command: its name, extension and page.
    public private(set) var performedCommands: [(name: String, id: InstalledExtension.ID, page: ObjectIdentifier?)] = []

    private func host(of page: any WebContents) -> String? { page.url?.host() }

    public func siteAccess(for page: any WebContents, extension id: InstalledExtension.ID) -> ExtensionSiteAccess? {
        guard index(id) != nil, let host = host(of: page) else { return nil }
        let wants = requestedHosts[id].map { $0.contains(host) } ?? true
        return ExtensionSiteAccess(level: level(id, host: host), selectable: wants ? (selectableSiteAccess[id] ?? Set(ExtensionSiteAccess.Level.allCases)) : [],
                                   wantsSite: wants, canAffect: wants,
                                   wantsToRun: blocked[id]?.contains(ObjectIdentifier(page)) == true)
    }

    private func level(_ id: InstalledExtension.ID, host: String) -> ExtensionSiteAccess.Level {
        siteAccessByHost[id]?[host] ?? defaultSiteAccess[id] ?? .onAllSites
    }

    /// RoomCore's rule: only a level the extension can take; "on all sites"
    /// drops the per-host choices (the extension runs everywhere again).
    public func setSiteAccess(_ access: ExtensionSiteAccess.Level, for id: InstalledExtension.ID, host: String) -> Bool {
        guard index(id) != nil, requestedHosts[id].map({ $0.contains(host) }) ?? true,
              (selectableSiteAccess[id] ?? Set(ExtensionSiteAccess.Level.allCases)).contains(access) else { return false }
        if access == .onAllSites {
            siteAccessByHost[id] = nil
            defaultSiteAccess[id] = .onAllSites
        } else {
            siteAccessByHost[id, default: [:]][host] = access
        }
        return true
    }

    /// A page of `host` loaded: the extension's content script runs when it
    /// has access there, and waits for Run when it is "on click".
    public func simulatePageLoad(_ page: any WebContents, extension id: InstalledExtension.ID) {
        guard let host = host(of: page), requestedHosts[id].map({ $0.contains(host) }) ?? true else { return }
        if level(id, host: host) == .onClick {
            blocked[id, default: []].insert(ObjectIdentifier(page))
        } else {
            ranOn.append((id, ObjectIdentifier(page)))
        }
    }

    public func runAction(for id: InstalledExtension.ID, in page: any WebContents) -> Bool {
        guard blocked[id]?.remove(ObjectIdentifier(page)) != nil else { return false }
        ranOn.append((id, ObjectIdentifier(page)))
        return true
    }

    public func commands(for id: InstalledExtension.ID) -> [ExtensionCommand] {
        commandsByExtension[id] ?? []
    }

    /// `_execute_action` clicks the action (`openPopup`); a named command is recorded.
    public func performCommand(_ name: String, for id: InstalledExtension.ID, in page: (any WebContents)?) -> Bool {
        guard commands(for: id).contains(where: { $0.name == name }) else { return false }
        performedCommands.append((name, id, page.map(ObjectIdentifier.init)))
        if name == ExtensionCommand.executeAction, let page { _ = openPopup(extensionID: id, in: page) }
        return true
    }

    /// Extensions allowed in the off-the-record twin (`setAllowedInIncognito`).
    public private(set) var allowedInIncognito: Set<InstalledExtension.ID> = []

    public func setAllowedInIncognito(_ allowed: Bool, extension id: InstalledExtension.ID) {
        guard index(id) != nil else { return }
        if allowed { allowedInIncognito.insert(id) } else { allowedInIncognito.remove(id) }
    }

    /// An install asking for consent, as the Web Store's "Add to Chrome"
    /// does: the delegate answers; accepted, the extension is installed.
    @discardableResult
    public func simulateInstall(_ request: ExtensionInstallRequest) async -> Bool {
        guard let delegate else { return false }
        let consent = await withCheckedContinuation { continuation in
            delegate.extensions(self, willInstall: request) { continuation.resume(returning: $0) }
        }
        if consent, request.kind == .install, index(request.id) == nil {
            installed.append(InstalledExtension(id: request.id, name: request.name, isFromWebStore: true))
        }
        return consent
    }
}
