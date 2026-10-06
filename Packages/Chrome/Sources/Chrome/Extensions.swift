import AppKit
import Engine
import Observation

/// The host's side of Chrome extensions (Phase 3.6a): every profile's
/// installed list for Settings ▸ Extensions, the consent sheets RoomCore asks
/// for (installing from the Web Store with the permission list, and every
/// uninstall), the options and management pages opened as tabs, the
/// header's action buttons and their popups (3.6b), and the daily update
/// check on the host's timer, which runs only while an extension is
/// installed (AGENTS.md: no request the user did not ask for; an installed
/// extension's updates are one they did).
@Observable
public final class ExtensionsCenter: ProfileExtensionsDelegate {
    /// One profile's extensions.
    public struct ProfileSection: Identifiable {
        public let id: UUID
        public let name: String
        public let extensions: any ProfileExtensions
        public var installed: [InstalledExtension]
    }

    /// Profiles whose engine has an extension system, in the order added.
    public private(set) var sections: [ProfileSection] = []
    /// Every installed extension across profiles.
    public var installedCount: Int { sections.reduce(0) { $0 + $1.installed.count } }
    /// The last update check's result (Settings shows it).
    public private(set) var lastCheck: ExtensionUpdateCheck?
    /// Bumped on every action change (title, badge, icon) the engine reports,
    /// for any page; the header's action buttons observe it (3.6b).
    public private(set) var actionRevision = 0
    /// The last action change: the extension and whether it was for one page.
    @ObservationIgnored public private(set) var lastActionUpdate: (id: InstalledExtension.ID, perPage: Bool)?

    /// The action popup the host shows now (3.6b): one at a time, as Chrome's toolbar.
    public private(set) var shownPopup: ShownPopup?
    /// Shows the popups (App: a popover on the header's action button).
    @ObservationIgnored public weak var popupPresenter: (any ExtensionPopupPresenting)?

    /// An open action popup: its extension, its page, and whose extension system it belongs to.
    public struct ShownPopup {
        public let id: InstalledExtension.ID
        public let popup: any WebContents
        public let extensions: any ProfileExtensions
    }

    @ObservationIgnored private let consent: any ExtensionConsentPresenting
    @ObservationIgnored private let openTab: (URL) -> Void
    @ObservationIgnored private let updates: ExtensionUpdateTimer

    /// `lastUpdateCheck`/`setLastUpdateCheck` persist the time in Settings;
    /// `clock` and `schedule` are injected for the unit tests.
    public init(consent: any ExtensionConsentPresenting, openTab: @escaping (URL) -> Void,
                lastUpdateCheck: @escaping () -> Date?, setLastUpdateCheck: @escaping (Date) -> Void,
                clock: @escaping () -> Date = Date.init,
                schedule: @escaping ExtensionUpdateTimer.Schedule = ExtensionUpdateTimer.dispatchSchedule) {
        self.consent = consent
        self.openTab = openTab
        updates = ExtensionUpdateTimer(lastCheck: lastUpdateCheck, setLastCheck: setLastUpdateCheck, clock: clock,
                                       schedule: schedule)
        updates.check = { [weak self] in await self?.checkForUpdatesNow() ?? false }
    }

    /// A profile's extension system joins (at launch, once its engine profile exists).
    public func add(profile id: UUID, name: String, extensions: any ProfileExtensions) {
        guard !sections.contains(where: { $0.id == id }) else { return }
        extensions.delegate = self
        sections.append(ProfileSection(id: id, name: name, extensions: extensions, installed: extensions.installed))
        updates.installedCountChanged(installedCount)
    }

    /// A profile was renamed (4.4b): its section's title follows.
    public func rename(profile id: UUID, to name: String) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        let section = sections[index]
        sections[index] = ProfileSection(id: id, name: name, extensions: section.extensions, installed: section.installed)
    }

    /// A profile is being deleted (4.4b): its extensions leave the list (a
    /// popup of theirs closes first).
    public func remove(profile id: UUID) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        if let shown = shownPopup, shown.extensions === sections[index].extensions {
            shownPopup = nil
            popupPresenter?.closePopup(shown.popup)
            shown.extensions.closePopup(shown.popup)
        }
        sections.remove(at: index)
        updates.installedCountChanged(installedCount)
    }

    func section(of extensions: any ProfileExtensions) -> Int? {
        sections.firstIndex { $0.extensions === extensions }
    }

    // MARK: Actions (Settings ▸ Extensions)

    public func setEnabled(_ enabled: Bool, _ item: InstalledExtension, in section: ProfileSection) {
        section.extensions.setEnabled(enabled, extension: item.id)
    }

    public func reload(_ item: InstalledExtension, in section: ProfileSection) {
        section.extensions.reload(item.id)
    }

    /// The engine asks for consent (`willUninstall`), which shows the sheet.
    @discardableResult
    public func uninstall(_ item: InstalledExtension, in section: ProfileSection) async -> Bool {
        await section.extensions.uninstall(item.id)
    }

    public func loadUnpacked(at folder: URL, in section: ProfileSection) async throws {
        _ = try await section.extensions.loadUnpacked(at: folder)
    }

    /// The options page as a Today tab.
    public func openOptions(_ item: InstalledExtension, in section: ProfileSection) {
        guard let url = section.extensions.optionsPageURL(for: item.id) ?? item.optionsPageURL else { return }
        openTab(url)
    }

    /// `chrome://extensions` as a Today tab (Chrome's management page, the fallback of PLAN §7 risk 7).
    public func openManagementPage(in section: ProfileSection) {
        openTab(section.extensions.managementPageURL)
    }

    public func setPinned(_ pinned: Bool, _ item: InstalledExtension, in section: ProfileSection) {
        section.extensions.setPinned(pinned, extension: item.id)
    }

    // MARK: The header's action buttons and their popups (3.6b)

    /// The section of the profile `profile` (the active space's).
    public func section(profile: UUID?) -> ProfileSection? {
        sections.first { $0.id == profile }
    }

    /// The header's buttons for `profile`'s extensions as `page` shows them:
    /// pinned extensions with an action, in the pinned order (the installed
    /// list's own order: `ToolbarActionsModel`'s); unpinned ones are in the
    /// overflow menu (`overflowActions`, 4.5).
    public func headerActions(profile: UUID?, page: (any WebContents)?) -> [HeaderExtensionAction] {
        guard let section = section(profile: profile) else { return [] }
        return section.installed.compactMap { item in
            guard item.isPinned, item.isEnabled else { return nil }
            return headerAction(item, section: section, page: page)
        }
    }

    /// The overflow menu's items (4.5): enabled extensions with an action
    /// that are not pinned, by name, as `page` shows their actions (badges).
    public func overflowActions(profile: UUID?, page: (any WebContents)?) -> [HeaderExtensionAction] {
        guard let section = section(profile: profile) else { return [] }
        return section.installed.compactMap { item in
            guard !item.isPinned, item.isEnabled, item.action != nil else { return nil }
            return headerAction(item, section: section, page: page)
        }
    }

    private func headerAction(_ item: InstalledExtension, section: ProfileSection, page: (any WebContents)?) -> HeaderExtensionAction? {
        guard let defaults = item.action else { return nil }
        let state = page.flatMap { section.extensions.action(for: item.id, in: $0) } ?? defaults
        return HeaderExtensionAction(id: item.id, name: item.name, title: state.title.isEmpty ? item.name : state.title,
                                     icon: state.icon ?? defaults.icon ?? item.icon16, badgeText: state.badgeText,
                                     badgeBackgroundColor: state.badgeBackgroundColor, badgeTextColor: state.badgeTextColor,
                                     isEnabled: state.isEnabled)
    }

    // MARK: Commands with the keyboard outside the page (4.5, B-70)

    /// The extension command of `profile` whose key is `shortcut` (Room's
    /// notation, "⇧⌘U"), if any: enabled extensions in the list's order, the
    /// action's command before named ones (the engine's own registry picks
    /// the first extension too).
    public func command(forShortcut shortcut: String, profile: UUID?) -> (id: InstalledExtension.ID, name: String)? {
        guard !shortcut.isEmpty, let section = section(profile: profile) else { return nil }
        for item in section.installed where item.isEnabled {
            if let command = section.extensions.commands(for: item.id).first(where: { $0.shortcut == shortcut }) {
                return (item.id, command.name)
            }
        }
        return nil
    }

    /// Runs the command whose key is `shortcut` for `page` (the key router
    /// asks this before the menu while the sidebar or the palette has the
    /// keyboard); `true` when an extension took it.
    @discardableResult
    public func performCommand(forShortcut shortcut: String, profile: UUID?, page: (any WebContents)?) -> Bool {
        guard let section = section(profile: profile), let match = command(forShortcut: shortcut, profile: profile) else { return false }
        return section.extensions.performCommand(match.name, for: match.id, in: page)
    }

    /// Every extension command across profiles with its key, for Settings ▸
    /// Shortcuts' read-only rows (the extension's name, the command's title).
    public func shortcutRows() -> [(extension: String, title: String, shortcut: String)] {
        var rows: [(extension: String, title: String, shortcut: String)] = []
        for section in sections {
            for item in section.installed where item.isEnabled {
                for command in section.extensions.commands(for: item.id) where !command.shortcut.isEmpty {
                    let title = command.isAction ? "Activate the extension" : (command.description.isEmpty ? command.name : command.description)
                    rows.append((item.name, title, command.shortcut))
                }
            }
        }
        return rows
    }

    // MARK: Site access (4.5)

    /// `item`'s access to `page`'s site, as the engine answers it.
    public func siteAccess(_ id: InstalledExtension.ID, profile: UUID?, page: any WebContents) -> ExtensionSiteAccess? {
        section(profile: profile)?.extensions.siteAccess(for: page, extension: id)
    }

    /// The extensions of `profile` that want `page`'s site (the site
    /// panel's Extensions section, B-30), with their access, in the list's order.
    public func extensionsWantingSite(profile: UUID?, page: any WebContents) -> [(item: InstalledExtension, access: ExtensionSiteAccess)] {
        guard let section = section(profile: profile) else { return [] }
        return section.installed.compactMap { item in
            guard item.isEnabled, let access = section.extensions.siteAccess(for: page, extension: item.id), access.wantsSite
            else { return nil }
            return (item, access)
        }
    }

    @discardableResult
    public func setSiteAccess(_ level: ExtensionSiteAccess.Level, _ id: InstalledExtension.ID, profile: UUID?, host: String) -> Bool {
        let done = section(profile: profile)?.extensions.setSiteAccess(level, for: id, host: host) ?? false
        if done { actionRevision += 1 }
        return done
    }

    /// The site panel's Run.
    @discardableResult
    public func runBlocked(_ id: InstalledExtension.ID, profile: UUID?, page: any WebContents) -> Bool {
        let done = section(profile: profile)?.extensions.runAction(for: id, in: page) ?? false
        if done { actionRevision += 1 }
        return done
    }

    /// A click on an action's button: the engine runs the action for `page`
    /// (its popup arrives through `didOpenPopup`); `true` when a popup is opening.
    @discardableResult
    public func runAction(_ id: InstalledExtension.ID, profile: UUID?, page: any WebContents) -> Bool {
        guard let section = section(profile: profile) else { return false }
        return section.extensions.openPopup(extensionID: id, in: page)
    }

    /// The popover closed on its own (focus loss, Esc, a click elsewhere):
    /// the engine is told, which destroys the popup's page.
    public func popoverDidClose(_ popup: any WebContents) {
        guard let shown = shownPopup, shown.popup === popup else { return }
        shownPopup = nil
        shown.extensions.closePopup(popup)
    }

    /// Every profile with an installed extension checks once; the time is kept.
    @discardableResult
    public func checkForUpdatesNow() async -> Bool {
        var total = ExtensionUpdateCheck(checked: false)
        for section in sections where !section.installed.isEmpty {
            let result = await section.extensions.checkForUpdates()
            total.checked = total.checked || result.checked
            total.extensions += result.extensions
            total.updatesFound += result.updatesFound
        }
        lastCheck = total
        return total.checked
    }

    // MARK: ProfileExtensionsDelegate

    public func extensionsDidChange(_ extensions: any ProfileExtensions) {
        guard let index = section(of: extensions) else { return }
        sections[index].installed = extensions.installed
        updates.installedCountChanged(installedCount)
    }

    public func extensions(_ extensions: any ProfileExtensions, didUpdateActionOf id: InstalledExtension.ID,
                           in webContents: (any WebContents)?) {
        lastActionUpdate = (id, webContents != nil)
        actionRevision += 1
    }

    public func extensions(_ extensions: any ProfileExtensions, didOpenPopup popup: any WebContents,
                           for id: InstalledExtension.ID, in page: (any WebContents)?, preferredSize: CGSize) {
        if let previous = shownPopup, previous.popup !== popup {
            shownPopup = nil
            popupPresenter?.closePopup(previous.popup)
        }
        shownPopup = ShownPopup(id: id, popup: popup, extensions: extensions)
        popupPresenter?.showPopup(popup, for: id, page: page, size: ExtensionPopupBounds.clamp(preferredSize))
    }

    public func extensions(_ extensions: any ProfileExtensions, popup: any WebContents, didResizeTo size: CGSize) {
        guard shownPopup?.popup === popup else { return }
        popupPresenter?.resizePopup(popup, to: ExtensionPopupBounds.clamp(size))
    }

    public func extensions(_ extensions: any ProfileExtensions, popupDidClose popup: any WebContents) {
        guard shownPopup?.popup === popup else { return }
        shownPopup = nil
        popupPresenter?.closePopup(popup)
    }

    public func extensions(_ extensions: any ProfileExtensions, willUninstall installed: InstalledExtension,
                           completion: @escaping (Bool) -> Void) {
        consent.confirmUninstall(installed, completion: completion)
    }

    public func extensions(_ extensions: any ProfileExtensions, willInstall request: ExtensionInstallRequest,
                           completion: @escaping (Bool) -> Void) {
        consent.confirmInstall(request, completion: completion)
    }

    #if DEBUG
    /// The update timer's next fire (spikes log it).
    public var debugNextUpdateCheck: Date? { updates.nextFire }
    #endif
}

/// A pinned extension's button in the header (3.6b), as the page shows its action.
public struct HeaderExtensionAction: Identifiable, Equatable {
    public var id: InstalledExtension.ID
    public var name: String
    /// The action's title (the tooltip); the extension's name when it set none.
    public var title: String
    public var icon: NSImage?
    /// "" for none.
    public var badgeText: String
    /// `nil`: the host's default badge colours.
    public var badgeBackgroundColor: NSColor?
    public var badgeTextColor: NSColor?
    /// `action.disable()` greys the button.
    public var isEnabled: Bool

    public init(id: InstalledExtension.ID, name: String, title: String, icon: NSImage? = nil, badgeText: String = "",
                badgeBackgroundColor: NSColor? = nil, badgeTextColor: NSColor? = nil, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.title = title
        self.icon = icon
        self.badgeText = badgeText
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeTextColor = badgeTextColor
        self.isEnabled = isEnabled
    }
}

/// Shows the action popups (App: an `NSPopover` on the header's action button).
public protocol ExtensionPopupPresenting: AnyObject {
    /// `popup`'s page at `size`, anchored on `id`'s button in the window that shows `page`.
    func showPopup(_ popup: any WebContents, for id: InstalledExtension.ID, page: (any WebContents)?, size: CGSize)
    func resizePopup(_ popup: any WebContents, to size: CGSize)
    /// The engine closed it: the popover goes without telling the engine again.
    func closePopup(_ popup: any WebContents)
}

/// The sheets that ask the user (App: `NSAlert` sheets on the key window).
public protocol ExtensionConsentPresenting: AnyObject {
    /// "Remove “X”?" — `true` removes.
    func confirmUninstall(_ installed: InstalledExtension, completion: @escaping (Bool) -> Void)
    /// "Add “X”?" with what it can do — `true` installs.
    func confirmInstall(_ request: ExtensionInstallRequest, completion: @escaping (Bool) -> Void)
}

/// When the next extension update check is due (ROADMAP 3.6a task 3): one a
/// day while an extension is installed, none while none is; the last check's
/// time is kept across launches so a relaunch does not check at once. An
/// install starts the day (the store just served the newest version).
public enum ExtensionUpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    /// `nil`: nothing installed, no check. Otherwise the due date (a past
    /// date means check now). `lastCheck == nil` with extensions installed
    /// (the first install, or a state from before 3.6a) starts the day now.
    public static func nextCheck(lastCheck: Date?, now: Date, installedCount: Int) -> Date? {
        guard installedCount > 0 else { return nil }
        guard let lastCheck else { return now.addingTimeInterval(interval) }
        // A clock set back far: never more than a day away.
        return min(lastCheck.addingTimeInterval(interval), now.addingTimeInterval(interval))
    }
}

/// Drives `ExtensionUpdateSchedule` with one pending timer: armed while an
/// extension is installed, cancelled when the last one goes.
public final class ExtensionUpdateTimer {
    /// Runs `fire` after `delay` seconds; the returned closure cancels it.
    public typealias Schedule = (_ delay: TimeInterval, _ fire: @escaping @MainActor () async -> Void) -> () -> Void

    var check: (() async -> Bool)?
    public private(set) var nextFire: Date?
    private let lastCheck: () -> Date?
    private let setLastCheck: (Date) -> Void
    private let clock: () -> Date
    private let schedule: Schedule
    private var cancel: (() -> Void)?
    private var installedCount = 0
    private var generation = 0

    init(lastCheck: @escaping () -> Date?, setLastCheck: @escaping (Date) -> Void, clock: @escaping () -> Date,
         schedule: @escaping Schedule) {
        self.lastCheck = lastCheck
        self.setLastCheck = setLastCheck
        self.clock = clock
        self.schedule = schedule
    }

    /// The real timer: a main-queue dispatch after `delay`.
    public static let dispatchSchedule: Schedule = { delay, fire in
        let item = DispatchWorkItem { Task { @MainActor in await fire() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return { item.cancel() }
    }

    func installedCountChanged(_ count: Int) {
        let wasEmpty = installedCount == 0
        installedCount = count
        if count == 0 {
            disarm()
        } else if wasEmpty || cancel == nil {
            arm()
        }
    }

    private func disarm() {
        cancel?()
        cancel = nil
        nextFire = nil
        generation += 1
    }

    private func arm() {
        disarm()
        let now = clock()
        if lastCheck() == nil {
            // The day starts with the first extension: no check at once.
            setLastCheck(now)
        }
        guard let due = ExtensionUpdateSchedule.nextCheck(lastCheck: lastCheck(), now: now, installedCount: installedCount)
        else { return }
        nextFire = due
        let current = generation
        cancel = schedule(max(0, due.timeIntervalSince(now))) { [weak self] in
            await self?.fire(generation: current)
        }
    }

    private func fire(generation current: Int) async {
        guard generation == current, installedCount > 0 else { return }
        cancel = nil
        _ = await check?()
        setLastCheck(clock())
        if installedCount > 0, cancel == nil { arm() }
    }
}
