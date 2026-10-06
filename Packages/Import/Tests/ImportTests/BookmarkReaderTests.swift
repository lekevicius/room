import Foundation
import Testing
@testable import Import

@Suite("Import: bookmark readers (Chrome JSON, Safari plist, Netscape HTML)")
struct BookmarkReaderTests {
    @Test("Chrome's Bookmarks: the bar, other and synced roots, nested folders, WebKit dates, guids")
    func chrome() throws {
        let bookmarks = try ChromeBookmarksReader.read(try Fixtures.data("chrome/Default/Bookmarks"))
        #expect(bookmarks.bar.count == 17 && bookmarks.other.count == 4 && bookmarks.mobile.count == 2)
        #expect(bookmarks.links == 31 && bookmarks.folders == 9 && bookmarks.skipped.isEmpty)
        let first = try #require(bookmarks.bar.first?.link)
        #expect(first.url == "https://example.org/docs" && first.title == "Room Docs")
        #expect(first.guid == "c7f4278c-ef3c-5993-8733-609a7cc511b0")
        // 13400000001000000 µs since 1601 = 1755526401 s since 1970.
        #expect(first.dateAdded == Date(timeIntervalSince1970: 1_755_526_401))
        // L1 … L7: seven levels.
        var depth = 0
        var node = bookmarks.bar.first { $0.title == "L1" }
        while let folder = node?.folder {
            depth += 1
            node = folder.children.first { $0.folder != nil }
        }
        #expect(depth == 7)
        #expect(bookmarks.mobile.map(\.title) == ["Mobile", "Example on the phone"])
        #expect(bookmarks.other.compactMap(\.folder).map(\.title) == ["Reading"])
    }

    @Test("Chrome's Bookmarks: a node without its URL or of an unknown type is skipped with a reason; malformed files throw")
    func chromeMalformed() throws {
        let json = #"{"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[{"type":"url","name":"No URL"},{"type":"separator","name":"Line"},{"type":"url","name":"Ok","url":"https://ok.example/"}]},"other":{"type":"folder","children":[]}}}"#
        let bookmarks = try ChromeBookmarksReader.read(Data(json.utf8))
        #expect(bookmarks.bar.map(\.title) == ["Ok"])
        #expect(bookmarks.skipped == [SkippedItem("Bar ▸ No URL", reason: "no URL"), SkippedItem("Bar ▸ Line", reason: "unknown node type")])
        #expect(throws: ImportError(.malformed, .chromeBookmarks, "not JSON")) { try ChromeBookmarksReader.read(Data("{roots".utf8)) }
        #expect(throws: ImportError(.malformed, .chromeBookmarks, "no \"roots\" object")) { try ChromeBookmarksReader.read(Data("[1]".utf8)) }
        #expect(throws: ImportError(.malformed, .chromeBookmarks, "no \"bookmark_bar\" or \"other\" root")) {
            try ChromeBookmarksReader.read(Data(#"{"roots":{}}"#.utf8))
        }
    }

    @Test("Safari's Bookmarks.plist (binary): the bar, the menu, the Reading List as a folder, a top-level folder; a leaf without a URL")
    func safari() throws {
        let bookmarks = try SafariBookmarksReader.read(try Fixtures.data("safari/Bookmarks.plist"))
        #expect(bookmarks.bar.map(\.title) == ["Apple", "Alpha", "Dev"])
        #expect(bookmarks.bar.last?.folder?.children.count == 3)
        #expect(bookmarks.other.map(\.title) == ["Wikipedia", "Recipes", "Reading List", "Travel"])
        let reading = try #require(bookmarks.other[2].folder)
        #expect(reading.children.compactMap(\.link).map(\.url) == ["https://news.example.com/a", "https://news.example.com/c"])
        #expect(reading.children.first?.link?.dateAdded != nil)
        #expect(bookmarks.mobile.isEmpty && bookmarks.links == 10 && bookmarks.folders == 4)
        #expect(bookmarks.skipped == [SkippedItem("Bookmarks ▸ Travel ▸ No URL", reason: "no URL")])
    }

    @Test("Safari's Bookmarks.plist: not a plist, or not a bookmark list, throws")
    func safariMalformed() throws {
        #expect(throws: ImportError(.malformed, .safariBookmarks, "not a property list")) { try SafariBookmarksReader.read(Data("<plist><dict><key>unclosed".utf8)) }
        let array = try PropertyListSerialization.data(fromPropertyList: ["a"], format: .xml, options: 0)
        #expect(throws: ImportError(.malformed, .safariBookmarks, "the root is not a WebBookmarkTypeList with Children")) {
            try SafariBookmarksReader.read(array)
        }
    }

    @Test("Netscape HTML: the toolbar folder is the bar, folders nest, entities decode, ADD_DATE is read; an anchor without HREF is skipped")
    func netscape() throws {
        let bookmarks = try NetscapeBookmarksReader.read(try Fixtures.data("netscape/bookmarks.html"))
        #expect(bookmarks.bar.map(\.title) == ["Mozilla & friends", "Import fixture Beta", "Tools"])
        #expect(bookmarks.bar[2].folder?.children.map(\.title) == ["MDN – Web Docs", "MDN again"])
        #expect(bookmarks.bar[0].link?.dateAdded == Date(timeIntervalSince1970: 1_756_000_001))
        #expect(bookmarks.other.map(\.title) == ["Docs", "Recently Bookmarked", "Kitchen"])
        #expect(bookmarks.other[1].link?.url == "place:sort=8&maxResults=10")
        #expect(bookmarks.other[2].folder?.children.map(\.title) == ["Bread", "Empty folder"])
        #expect(bookmarks.other[2].folder?.children.last?.folder?.children.isEmpty == true)
        #expect(bookmarks.skipped == [SkippedItem("No address", reason: "no URL")])
    }

    @Test("Netscape HTML: text without a bookmark list throws; a folder without a list is an empty folder")
    func netscapeMalformed() throws {
        #expect(throws: ImportError(.malformed, .netscapeBookmarks, "no bookmark list (<DL>)")) {
            try NetscapeBookmarksReader.read(Data("<html><body>hello</body></html>".utf8))
        }
        let html = "<DL><DT><H3>Lonely</H3><DT><A HREF=\"https://a.example/\">A</A></DL>"
        let bookmarks = try NetscapeBookmarksReader.read(Data(html.utf8))
        #expect(bookmarks.other.map(\.title) == ["Lonely", "A"])
        #expect(bookmarks.other.first?.folder?.children.isEmpty == true)
    }
}
