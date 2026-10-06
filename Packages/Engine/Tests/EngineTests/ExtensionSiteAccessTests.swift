import AppKit
import Engine
import FakeEngine
import Testing

/// Phase 4.5: an extension's site access per host, Run, and commands, as
/// the fake answers them for the host's tests (RoomCore's rules: Chrome's
/// `PermissionsManager`, `ExtensionActionRunner`, `CommandService`).
@Suite("Extension site access and commands")
struct ExtensionSiteAccessTests {
    private func setUp() throws -> (FakeProfileExtensions, FakeWebContents, FakeWebContents) {
        let (_, profile) = try makeProfile()
        let extensions = FakeProfileExtensions(installed: [InstalledExtension(id: "fx", name: "Fixture")])
        profile.fakeExtensions = extensions
        let page = profile.makeWebContents()
        page.load(url("http://127.0.0.1:8770/site.html"), transition: .typed, fromAddressBar: true)
        let other = profile.makeWebContents()
        other.load(url("https://example.com/"), transition: .typed, fromAddressBar: true)
        return (extensions, page, other)
    }

    @Test func onClickWaitsForRunAndOnSiteIsPerHost() throws {
        let (extensions, page, other) = try setUp()
        #expect(extensions.siteAccess(for: page, extension: "fx")?.level == .onAllSites)
        #expect(extensions.setSiteAccess(.onClick, for: "fx", host: "127.0.0.1"))
        extensions.simulatePageLoad(page, extension: "fx")
        extensions.simulatePageLoad(other, extension: "fx")
        #expect(extensions.siteAccess(for: page, extension: "fx")?.wantsToRun == true)
        #expect(extensions.siteAccess(for: other, extension: "fx")?.wantsToRun == false)
        #expect(extensions.ranOn.map(\.page) == [ObjectIdentifier(other)])
        #expect(extensions.runAction(for: "fx", in: page))
        #expect(extensions.siteAccess(for: page, extension: "fx")?.wantsToRun == false)
        #expect(!extensions.runAction(for: "fx", in: page))
        #expect(extensions.setSiteAccess(.onSite, for: "fx", host: "127.0.0.1"))
        extensions.simulatePageLoad(page, extension: "fx")
        #expect(extensions.siteAccess(for: page, extension: "fx")?.level == .onSite)
        #expect(extensions.siteAccess(for: page, extension: "fx")?.wantsToRun == false)
        #expect(extensions.siteAccess(for: other, extension: "fx")?.level == .onAllSites)
    }

    @Test func refusesALevelTheExtensionCannotTake() throws {
        let (extensions, page, other) = try setUp()
        extensions.selectableSiteAccess["fx"] = [.onClick, .onSite]
        extensions.requestedHosts["fx"] = ["127.0.0.1"]
        #expect(!extensions.setSiteAccess(.onAllSites, for: "fx", host: "127.0.0.1"))
        #expect(!extensions.setSiteAccess(.onSite, for: "fx", host: "example.com"))
        #expect(extensions.siteAccess(for: other, extension: "fx")?.wantsSite == false)
        #expect(extensions.siteAccess(for: page, extension: "fx")?.selectable == [.onClick, .onSite])
        #expect(extensions.siteAccess(for: page, extension: "nobody") == nil)
    }

    @Test func commandsRunOnlyWhenTheExtensionHasThem() throws {
        let (extensions, page, _) = try setUp()
        extensions.commandsByExtension["fx"] = [ExtensionCommand(name: "_execute_action", shortcut: "⇧⌘Y"),
                                                ExtensionCommand(name: "room-named", description: "Named", shortcut: "⇧⌘U")]
        #expect(extensions.commands(for: "fx").map(\.isAction) == [true, false])
        #expect(extensions.performCommand("room-named", for: "fx", in: page))
        #expect(!extensions.performCommand("missing", for: "fx", in: page))
        #expect(extensions.performCommand("room-named", for: "fx", in: nil))
        #expect(extensions.performedCommands.map(\.name) == ["room-named", "room-named"])
        #expect(extensions.performedCommands.map(\.page) == [ObjectIdentifier(page), nil])
    }

    @Test(arguments: [("Command+Shift+U", "⇧⌘U"), ("Ctrl+Alt+Comma", "⌃⌥,"), ("MacCtrl+Shift+Up", "⌃⇧↑"),
                      ("Command+Shift+5", "⇧⌘5"), ("Alt+Shift+P", "⌥⇧P"), ("Command+MediaPlayPause", ""), ("U", ""), ("", "")])
    func chromeShortcutsInRoomNotation(_ chrome: String, _ room: String) {
        #expect(ExtensionCommand.shortcut(fromChrome: chrome) == room)
    }
}
