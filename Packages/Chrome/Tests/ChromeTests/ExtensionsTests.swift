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
                        opened: @escaping (URL) -> Void = { _ in }) -> (ExtensionsCenter, () -> Date?) {
    var stored = lastCheck
    let center = ExtensionsCenter(consent: consent, openTab: opened, lastUpdateCheck: { stored },
                                  setLastUpdateCheck: { stored = $0 }, clock: { time.now }, schedule: time.schedule)
    return (center, { stored })
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

    @Test("Options and the management page open as tabs")
    @MainActor func pagesAsTabs() {
        let time = ManualTime()
        var opened: [URL] = []
        let (center, _) = makeCenter(time, opened: { opened.append($0) })
        let options = URL(string: "chrome-extension://abc/options.html")!
        let engine = FakeProfileExtensions(installed: [InstalledExtension(id: "abc", name: "Fixture", optionsPageURL: options)])
        center.add(profile: UUID(), name: "Personal", extensions: engine)
        let section = center.sections[0]
        center.openOptions(section.installed[0], in: section)
        center.openManagementPage(in: section)
        #expect(opened == [options, URL(string: "chrome://extensions/")!])
    }
}
