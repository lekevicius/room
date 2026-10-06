import AppKit
import Engine
import FakeEngine
import Testing

@Suite("Application and profiles")
struct ApplicationAndProfileTests {
    @Test func initializeOnce() throws {
        let app = FakeApplication()
        let configuration = EngineConfiguration(
            userDataDirectory: URL(filePath: "/tmp/room-tests"),
            features: EngineFeatures(enabled: ["BackForwardCache"], disabled: ["MemorySaver"])
        )
        try app.initialize(configuration)
        #expect(throws: EngineError.self) { try app.initialize(configuration) }
        #expect(app.features.isEnabled("BackForwardCache") == true)
        #expect(app.features.isEnabled("MemorySaver") == false)
        #expect(app.features.isEnabled("Other") == nil)
    }

    @Test func profilesNeedAnInitializedEngine() async {
        let app = FakeApplication()
        await #expect(throws: EngineError.notRunning) { _ = try await app.createProfile(name: "Default") }
    }

    @Test func createProfileReturnsTheLoadedOneForTheSameName() async throws {
        let (app, _) = try makeProfile(name: "Default")
        let work = try await app.createProfile(name: "Work")
        let again = try await app.createProfile(name: "Work")
        #expect(work === again)
        #expect(app.profiles.map(\.name) == ["Default", "Work"])
    }

    @Test(arguments: ["", "..", "a/b", "c:d"])
    func invalidProfileNames(_ name: String) async throws {
        let (app, _) = try makeProfile()
        await #expect(throws: EngineError.invalidProfileName(name)) { _ = try await app.createProfile(name: name) }
    }

    @Test func profilesHaveNoChromeOnlyCapabilities() throws {
        let (_, profile) = try makeProfile()
        let engineProfile: any Profile = profile
        #expect(engineProfile.history == nil)
        #expect(engineProfile.bookmarks == nil)
        #expect(engineProfile.extensions == nil)
        #expect(engineProfile.makeAutocompleteController() == nil)
    }

    @Test func createWebContentsThroughTheProtocol() throws {
        let (_, profile) = try makeProfile()
        let engineProfile: any Profile = profile
        let page = try engineProfile.createWebContents(WebContentsConfiguration(initiallyHidden: true))
        page.load(url("https://protocol.example"))
        #expect(page.url == url("https://protocol.example"))
        #expect(profile.openWebContents.count == 1)
    }

    @Test func faviconsAndSiteData() async throws {
        let (_, profile) = try makeProfile()
        let page = url("https://icons.example/")
        #expect(await profile.favicon(for: page) == nil)
        let image = NSImage(size: NSSize(width: 16, height: 16))
        profile.storedFavicons[page] = image
        #expect(await profile.favicon(for: page) === image)
        try await profile.clearSiteData([.cookies, .storage], for: url("https://icons.example"))
        #expect(profile.clearedSiteData.count == 1)
        #expect(profile.clearedSiteData[0].types == [.cookies, .storage])
    }

    @Test func terminateClosesEveryPage() throws {
        let (app, profile) = try makeProfile()
        let work = try app.profile(named: "Work")
        let pages = [profile.makeWebContents(), profile.makeWebContents(), work.makeWebContents()]
        let ui = RecordingUIDelegate()
        pages.forEach { $0.uiDelegate = ui }
        var result: Bool?
        app.tryToTerminate { result = $0 }
        #expect(result == true)
        #expect(pages.allSatisfy { $0.state == .closed })
        #expect(ui.calls == [.didClose, .didClose, .didClose])
    }

    @Test func beforeUnloadCancelsTermination() throws {
        let (app, profile) = try makeProfile()
        let first = profile.makeWebContents()
        let blocking = profile.makeWebContents()
        blocking.hasBeforeUnloadHandler = true
        let ui = RecordingUIDelegate()
        ui.beforeUnloadAnswer = false
        blocking.uiDelegate = ui
        var result: Bool?
        app.tryToTerminate { result = $0 }
        #expect(result == false)
        #expect(first.state == .alive && blocking.state == .alive)
    }
}

@Suite("Downloads")
struct DownloadTests {
    @Test func delegatePicksTheDestinationAndSeesProgress() throws {
        let (_, profile) = try makeProfile()
        let delegate = RecordingDownloadsDelegate()
        profile.downloadsDelegate = delegate
        let id = profile.simulateDownload(url: url("https://files.example/file.zip"), totalBytes: 100)
        profile.advanceDownload(id: id, by: 40)
        profile.pauseDownload(id: id)
        profile.advanceDownload(id: id, by: 10)
        profile.resumeDownload(id: id)
        profile.advanceDownload(id: id, by: 80)

        #expect(delegate.began.map(\.suggestedFilename) == ["file.zip"])
        #expect(delegate.updates.map(\.receivedBytes) == [0, 40, 40, 40, 100])
        #expect(delegate.updates.map(\.isPaused) == [false, false, true, false, false])
        let final = try #require(delegate.updates.last)
        #expect(final.state == .complete)
        #expect(final.destination == URL(filePath: "/tmp/downloads/file.zip"))
        #expect(final.fractionCompleted == 1)
    }

    @Test func delegateCanCancelBeforeStart() throws {
        let (_, profile) = try makeProfile()
        let delegate = RecordingDownloadsDelegate()
        delegate.destination = nil
        profile.downloadsDelegate = delegate
        let id = profile.simulateDownload(url: url("https://files.example/x.dmg"))
        #expect(profile.downloads[id]?.state == .cancelled)
    }

    @Test func noDelegateMeansCancelled() throws {
        let (_, profile) = try makeProfile()
        let id = profile.simulateDownload(url: url("https://files.example/x.dmg"))
        #expect(profile.downloads[id]?.state == .cancelled)
    }

    @Test func interruptedDownloadsResume() throws {
        let (_, profile) = try makeProfile()
        let delegate = RecordingDownloadsDelegate()
        profile.downloadsDelegate = delegate
        let id = profile.simulateDownload(url: url("https://files.example/big.iso"))
        profile.advanceDownload(id: id, by: 5)
        profile.interruptDownload(id: id)
        #expect(profile.downloads[id]?.canResume == true)
        profile.resumeDownload(id: id)
        #expect(profile.downloads[id]?.state == .inProgress)
        profile.cancelDownload(id: id)
        #expect(profile.downloads[id]?.state == .cancelled)
        #expect(profile.downloads[id]?.fractionCompleted == nil)
    }

    /// B-59: a removed download leaves the engine's list and reports nothing more.
    @Test func removedDownloadsAreForgotten() throws {
        let (_, profile) = try makeProfile()
        let delegate = RecordingDownloadsDelegate()
        profile.downloadsDelegate = delegate
        let id = profile.simulateDownload(url: url("https://files.example/a.zip"), totalBytes: 10)
        profile.advanceDownload(id: id, by: 10)
        let updates = delegate.updates.count
        profile.removeDownload(id: id)
        #expect(profile.downloads[id] == nil)
        profile.advanceDownload(id: id, by: 1)
        #expect(delegate.updates.count == updates)
    }
}

@Suite("Menu model")
struct MenuModelTests {
    @Test func completesExactlyOnce() {
        var results: [MenuItem.ID?] = []
        let menu = MenuModel(items: [MenuItem(id: 1, title: "One")]) { results.append($0) }
        #expect(menu.isPending)
        menu.select(1)
        menu.cancel()
        menu.select(1)
        #expect(results == [1])
        #expect(!menu.isPending)
    }

    @Test func findsItemsInSubmenus() {
        let menu = MenuModel(items: [
            MenuItem(id: 1, title: "Top"),
            .separator(),
            MenuItem(id: 2, kind: .submenu([MenuItem(id: 3, kind: .checkbox, title: "Spellcheck", isChecked: true)]), title: "Spelling"),
        ]) { _ in }
        #expect(menu.item(withID: 3)?.title == "Spellcheck")
        #expect(menu.item(withID: -1) == nil)
        #expect(menu.item(withID: 9) == nil)
    }
}

/// 4.3b: `Profile.importPasswords` as the fake answers it (the shape of
/// Chromium's `PasswordImporter`: conflicts asked once for all, malformed rows
/// listed with their reason, a row saved with the same password counted).
@Suite("Password import")
struct PasswordImportTests {
    static let csv = """
        name,url,username,password,note\r
        127.0.0.1,http://127.0.0.1:8772/login.html,alice,secret-a2,"conflicts, with a comma"\r
        localhost,http://localhost:8772/login.html,bob,secret-b1,\r
        127.0.0.1,https://127.0.0.1:8773/signup.html,carol,secret-c1,"a ""quoted"" note"\r
        broken,not a url,mallory,secret-m1,malformed\r

        """

    private func profileWithAlice() throws -> FakeProfile {
        let (_, profile) = try makeProfile()
        profile.savedPasswords = [.init(site: "http://127.0.0.1:8772", username: "alice", password: "secret-a0")]
        return profile
    }

    @Test func conflictsKeptWithSkip() async throws {
        let profile = try profileWithAlice()
        let result = await profile.importPasswords(csv: Self.csv, conflicts: .skip)
        #expect(result.status == .success)
        #expect(result.imported == 2)
        #expect(result.conflicts == 1 && result.replaced == 0)
        #expect(result.skipped == 1)
        #expect(result.rows.map(\.reason) == [.conflictKept, .invalidURL])
        #expect(profile.savedPasswords.first { $0.username == "alice" }?.password == "secret-a0")
        #expect(Set(profile.savedPasswords.map(\.username)) == ["alice", "bob", "carol"])
    }

    @Test func conflictsReplacedAndDuplicatesCounted() async throws {
        let profile = try profileWithAlice()
        _ = await profile.importPasswords(csv: Self.csv, conflicts: .skip)
        let again = await profile.importPasswords(csv: Self.csv, conflicts: .replace)
        #expect(again.imported == 3)
        #expect(again.conflicts == 1 && again.replaced == 1)
        #expect(again.rows.first?.reason == .conflictReplaced)
        #expect(profile.savedPasswords.first { $0.username == "alice" }?.password == "secret-a2")
        #expect(profile.savedPasswords.count == 3)
    }

    @Test func aliasesAndMissingColumns() async throws {
        let (_, profile) = try makeProfile()
        let aliased = await profile.importPasswords(csv: "login_uri,login_username,login_password\nhttps://a.example/,u,p\nhttps://b.example/,v,\n", conflicts: .skip)
        #expect(aliased.imported == 1)
        #expect(aliased.rows.map(\.reason) == [.missingPassword])
        let noHeader = await profile.importPasswords(csv: "title,notes\nx,y\n", conflicts: .skip)
        #expect(noHeader.status == .badFormat)
    }
}

/// The three 4.4b members (ROADMAP 4.4 task 6) on the fake.
@Suite("Profile deletion, browsing data, content settings")
struct ProfileDataTests {
    @Test func deleteProfileRefusesWhileAPageIsOpen() async throws {
        let (app, _) = try makeProfile()
        let work = try app.profile(named: "Work")
        let page = work.makeWebContents()
        await #expect(throws: EngineError.profileInUse("1 pages open")) { try await app.deleteProfile(work) }
        #expect(app.profiles.count == 2)
        page.close()
        try await app.deleteProfile(work)
        #expect(app.profiles.map(\.name) == ["Default"])
        #expect(app.deletedProfiles == ["Work"])
        await #expect(throws: EngineError.closed) { try await app.deleteProfile(work) }
    }

    @Test func clearBrowsingDataKeepsWhatIsOlderThanThePeriod() async throws {
        let (_, profile) = try makeProfile()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        profile.now = { now }
        let history = FakeHistory()
        profile.fakeHistory = history
        history.addVisit(url("https://old.example/"), title: "Old", at: now.addingTimeInterval(-7200))
        history.addVisit(url("https://both.example/"), title: "Both", at: now.addingTimeInterval(-7200))
        history.addVisit(url("https://both.example/"), title: "Both", at: now.addingTimeInterval(-60))
        history.addVisit(url("https://new.example/"), title: "New", at: now.addingTimeInterval(-60))
        await profile.clearBrowsingData([.history, .cookiesAndSiteData], since: .lastHour)
        #expect(Set(history.entries.keys) == ["https://old.example/", "https://both.example/"])
        #expect(history.entries["https://both.example/"]?.entry.visitCount == 1)
        #expect(profile.clearedBrowsingData.map(\.period) == [.lastHour])
        await profile.clearBrowsingData(.history, since: .allTime)
        #expect(history.entries.isEmpty)
    }

    @Test func contentSettingsListTheSitesWithTheirOwnSetting() throws {
        let (_, profile) = try makeProfile()
        profile.setPermissionSetting(.block, for: .camera, origin: url("https://b.example"))
        profile.setPermissionSetting(.allow, for: .camera, origin: url("https://a.example:8443"))
        profile.setPermissionSetting(.allow, for: .popups, origin: url("https://c.example"))
        let camera = profile.contentSettings(ofType: .camera)
        #expect(camera.map(\.pattern) == ["https://a.example:8443", "https://b.example"])
        #expect(camera.map(\.setting) == [.allow, .block])
        profile.setPermissionSetting(nil, for: .camera, origin: url("https://b.example"))
        #expect(profile.contentSettings(ofType: .camera).map(\.pattern) == ["https://a.example:8443"])
    }

    @Test func periodsStartWhereChromeStartsThem() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        #expect(BrowsingDataPeriod.lastHour.start(before: now) == now.addingTimeInterval(-3600))
        #expect(BrowsingDataPeriod.lastFourWeeks.start(before: now) == now.addingTimeInterval(-28 * 86_400))
        #expect(BrowsingDataPeriod.allTime.start(before: now) == nil)
    }
}
