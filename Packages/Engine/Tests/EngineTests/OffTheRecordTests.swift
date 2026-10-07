import AppKit
import Engine
import FakeEngine
import Testing

/// The off-the-record twin and the move between windows (4.8b, ROADMAP 4.8
/// task 6): the fakes behave as RoomCore's members are specified.
@MainActor
@Suite("Off the record and moves")
struct OffTheRecordTests {
    @Test func theTwinIsOneObjectUntilClosedAndKeepsItsCookiesApart() throws {
        let (_, profile) = try makeProfile()
        let twin = try #require(try profile.offTheRecord() as? FakeProfile)
        #expect(twin.isOffTheRecord)
        #expect(try profile.offTheRecord() === twin)
        #expect(throws: EngineError.notSupported("offTheRecord of an off-the-record profile")) { try twin.offTheRecord() }

        twin.setCookie("room", value: "incognito", host: "127.0.0.1")
        #expect(profile.cookies["127.0.0.1"] == nil)

        let page = twin.makeWebContents()
        page.load(url("https://example.com/"))
        profile.closeOffTheRecord()
        #expect(page.state == .closed)
        #expect(twin.isClosed && twin.cookies.isEmpty)
        let next = try #require(try profile.offTheRecord() as? FakeProfile)
        #expect(next !== twin)
        #expect(next.cookies.isEmpty)
    }

    @Test func aTwinStillClosingIsRefused() throws {
        let (_, profile) = try makeProfile()
        profile.offTheRecordUnavailable = true
        #expect(throws: EngineError.profileInUse("the previous twin is closing")) { try profile.offTheRecord() }
    }

    @Test func anOffTheRecordOpenBelongsToTheTwin() throws {
        let (_, profile) = try makeProfile()
        let window = NSWindow()
        let opener = profile.makeWebContents(WebContentsConfiguration(hostWindow: window))
        let delegate = RecordingUIDelegate()
        opener.uiDelegate = delegate
        opener.load(url("https://example.com/"))
        opener.simulateLinkClick(to: url("https://example.com/private"), disposition: .offTheRecord)
        #expect(delegate.calls.contains(.didCreate(targetURL: url("https://example.com/private"), disposition: .offTheRecord)))
        let page = try #require(delegate.createdContents.first as? FakeWebContents)
        #expect(profile.offTheRecordTwin?.openWebContents.contains { $0 === page } == true)
        #expect(!profile.openWebContents.contains { $0 === page })
    }

    @Test func aMovedPageKeepsItsHistoryAndOpensInItsNewWindow() throws {
        let (_, profile) = try makeProfile()
        let first = NSWindow(), second = NSWindow()
        let page = profile.makeWebContents(WebContentsConfiguration(hostWindow: first))
        page.load(url("https://example.com/a"))
        page.load(url("https://example.com/b"))
        try page.move(toHostWindow: second)
        #expect(page.hostWindow === second)
        #expect(page.canGoBack && page.backForwardList.count == 2)
        try page.move(toHostWindow: second)
        #expect(page.moveCount == 1)

        let delegate = RecordingUIDelegate()
        page.uiDelegate = delegate
        page.simulateWindowOpen(url("https://example.com/c"))
        #expect((delegate.createdContents.first as? FakeWebContents)?.hostWindow === second)

        page.close()
        #expect(throws: EngineError.closed) { try page.move(toHostWindow: first) }
    }

    @Test func allowedInIncognitoIsPerExtension() throws {
        let extensions = FakeProfileExtensions(installed: [InstalledExtension(id: "a", name: "A"), InstalledExtension(id: "b", name: "B")])
        extensions.setAllowedInIncognito(true, extension: "a")
        extensions.setAllowedInIncognito(true, extension: "missing")
        #expect(extensions.allowedInIncognito == ["a"])
        extensions.setAllowedInIncognito(false, extension: "a")
        #expect(extensions.allowedInIncognito.isEmpty)
    }
}
