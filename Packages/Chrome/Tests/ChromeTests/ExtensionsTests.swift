import Engine
import FakeEngine
import Foundation
import Testing
@testable import Chrome

/// A clock and a scheduler the tests drive (no sleeps, no wall clock).
@MainActor
private final class ManualTime {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// Pending timers: delay from the moment they were armed, and the fire.
    var timers: [(delay: TimeInterval, fire: @MainActor () async -> Void, cancelled: Bool)] = []
    var live: [Int] { timers.indices.filter { !timers[$0].cancelled } }

    var schedule: ExtensionUpdateTimer.Schedule {
        { [unowned self] delay, fire in
            self.timers.append((delay, fire, false))
            let index = self.timers.count - 1
            return { [weak self] in self?.timers[index].cancelled = true }
        }
    }

    /// Moves the clock to the live timer's deadline and fires it.
    func fireLive() async {
        guard let index = live.last else { return }
        now = now.addingTimeInterval(timers[index].delay)
        timers[index].cancelled = true
        await timers[index].fire()
    }
}

@MainActor
private final class Consent: ExtensionConsentPresenting {
    var answer = true
    var uninstallAsked: [String] = []
    var installAsked: [ExtensionInstallRequest] = []

    func confirmUninstall(_ installed: InstalledExtension, completion: @escaping (Bool) -> Void) {
        uninstallAsked.append(installed.id)
        completion(answer)
    }

    func confirmInstall(_ request: ExtensionInstallRequest, completion: @escaping (Bool) -> Void) {
        installAsked.append(request)
        completion(answer)
    }
}

@MainActor
private func makeCenter(_ time: ManualTime, lastCheck: Date? = nil, consent: Consent = Consent(),
                        opened: @escaping (URL, UUID) -> Void = { _, _ in }) -> (ExtensionsCenter, () -> Date?) {
    var stored = lastCheck
    let center = ExtensionsCenter(consent: consent, openTab: opened, lastUpdateCheck: { stored },
                                  setLastUpdateCheck: { stored = $0 }, clock: { time.now }, schedule: time.schedule)
    return (center, { stored })
}

/// The popover side the host would show (3.6b).
@MainActor
private final class Popovers: ExtensionPopupPresenting {
    var shown: [(id: String, popup: ObjectIdentifier, size: CGSize)] = []
    var resized: [CGSize] = []
    var closed: [ObjectIdentifier] = []

    func showPopup(_ popup: any WebContents, for id: InstalledExtension.ID, page: (any WebContents)?, size: CGSize) {
        shown.append((id, ObjectIdentifier(popup), size))
    }

    func resizePopup(_ popup: any WebContents, to size: CGSize) { resized.append(size) }
    func closePopup(_ popup: any WebContents) { closed.append(ObjectIdentifier(popup)) }
}

@Suite("Extensions: consent and the daily update check (ROADMAP 3.6a tasks 1–3)")
struct ExtensionsTests {
    @Test("Nothing installed: no timer, no check, no time written")
    @MainActor func nothingInstalled() async {
        let time = ManualTime()
        let (center, stored) = makeCenter(time)
        let engine = FakeProfileExtensions()
        center.add(profile: UUID(), name: "Personal", extensions: engine)
        #expect(time.live.isEmpty)
        #expect(stored() == nil)
        #expect(engine.updateChecks.isEmpty)
    }

    @Test("A renamed profile's section takes the name; a deleted one's leaves, its extensions no longer counted (4.4b)")
    @MainActor func renameAndRemove() {
        let time = ManualTime()
        let (center, _) = makeCenter(time)
        let personal = UUID(), work = UUID()
        let engine = FakeProfileExtensions()
        center.add(profile: personal, name: "Personal", extensions: FakeProfileExtensions())
        center.add(profile: work, name: "Work", extensions: engine)
        engine.installed = [InstalledExtension(id: "dark", name: "Dark Reader", isFromWebStore: true)]
        center.rename(profile: work, to: "Office")
        #expect(center.sections.map(\.name) == ["Personal", "Office"])
        #expect(center.installedCount == 1)
        center.remove(profile: work)
        #expect(center.sections.map(\.id) == [personal])
        #expect(center.installedCount == 0)
    }

    @Test("The first install starts the day: no check at once, one a day later, then daily")
    @MainActor func firstInstall() async {
        let time = ManualTime()
        let (center, stored) = makeCenter(time)
        let engine = FakeProfileExtensions()
        engine.now = { time.now }
        center.add(profile: UUID(), name: "Personal", extensions: engine)
        let installedAt = time.now
        engine.installed = [InstalledExtension(id: "dark", name: "Dark Reader", isFromWebStore: true)]
        #expect(engine.updateChecks.isEmpty)
        #expect(stored() == installedAt)
        #expect(time.live.count == 1)
        #expect(time.timers[time.live[0]].delay == ExtensionUpdateSchedule.interval)

        await time.fireLive()
        #expect(engine.updateChecks == [installedAt.addingTimeInterval(ExtensionUpdateSchedule.interval)])
        #expect(stored() == time.now)
        #expect(time.live.count == 1, "re-armed for the next day")
        #expect(time.timers[time.live[0]].delay == ExtensionUpdateSchedule.interval)
        #expect(center.lastCheck == ExtensionUpdateCheck(checked: true, extensions: 1, updatesFound: 0))
    }

    @Test("A relaunch inside the day does not check at once; an overdue one checks once")
    @MainActor func relaunch() async {
        let time = ManualTime()
        let installed = [InstalledExtension(id: "ubo", name: "uBlock Origin Lite", isFromWebStore: true)]

        let recent = time.now.addingTimeInterval(-23 * 3600)
        let (center, _) = makeCenter(time, lastCheck: recent)
        let engine = FakeProfileExtensions(installed: installed)
        center.add(profile: UUID(), name: "Personal", extensions: engine)
        #expect(engine.updateChecks.isEmpty)
        #expect(time.timers[time.live[0]].delay == 3600)

        let late = ManualTime()
        let (overdueCenter, _) = makeCenter(late, lastCheck: late.now.addingTimeInterval(-30 * 3600))
        let overdue = FakeProfileExtensions(installed: installed)
        overdueCenter.add(profile: UUID(), name: "Personal", extensions: overdue)
        #expect(late.timers[late.live[0]].delay == 0)
        await late.fireLive()
        #expect(overdue.updateChecks.count == 1)
    }

    @Test("The last extension removed cancels the timer; a stale fire checks nothing")
    @MainActor func lastRemoved() async {
        let time = ManualTime()
        let (center, _) = makeCenter(time)
        let engine = FakeProfileExtensions()
        center.add(profile: UUID(), name: "Personal", extensions: engine)
        engine.installed = [InstalledExtension(id: "dark", name: "Dark Reader", isFromWebStore: true)]
        let armed = time.timers.count - 1
        engine.installed = []
        #expect(time.live.isEmpty)
        await time.timers[armed].fire()
        #expect(engine.updateChecks.isEmpty)
    }

    @Test("Uninstall asks the host first: cancelled keeps the extension, confirmed removes it")
    @MainActor func uninstallConsent() async {
        let time = ManualTime()
        let consent = Consent()
        let (center, _) = makeCenter(time, consent: consent)
        let engine = FakeProfileExtensions(installed: [InstalledExtension(id: "op", name: "1Password", isFromWebStore: true)])
        center.add(profile: UUID(), name: "Personal", extensions: engine)
        let section = center.sections[0]

        consent.answer = false
        #expect(await center.uninstall(section.installed[0], in: section) == false)
        #expect(consent.uninstallAsked == ["op"])
        #expect(center.sections[0].installed.map(\.id) == ["op"])

        consent.answer = true
        #expect(await center.uninstall(section.installed[0], in: section) == true)
        #expect(consent.uninstallAsked == ["op", "op"])
        #expect(center.sections[0].installed.isEmpty)
    }

    @Test("Without a delegate the engine removes nothing (no consent, no uninstall)")
    @MainActor func uninstallWithoutDelegate() async {
        let engine = FakeProfileExtensions(installed: [InstalledExtension(id: "op", name: "1Password")])
        #expect(await engine.uninstall("op") == false)
        #expect(engine.installed.count == 1)
    }

    @Test("An install from the store shows the permissions; declined installs nothing")
    @MainActor func installConsent() async {
        let time = ManualTime()
        let consent = Consent()
        let (center, _) = makeCenter(time, consent: consent)
        let engine = FakeProfileExtensions()
        center.add(profile: UUID(), name: "Personal", extensions: engine)
        let request = ExtensionInstallRequest(id: "dark", name: "Dark Reader", permissionsHeading: "It can:",
                                              permissions: ["Read and change all your data on all websites"])
        consent.answer = false
        #expect(await engine.simulateInstall(request) == false)
        #expect(center.sections[0].installed.isEmpty)
        consent.answer = true
        #expect(await engine.simulateInstall(request) == true)
        #expect(consent.installAsked.map(\.permissions) == [request.permissions, request.permissions])
        #expect(center.sections[0].installed.map(\.id) == ["dark"])
    }

    @Test("Options, the management page and the shortcuts page open as tabs of the extension's profile")
    @MainActor func pagesAsTabs() {
        let time = ManualTime()
        var opened: [URL] = []
        var profiles: [UUID] = []
        let (center, _) = makeCenter(time, opened: { opened.append($0); profiles.append($1) })
        let options = URL(string: "chrome-extension://abc/options.html")!
        let engine = FakeProfileExtensions(installed: [InstalledExtension(id: "abc", name: "Fixture", optionsPageURL: options)])
        let work = UUID()
        center.add(profile: UUID(), name: "Personal", extensions: FakeProfileExtensions())
        center.add(profile: work, name: "Work", extensions: engine)
        let section = center.sections[1]
        center.openOptions(section.installed[0], in: section)
        center.openManagementPage(in: section)
        center.openShortcutsPage(in: section)
        #expect(opened == [options, URL(string: "chrome://extensions/")!, URL(string: "chrome://extensions/shortcuts")!])
        // B-67 (4.5): every page is for the extension's own profile, not the first one's.
        #expect(profiles == [work, work, work])
    }

    // MARK: 3.6b: the header's buttons and the popups

    /// A center with one fake profile whose page `page` the popups are for.
    @MainActor private func popupSetup(engine: FakeApplication, _ installed: [InstalledExtension]) throws
        -> (ExtensionsCenter, FakeProfileExtensions, Popovers, UUID, any WebContents) {
        try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        let profile = try engine.profile(named: "Personal")
        let extensions = FakeProfileExtensions(installed: installed)
        profile.fakeExtensions = extensions
        let (center, _) = makeCenter(ManualTime())
        let popovers = Popovers()
        center.popupPresenter = popovers
        let id = UUID()
        center.add(profile: id, name: "Personal", extensions: extensions)
        let page = try profile.createWebContents(WebContentsConfiguration())
        return (center, extensions, popovers, id, page)
    }

    @Test("The header shows pinned, enabled extensions with an action, in the pinned order; badges are the page's")
    @MainActor func headerFollowsPinnedOrder() throws {
        let application = FakeApplication()
        let popup = ExtensionActionState(title: "Popup", hasPopup: true)
        let (center, engine, _, profile, page) = try popupSetup(engine: application, [
            InstalledExtension(id: "b", name: "B", action: popup, isPinned: true),
            InstalledExtension(id: "a", name: "A", action: ExtensionActionState(title: ""), isPinned: true),
            InstalledExtension(id: "c", name: "C", action: popup, isPinned: false),
            InstalledExtension(id: "d", name: "D", isPinned: true),
            InstalledExtension(id: "e", name: "E", isEnabled: false, action: popup, isPinned: true),
        ])
        #expect(center.headerActions(profile: profile, page: page).map(\.id) == ["b", "a"])
        #expect(center.headerActions(profile: profile, page: page).map(\.title) == ["Popup", "A"])
        // Reordered or unpinned in the engine: the next refresh follows it.
        engine.installed = [engine.installed[1], engine.installed[0]]
        engine.setPinned(false, extension: "b")
        #expect(center.headerActions(profile: profile, page: page).map(\.id) == ["a"])
        engine.actions["a"] = ExtensionActionState(title: "A", badgeText: "3")
        #expect(center.headerActions(profile: profile, page: page).first?.badgeText == "3")
        #expect(center.headerActions(profile: UUID(), page: page).isEmpty)
    }

    @Test("A popover that loses focus tells the engine, which closes the popup; the presenter is not asked again")
    @MainActor func popoverFocusLossTellsEngine() throws {
        let application = FakeApplication()
        let (center, engine, popovers, profile, page) = try popupSetup(engine: application, [
            InstalledExtension(id: "x", name: "X", action: ExtensionActionState(title: "X", hasPopup: true), isPinned: true),
        ])
        engine.popupSize = CGSize(width: 2000, height: 10)
        #expect(center.runAction("x", profile: profile, page: page))
        #expect(popovers.shown.count == 1)
        #expect(popovers.shown.first?.size == CGSize(width: 800, height: 25))
        let popup = try #require(center.shownPopup?.popup)
        engine.simulatePopupResize(CGSize(width: 374, height: 266))
        #expect(popovers.resized == [CGSize(width: 374, height: 266)])
        center.popoverDidClose(popup)
        #expect(engine.closedByHost == [ObjectIdentifier(popup)])
        #expect(engine.openPopup == nil)
        #expect(center.shownPopup == nil)
        #expect(popovers.closed.isEmpty)
    }

    @Test("The engine closing a popup (window.close, Esc, a tab switch) closes the popover; a second click closes it too")
    @MainActor func engineCloseClosesPopover() throws {
        let application = FakeApplication()
        let (center, engine, popovers, profile, page) = try popupSetup(engine: application, [
            InstalledExtension(id: "x", name: "X", action: ExtensionActionState(title: "X", hasPopup: true), isPinned: true),
            InstalledExtension(id: "n", name: "N", action: ExtensionActionState(title: "N"), isPinned: true),
        ])
        #expect(center.runAction("x", profile: profile, page: page))
        let first = try #require(center.shownPopup?.popup)
        engine.simulatePopupClose()
        #expect(popovers.closed == [ObjectIdentifier(first)])
        #expect(center.shownPopup == nil)
        #expect(center.runAction("x", profile: profile, page: page))
        #expect(!center.runAction("x", profile: profile, page: page))
        #expect(popovers.closed.count == 2)
        // An action without a popup opens none (the engine sends onClicked).
        #expect(!center.runAction("n", profile: profile, page: page))
        #expect(popovers.shown.count == 2)
    }
}

// MARK: 4.5: pin/unpin and the overflow menu, commands, the site panel's section

@Suite("Extensions UX (ROADMAP 4.5)")
struct ExtensionsUXTests {
    @MainActor private func setUp(_ installed: [InstalledExtension]) throws
        -> (ExtensionsCenter, FakeProfileExtensions, UUID, FakeWebContents) {
        let application = FakeApplication()
        try application.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        let profile = try application.profile(named: "Personal")
        let extensions = FakeProfileExtensions(installed: installed)
        profile.fakeExtensions = extensions
        let center = ExtensionsCenter(consent: Consent(), openTab: { _, _ in }, lastUpdateCheck: { nil }, setLastUpdateCheck: { _ in },
                                      schedule: { _, _ in {} })
        let id = UUID()
        center.add(profile: id, name: "Personal", extensions: extensions)
        let page = profile.makeWebContents()
        page.load(URL(string: "http://127.0.0.1:8770/site.html")!, transition: .typed, fromAddressBar: true)
        return (center, extensions, id, page)
    }

    private static let action = ExtensionActionState(title: "Act", hasPopup: true)

    @Test("Unpinning moves an action to the overflow menu with its badge; pinning it again puts it at the header's end")
    @MainActor func pinUnpinReordersTheHeader() throws {
        let (center, engine, profile, page) = try setUp([
            InstalledExtension(id: "a", name: "A", action: Self.action, isPinned: true),
            InstalledExtension(id: "b", name: "B", action: Self.action, isPinned: true),
            InstalledExtension(id: "n", name: "No action", isPinned: false),
        ])
        #expect(center.headerActions(profile: profile, page: page).map(\.id) == ["a", "b"])
        #expect(center.overflowActions(profile: profile, page: page).isEmpty)
        let section = try #require(center.section(profile: profile))
        center.setPinned(false, section.installed[0], in: section)
        engine.actions["a"] = ExtensionActionState(title: "Act", badgeText: "T1", hasPopup: true)
        #expect(center.headerActions(profile: profile, page: page).map(\.id) == ["b"])
        #expect(center.overflowActions(profile: profile, page: page).map(\.id) == ["a"])
        #expect(center.overflowActions(profile: profile, page: page).first?.badgeText == "T1")
        let unpinned = try #require(center.section(profile: profile)?.installed.first { $0.id == "a" })
        center.setPinned(true, unpinned, in: try #require(center.section(profile: profile)))
        #expect(center.headerActions(profile: profile, page: page).map(\.id) == ["b", "a"])
        #expect(center.overflowActions(profile: profile, page: page).isEmpty)
    }

    @Test("A key that is an extension's command runs it for the page; another key is left to the menu")
    @MainActor func commandsByShortcut() throws {
        let (center, engine, profile, page) = try setUp([
            InstalledExtension(id: "a", name: "A", action: Self.action, isPinned: true),
            InstalledExtension(id: "off", name: "Off", isEnabled: false),
        ])
        engine.commandsByExtension["a"] = [ExtensionCommand(name: "_execute_action", shortcut: "⇧⌘Y"),
                                           ExtensionCommand(name: "room-named", description: "Named", shortcut: "⇧⌘U")]
        engine.commandsByExtension["off"] = [ExtensionCommand(name: "x", shortcut: "⇧⌘X")]
        #expect(center.command(forShortcut: "⇧⌘U", profile: profile)?.name == "room-named")
        #expect(center.performCommand(forShortcut: "⇧⌘U", profile: profile, page: page))
        #expect(engine.performedCommands.map(\.name) == ["room-named"])
        #expect(!center.performCommand(forShortcut: "⇧⌘X", profile: profile, page: page))
        #expect(!center.performCommand(forShortcut: "⇧⌘C", profile: profile, page: page))
        #expect(!center.performCommand(forShortcut: "⇧⌘U", profile: UUID(), page: page))
        #expect(center.shortcutRows().map(\.shortcut) == ["⇧⌘Y", "⇧⌘U"])
        #expect(center.shortcutRows().map(\.title) == ["Activate the extension", "Named"])
    }

    @Test("The site panel lists the extensions that want the site; Run runs the blocked one; On this site is kept")
    @MainActor func sitePanelSection() throws {
        let (center, engine, profile, page) = try setUp([
            InstalledExtension(id: "a", name: "A", action: Self.action, isPinned: true),
            InstalledExtension(id: "elsewhere", name: "Elsewhere"),
        ])
        engine.requestedHosts["elsewhere"] = ["example.com"]
        #expect(center.extensionsWantingSite(profile: profile, page: page).map(\.item.id) == ["a"])
        #expect(center.setSiteAccess(.onClick, "a", profile: profile, host: "127.0.0.1"))
        engine.simulatePageLoad(page, extension: "a")
        #expect(center.extensionsWantingSite(profile: profile, page: page).first?.access.wantsToRun == true)
        #expect(center.runBlocked("a", profile: profile, page: page))
        #expect(center.siteAccess("a", profile: profile, page: page)?.wantsToRun == false)
        #expect(center.setSiteAccess(.onSite, "a", profile: profile, host: "127.0.0.1"))
        engine.simulatePageLoad(page, extension: "a")
        #expect(center.siteAccess("a", profile: profile, page: page)?.level == .onSite)
        #expect(center.siteAccess("a", profile: profile, page: page)?.wantsToRun == false)
    }
}
