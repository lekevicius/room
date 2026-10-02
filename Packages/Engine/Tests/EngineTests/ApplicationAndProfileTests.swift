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
