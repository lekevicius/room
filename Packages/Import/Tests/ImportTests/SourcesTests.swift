import Foundation
import Testing
@testable import Import

@Suite("Import: URL normalisation, sources, scans")
struct SourcesTests {
    @Test("Normalised URLs: scheme and host lower-cased, www. dropped, the default port and an empty path's slash dropped, the fragment dropped")
    func normalisation() {
        #expect(ImportURL.normalized("HTTPS://WWW.Example.com") == "https://example.com")
        #expect(ImportURL.normalized("https://example.com:443/") == "https://example.com")
        #expect(ImportURL.normalized("http://example.com:80/a") == "http://example.com/a")
        #expect(ImportURL.normalized("http://example.com:8080/a") == "http://example.com:8080/a")
        #expect(ImportURL.normalized("https://www.example.org/docs#intro") == "https://example.org/docs")
        // A trailing slash on a non-empty path, the path's case and the query count.
        #expect(ImportURL.normalized("https://a.example/en-US/") != ImportURL.normalized("https://a.example/en-US"))
        #expect(ImportURL.normalized("https://a.example/Path") != ImportURL.normalized("https://a.example/path"))
        #expect(ImportURL.normalized("https://a.example/?q=1") != ImportURL.normalized("https://a.example/?q=2"))
        #expect(ImportURL.normalized("javascript:alert(1)#x") == "javascript:alert(1)")
        #expect(ImportURL.refusedScheme("javascript:alert(1)") == "javascript")
        #expect(ImportURL.refusedScheme("place:sort=8") == "place")
        #expect(ImportURL.refusedScheme("chrome://settings/") == "chrome")
        #expect(ImportURL.refusedScheme("https://a.example/") == nil && ImportURL.refusedScheme("file:///tmp/a.html") == nil)
    }

    @Test("Installs are detected by their directories alone; Firefox is listed with its note")
    func detection() throws {
        let home = try Fixtures.scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        for path in ["Library/Application Support/Google/Chrome", "Library/Application Support/Arc", "Library/Safari",
                     "Library/Application Support/Firefox"] {
            try FileManager.default.createDirectory(at: home.appending(path: path), withIntermediateDirectories: true)
        }
        // A file where Brave's directory would be is not an install.
        try FileManager.default.createDirectory(at: home.appending(path: "Library/Application Support/BraveSoftware"), withIntermediateDirectories: true)
        try Data().write(to: home.appending(path: "Library/Application Support/BraveSoftware/Brave-Browser"))
        let sources = ImportSources.detectInstalls(home: home)
        #expect(sources.map(\.kind) == [.chrome, .arc, .safari, .firefox])
        #expect(sources.map(\.name) == ["Google Chrome", "Arc", "Safari", "Firefox"])
        #expect(sources.last?.note == ImportSources.firefoxNote && sources.last?.isReadable == false)
    }

    @Test("A fixture directory lists one source per subdirectory; chosen files are identified by name")
    func identify() throws {
        let sources = ImportSources.sources(inDirectory: Fixtures.directory)
        #expect(sources.map(\.kind) == [.arc, .chrome, .bookmarksFile, .safari])
        #expect(sources.map(\.name) == ["arc (fixture)", "chrome (fixture)", "netscape (fixture)", "safari (fixture)"])
        #expect(sources[2].location.lastPathComponent == "bookmarks.html")
        #expect(ImportSources.identify(Fixtures.url("safari/Bookmarks.plist"))?.kind == .safari)
        #expect(ImportSources.identify(Fixtures.url("chrome/Default/Bookmarks"))?.location.lastPathComponent == "Default")
        #expect(ImportSources.identify(Fixtures.url("netscape/bookmarks.html"))?.kind == .bookmarksFile)
        #expect(ImportSources.identify(Fixtures.url("pages")) == nil)
        let chrome = try #require(sources.first { $0.kind == .chrome })
        // "Profile 9" is in Local State without a directory.
        #expect(ImportSources.profiles(of: chrome) == [ImportProfileChoice(directory: "Default", name: "Person 1"),
                                                       ImportProfileChoice(directory: "Profile 1", name: "Work")])
    }

    @Test("A scan reads each part the source has, with the readers' counts and errors")
    func scan() throws {
        let sources = ImportSources.sources(inDirectory: Fixtures.directory)
        let chrome = try #require(sources.first { $0.kind == .chrome })
        let scan = ImportScanner.scan(chrome, profile: ImportProfileChoice(directory: "Default", name: "Person 1"))
        #expect(scan.bookmarks?.value?.links == 31 && scan.history?.value?.urls.count == 10)
        #expect(scan.extensions?.value?.extensions.count == 2 && scan.sidebar == nil && scan.errors.isEmpty)
        let work = ImportScanner.scan(chrome, profile: ImportProfileChoice(directory: "Profile 1", name: "Work"))
        #expect(work.bookmarks?.value?.links == 1 && work.history == nil && work.extensions == nil)
        let arc = ImportScanner.scan(try #require(sources.first { $0.kind == .arc }), profile: nil)
        #expect(arc.sidebar?.value?.profiles.map(\.name) == ["Personal", "Work"] && arc.bookmarks == nil && arc.history == nil)
        let safari = ImportScanner.scan(try #require(sources.first { $0.kind == .safari }), profile: nil)
        #expect(safari.bookmarks?.value?.links == 10 && safari.history?.value?.urls.count == 4)
        // A broken file is an error for its part only.
        let directory = try Fixtures.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8).write(to: directory.appending(path: "Bookmarks"))
        try FileManager.default.copyItem(at: Fixtures.url("chrome/Default/History"), to: directory.appending(path: "History"))
        let broken = ImportScanner.scan(ImportSource(kind: .chrome, name: "Broken", location: directory), profile: nil)
        #expect(broken.errors == [ImportError(.malformed, .chromeBookmarks, "not JSON")] && broken.history?.value?.urls.count == 10)
    }
}
