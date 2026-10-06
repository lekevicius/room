import Foundation
import Testing
@testable import Import

/// 4.3b: Firefox's `places.sqlite` (the fixture `firefox/places.sqlite`,
/// `make-firefox.py`: the schema `firefox_importer.cc` reads).
@Suite("Import: Firefox places.sqlite")
struct FirefoxReaderTests {
    @Test("Bookmarks: the toolbar is the bar, the menu and Other Bookmarks are other, mobile is mobile")
    func bookmarks() throws {
        let read = try FirefoxPlacesReader.bookmarks(at: Fixtures.url("firefox/places.sqlite"))
        #expect(read.bar.map(\.title) == ["Firefox", "MDN", "Dev", "Python"])  // the separator left out; an empty title takes the page's
        guard case .folder(let dev) = read.bar[2] else { Issue.record("Dev is not a folder"); return }
        #expect(dev.children.map(\.title) == ["Rust", "Kernel"])
        #expect(read.other.map(\.title) == ["Recipes", "Recent Tags", "News", "Maps"])
        #expect(read.mobile.map(\.title) == ["On the phone"])
        #expect(read.links == 10 && read.folders == 3)
        #expect(read.skipped == [SkippedItem("Lost page", reason: "no URL")])
        guard case .link(let firefox) = read.bar[0] else { return }
        #expect(firefox.url == "https://www.mozilla.org/en-US/firefox/")
        #expect(firefox.dateAdded == Date(timeIntervalSince1970: 1_790_856_000 - 30 * 86_400))
    }

    @Test("History: link, typed and bookmark visits; hidden pages and other visit types left out")
    func history() throws {
        let read = try FirefoxPlacesReader.history(at: Fixtures.url("firefox/places.sqlite"))
        #expect(read.urls.map(\.url) == ["https://www.mozilla.org/en-US/firefox/", "https://developer.mozilla.org/en-US/docs/Web",
                                         "https://www.rust-lang.org/", "https://cooking.example/soup"])
        let firefox = try #require(read.urls.first)
        #expect(firefox.visits.map(\.transition) == [.typed, .typed, .link] && firefox.typedCount == 2 && firefox.title == "Firefox Browser")
        #expect(read.urls[1].visits.count == 1)  // its reload is not a visit
        #expect(read.urls[2].visits.map(\.transition) == [.bookmark])
        #expect(read.visits == 7)
        #expect(read.skipped.map(\.item) == ["http://mozilla.org/", "https://ads.example/frame.html"])
    }

    @Test("A file without Firefox's tables is malformed")
    func malformed() throws {
        let directory = try Fixtures.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appending(path: "places.sqlite")
        try FileManager.default.copyItem(at: Fixtures.url("chrome/Default/History"), to: copy)
        #expect(throws: ImportError(.malformed, .firefoxPlaces, "no moz_bookmarks or moz_places table")) {
            try FirefoxPlacesReader.bookmarks(at: copy)
        }
    }
}
