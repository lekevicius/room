import AppKit
import Engine
import Observation

/// The host's side of Chrome extensions (Phase 3.6a): every profile's
/// installed list for Settings ▸ Extensions, the consent sheets RoomCore asks
/// for (installing from the Web Store with the permission list, and every
/// uninstall), the options and management pages opened as tabs, and the
/// daily update check on the host's timer, which runs only while an extension
/// is installed (AGENTS.md: no request the user did not ask for; an installed
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
