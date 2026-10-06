import Foundation
import GRDB
import Testing
@testable import Import

@Suite("Import: history readers (Chrome-family History, Safari History.db) on copies")
struct HistoryReaderTests {
    @Test("Chrome's History (a headless Chrome 154 profile): URLs, titles, visits with their transitions, typed counts, WebKit times; hidden rows skipped")
    func chrome() throws {
        let original = Fixtures.url("chrome/Default/History")
        let before = try FileManager.default.attributesOfItem(atPath: original.path)[.modificationDate] as? Date
        let history = try ChromeHistoryReader.read(at: original)
        #expect(history.urls.count == 10 && history.visits == 16)
        #expect(history.skipped == [SkippedItem("https://ads.example.com/frame", reason: "hidden (a subframe)")])
        let alpha = try #require(history.urls.first { $0.url == "http://127.0.0.1:8780/alpha.html" })
        #expect(alpha.title == "Import fixture Alpha" && alpha.visitCount == 2 && alpha.typedCount == 1)
        #expect(alpha.visits.map(\.transition) == [.typed, .other])
        // last_visit_time 13435775529419594 µs since 1601.
        #expect(abs((alpha.lastVisit?.timeIntervalSince1970 ?? 0) - 1_791_301_929.419594) < 0.001)
        let typed = try #require(history.urls.first { $0.url == "https://example.org/typed" })
        #expect(typed.typedCount == 3 && typed.visits.allSatisfy { $0.transition == .typed })
        #expect(typed.visits.map(\.time) == typed.visits.map(\.time).sorted())
        let search = try #require(history.urls.first { $0.url.hasPrefix("https://example.org/search") })
        #expect(search.visits.map(\.transition) == [.formSubmit, .reload])
        let redirect = try #require(history.urls.first { $0.url.hasSuffix("from=redirect") })
        #expect(redirect.visits.map(\.transition) == [.link])
        // The original was never opened (a copy was read).
        #expect(try FileManager.default.attributesOfItem(atPath: original.path)[.modificationDate] as? Date == before)
        #expect(!FileManager.default.fileExists(atPath: original.path + "-journal"))
    }

    @Test("Safari's History.db: items with their successful visits, 2001-based seconds, the latest title; a failed-only item skipped")
    func safari() throws {
        let history = try SafariHistoryReader.read(at: Fixtures.url("safari/History.db"))
        #expect(history.urls.count == 4 && history.visits == 6)
        #expect(history.skipped == [SkippedItem("https://broken.example/", reason: "no successful visit")])
        let news = try #require(history.urls.first { $0.url == "https://news.example.com/a" })
        #expect(news.title == "Article A" && news.visits.count == 2 && news.typedCount == 0)
        // 812548800 s after 2001-01-01 is 2026-10-01 12:00 UTC.
        #expect(news.lastVisit == Date(timeIntervalSince1970: 1_790_856_000))
        #expect(news.visits.first?.time == Date(timeIntervalSinceReferenceDate: 812_548_800 - 100 * 86_400))
    }

    @Test("A file that is not SQLite, a database without the tables, a missing file: typed errors")
    func malformed() throws {
        let directory = try Fixtures.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let garbage = directory.appending(path: "History")
        try Data(repeating: 0x42, count: 4096).write(to: garbage)
        #expect(throws: ImportError.self) { try ChromeHistoryReader.read(at: garbage) }
        do {
            _ = try ChromeHistoryReader.read(at: garbage)
        } catch {
            #expect(error.kind == .malformed && error.format == .chromeHistory)
        }
        let other = directory.appending(path: "Other.db")
        let queue = try DatabaseQueue(path: other.path)
        try queue.write { try $0.execute(sql: "CREATE TABLE t (x)") }
        try queue.close()
        #expect(throws: ImportError(.malformed, .chromeHistory, "no urls or visits table")) { try ChromeHistoryReader.read(at: other) }
        #expect(throws: ImportError(.malformed, .safariHistory, "no history_items or history_visits table")) { try SafariHistoryReader.read(at: other) }
        do {
            _ = try SafariHistoryReader.read(at: directory.appending(path: "missing.db"))
            Issue.record("no error")
        } catch {
            #expect(error.kind == .unreadable)
        }
    }
}

@Suite("Import: Preferences' extensions, Local State's profiles, Arc's sidebar")
struct ProfileReaderTests {
    @Test("Preferences: Web Store extensions with name, version and state; the unpacked one skipped")
    func extensions() throws {
        let read = try ChromeExtensionsReader.read(try Fixtures.data("chrome/Default/Preferences"))
        #expect(read.extensions == [
            ImportedExtension(id: "cjpalhdlnbpafiamejdnhcphjbkeiagm", name: "uBlock Origin", version: "1.66.0", fromWebStore: true, enabled: false),
            ImportedExtension(id: "nngceckbapebfimnlniiiahkandclblb", name: "Bitwarden Password Manager", version: "2026.9.0", fromWebStore: true,
                              enabled: true),
        ])
        #expect(read.skipped == [SkippedItem("My Unpacked Tool", reason: "unpacked (loaded from a folder)")])
    }

    @Test("Preferences: component and policy installs and a missing manifest are skipped; no extensions is empty; not JSON throws")
    func extensionsEdges() throws {
        let json = #"{"extensions":{"settings":{"a":{"location":5,"manifest":{"name":"PDF"}},"b":{"location":9,"manifest":{"name":"Policy"}},"c":{"location":1}}}}"#
        let read = try ChromeExtensionsReader.read(Data(json.utf8))
        #expect(read.extensions.isEmpty)
        #expect(read.skipped.map(\.reason) == ["part of the browser", "installed by policy or another app", "no manifest"])
        #expect(try ChromeExtensionsReader.read(Data("{}".utf8)) == ImportedExtensions())
        #expect(throws: ImportError(.malformed, .chromePreferences, "not JSON")) { try ChromeExtensionsReader.read(Data("{".utf8)) }
    }

    @Test("Local State: the profiles by name in profiles_order")
    func localState() throws {
        let profiles = try ChromeLocalStateReader.profiles(try Fixtures.data("chrome/Local State"))
        #expect(profiles.map(\.directory) == ["Default", "Profile 1", "Profile 9"])
        #expect(profiles.map(\.name) == ["Person 1", "Work", "Gone"])
    }

    @Test("Arc's StorableSidebar.json: spaces with names, icons, colours and profiles; essentials per profile; pinned with folders; Today; unsupported items skipped")
    func arc() throws {
        let sidebar = try ArcSidebarReader.read(try Fixtures.data("arc/StorableSidebar.json"), profileNames: ["Default": "Personal", "Profile 1": "Work"])
        #expect(sidebar.profiles == [ImportedProfile(key: "default", name: "Personal", isDefault: true),
                                     ImportedProfile(key: "Profile 1", name: "Work", isDefault: false)])
        #expect(sidebar.spaces.map(\.name) == ["Home", "Work", "Side"])
        #expect(sidebar.spaces.map(\.icon) == ["🏠", "💼", nil])
        #expect(sidebar.spaces.map(\.colors) == [["#3366CC"], ["#CC4D33"], []])
        #expect(sidebar.spaces.map(\.profileKey) == ["default", "Profile 1", "default"])
        let home = sidebar.spaces[0]
        #expect(home.pinned.map(\.title) == ["News", "Projects"])
        #expect(home.pinned[1].folder?.children.map(\.title) == ["Room project", "Nested", "Room project again"])
        #expect(home.today.map(\.url) == ["http://127.0.0.1:8780/alpha.html", "https://search.example/?q=room"])
        #expect(sidebar.essentials["default"]?.map(\.title) == ["Mail", "Calendar"])
        #expect(sidebar.essentials["Profile 1"]?.map(\.title) == ["Chat"])
        #expect(sidebar.pinnedLinks == 6 && sidebar.folders == 2 && sidebar.todayTabs == 3 && sidebar.essentialsCount == 3)
        #expect(sidebar.skipped == [SkippedItem("A canvas", reason: "unsupported item (easel)"),
                                    SkippedItem("A tab without a URL", reason: "a tab without a URL")])
    }

    @Test("Arc: arrays of objects only (no ids between them) read the same; no containers throws")
    func arcShapes() throws {
        let json = """
        {"sidebar":{"containers":[{"spaces":[{"id":"s","title":"Only","containerIDs":["pinned","p","unpinned","u"]}],
        "items":[{"id":"p","childrenIds":["t"],"data":{"itemContainer":{}}},{"id":"t","parentID":"p","childrenIds":[],"data":{"tab":{"savedURL":"https://a.example/","savedTitle":"A"}}},
        {"id":"u","childrenIds":[],"data":{"itemContainer":{}}}],"topAppsContainerIDs":[]}]}}
        """
        let sidebar = try ArcSidebarReader.read(Data(json.utf8))
        #expect(sidebar.spaces.map(\.name) == ["Only"] && sidebar.spaces[0].pinned.map(\.title) == ["A"])
        #expect(sidebar.profiles.map(\.key) == ["default"] && sidebar.profiles[0].name == "Default")
        #expect(throws: ImportError(.malformed, .arcSidebar, "no sidebar.containers")) { try ArcSidebarReader.read(Data(#"{"sidebar":{}}"#.utf8)) }
        #expect(throws: ImportError(.malformed, .arcSidebar, "no container with spaces and items")) {
            try ArcSidebarReader.read(Data(#"{"sidebar":{"containers":[{"global":{}}]}}"#.utf8))
        }
        #expect(throws: ImportError(.malformed, .arcSidebar, "not JSON")) { try ArcSidebarReader.read(Data("]".utf8)) }
    }
}
