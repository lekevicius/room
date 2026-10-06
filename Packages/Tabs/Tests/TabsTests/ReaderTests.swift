import AppKit
import Engine
import FakeEngine
import Foundation
import Model
import Testing
@testable import Tabs

/// Reader mode on the tab controller (4.7b): the reader page takes the
/// card in place of the entry's page, which is never navigated; Exit, Esc
/// and a link give the card back to it.
@Suite("Reader mode on the tab controller", .serialized)
struct ReaderModeTests {
    let file = URL(fileURLWithPath: "/tmp/room-reader-test/entry.html")

    func fixture() async throws -> (TabsFixture, Entry, FakeWebContents) {
        let fixture = try TabsFixture()
        let entry = try fixture.today("https://news.example.com/story")
        try fixture.select(entry.id)
        await fixture.settle()
        let page = try #require(fixture.page(entry.id))
        page.simulateLinkClick(to: URL(string: "https://news.example.com/story/2")!)
        await fixture.settle()
        return (fixture, entry, page)
    }

    @Test("The reader page shows in the card; the entry's page stays loaded with its history; Exit gives the card back")
    func swapAndExit() async throws {
        let (fixture, entry, page) = try await fixture()
        var ended: [UUID] = []
        fixture.tabs.onReaderEnded = { id, _, _ in ended.append(id) }
        let historyBefore = page.canGoBack
        let reader = try #require(fixture.tabs.openReader(file, for: entry.id) as? FakeWebContents)
        await fixture.settle()
        #expect(fixture.display.shown === reader)
        #expect(fixture.tabs.focusedPage === reader)
        #expect(reader.url == file)
        #expect(fixture.tabs.pageState(for: entry.id).isReader)
        #expect(fixture.tabs.contents(for: entry.id) === page)
        #expect(page.url == URL(string: "https://news.example.com/story/2"), "the entry's page is not navigated")
        // Back acts on the reader page, which has no history: the entry's page stays.
        fixture.tabs.focusedPage?.goBack()
        #expect(page.url == URL(string: "https://news.example.com/story/2"))
        fixture.tabs.exitReader(entry.id)
        #expect(fixture.display.shown === page)
        #expect(page.canGoBack == historyBefore)
        #expect(reader.state == .closed)
        #expect(!fixture.tabs.pageState(for: entry.id).isReader)
        #expect(ended == [entry.id])
    }

    @Test("Esc leaves reader mode; a link leaves it and loads in the entry's page; the original URL only leaves")
    func escapeAndLinks() async throws {
        let (fixture, entry, page) = try await fixture()
        let reader = try #require(fixture.tabs.openReader(file, for: entry.id) as? FakeWebContents)
        let esc = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(fixture.tabs.webContents(reader, handleUnhandledKeyEvent: esc))
        #expect(fixture.display.shown === page)

        let second = try #require(fixture.tabs.openReader(file, for: entry.id) as? FakeWebContents)
        second.simulateLinkClick(to: URL(string: "https://news.example.com/story/2#top")!)
        await fixture.settle()
        #expect(fixture.display.shown === page)
        #expect(page.url == URL(string: "https://news.example.com/story/2"), "the original page's URL only exits")

        let third = try #require(fixture.tabs.openReader(file, for: entry.id) as? FakeWebContents)
        third.simulateLinkClick(to: URL(string: "https://elsewhere.example/a")!)
        await fixture.settle()
        #expect(fixture.display.shown === page)
        #expect(page.url == URL(string: "https://elsewhere.example/a"))
    }

    @Test("Unloading the entry closes its reader page")
    func unloadCloses() async throws {
        let (fixture, entry, _) = try await fixture()
        let reader = try #require(fixture.tabs.openReader(file, for: entry.id) as? FakeWebContents)
        fixture.tabs.unload(entry.id)
        #expect(reader.state == .closed)
        #expect(fixture.tabs.readerContents(for: entry.id) == nil)
    }

    @Test("Where a reader page's navigation leads")
    func navigationOutcome() throws {
        let original = try #require(URL(string: "https://a.example/story?id=1"))
        #expect(ReaderNavigation.outcome(of: file, readerPage: file, original: original) == .stay)
        #expect(ReaderNavigation.outcome(of: try #require(URL(string: file.absoluteString + "#note")), readerPage: file, original: original) == .stay)
        #expect(ReaderNavigation.outcome(of: try #require(URL(string: "https://a.example/story?id=1#x")), readerPage: file, original: original) == .exit)
        let other = try #require(URL(string: "https://a.example/story?id=2"))
        #expect(ReaderNavigation.outcome(of: other, readerPage: file, original: original) == .exitAndLoad(other))
    }
}
