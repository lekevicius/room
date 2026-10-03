import Engine
import FakeEngine
import Foundation
import Testing
@testable import Chrome

@Suite("Downloads: file names, the folder, the list (ROADMAP 2.6 task 1)")
struct DownloadsTests {
    private let folder = URL(fileURLWithPath: "/Users/someone/Downloads", isDirectory: true)

    @Test("A suggested name is made safe: no path separators, colons, control characters or leading dots; empty is “download”")
    func sanitized() {
        #expect(DownloadRules.sanitizedFilename("report.pdf") == "report.pdf")
        #expect(DownloadRules.sanitizedFilename("../../etc/passwd") == "-..-etc-passwd")
        #expect(DownloadRules.sanitizedFilename("a:b\\c.txt") == "a-b-c.txt")
        #expect(DownloadRules.sanitizedFilename(".hidden") == "hidden")
        #expect(DownloadRules.sanitizedFilename("  \n ") == "download")
        #expect(DownloadRules.sanitizedFilename("tab\there.txt") == "tabhere.txt")
        #expect(DownloadRules.sanitizedFilename(String(repeating: "é", count: 200) + ".zip").utf8.count <= 255)
    }

    @Test("A taken name gets Chrome's numbering, compound extensions kept whole")
    func numbering() {
        var taken: Set<String> = ["report.pdf", "report (1).pdf", "logs.tar.gz", "README"]
        func destination(_ name: String) -> String {
            DownloadRules.destination(for: name, in: folder) { taken.contains($0.lastPathComponent) }.lastPathComponent
        }
        #expect(destination("report.pdf") == "report (2).pdf")
        #expect(destination("logs.tar.gz") == "logs (1).tar.gz")
        #expect(destination("README") == "README (1)")
        #expect(destination("new.zip") == "new.zip")
        taken.insert("new.zip")
        #expect(destination("new.zip") == "new (1).zip")
        #expect(DownloadRules.destination(for: "a.txt", in: folder) { _ in false }.deletingLastPathComponent().path == folder.path)
    }

    @Test("The folder is Settings' choice, ~/Downloads without one")
    func folderFromSettings() {
        #expect(DownloadRules.folder(setting: nil, downloads: folder) == folder)
        #expect(DownloadRules.folder(setting: "", downloads: folder) == folder)
        #expect(DownloadRules.folder(setting: "/Volumes/Data/In", downloads: folder).path == "/Volumes/Data/In")
    }

    private func profile() throws -> FakeProfile {
        let engine = FakeApplication()
        try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        return try engine.profile(named: "Default")
    }

    @Test("Two downloads of one name at once never share a file; the list is newest first and goes to the folder")
    func concurrentNames() throws {
        let list = DownloadList()
        list.folder = { folder }
        list.fileExists = { _ in false }
        let profile = try profile()
        profile.downloadsDelegate = list
        let first = profile.simulateDownload(url: URL(string: "https://a.example/file.zip")!, totalBytes: 100)
        let second = profile.simulateDownload(url: URL(string: "https://b.example/file.zip")!, totalBytes: 100)
        #expect(list.rows.map(\.id) == [second, first])
        #expect(profile.downloads[first]?.destination?.lastPathComponent == "file.zip")
        #expect(profile.downloads[second]?.destination?.lastPathComponent == "file (1).zip")
        #expect(list.rows.allSatisfy { $0.destination?.deletingLastPathComponent().path == folder.path })
        #expect(list.rows.allSatisfy { $0.profileName == "Default" })
    }

    @Test("The ring adds up downloads in progress; a finished one bumps the badge until seen; Clear keeps what is running")
    func progressBadgeAndClear() throws {
        let list = DownloadList()
        list.folder = { folder }
        list.fileExists = { _ in false }
        var completed: [String] = []
        list.onComplete = { completed.append($0.id) }
        let profile = try profile()
        profile.downloadsDelegate = list
        #expect(list.progress == nil)
        let a = profile.simulateDownload(url: URL(string: "https://a.example/a.bin")!, totalBytes: 100)
        let b = profile.simulateDownload(url: URL(string: "https://a.example/b.bin")!, totalBytes: 300)
        profile.advanceDownload(id: a, by: 50)
        profile.advanceDownload(id: b, by: 50)
        #expect(list.progress == 0.25)
        let c = profile.simulateDownload(url: URL(string: "https://a.example/c.bin")!)
        #expect(list.progress == -1)
        profile.cancelDownload(id: c)
        profile.advanceDownload(id: a, by: 50)
        #expect(completed == [a])
        #expect(list.unseenCompleted == 1)
        #expect(list.progress == 50.0 / 300)
        list.markSeen()
        #expect(list.unseenCompleted == 0)
        #expect(list.canClear)
        list.clear()
        #expect(list.rows.map(\.id) == [b])
        list.cancel(b)
        #expect(list.row(b)?.item.state == .cancelled)
        #expect(list.progress == nil)
    }

    @Test("The row's line: progress with speed and time left, size when done, Cancelled, Failed")
    func detail() {
        var item = DownloadItem(id: "1", url: URL(string: "https://a.example/x")!, suggestedFilename: "x", receivedBytes: 1_000_000,
                                totalBytes: 5_000_000, currentSpeed: 1_000_000)
        #expect(DownloadRules.detail(for: item) == "1 MB of 5 MB — 1 MB/s, 4 s left")
        item.state = .complete
        #expect(DownloadRules.detail(for: item) == "5 MB")
        item.state = .cancelled
        #expect(DownloadRules.detail(for: item) == "Cancelled")
        item.state = .interrupted
        #expect(DownloadRules.detail(for: item) == "Failed")
    }
}
