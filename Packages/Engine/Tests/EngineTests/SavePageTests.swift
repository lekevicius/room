import Engine
import FakeEngine
import Foundation
import Testing

/// `WebContents.savePage(as:to:)` (4.7a): the format's file names and the
/// fake's stub files.
@Suite("Save page")
struct SavePageTests {
    @Test func completeHTMLKeepsItsResourcesBesideTheFile() {
        let file = URL(fileURLWithPath: "/tmp/Saved/Room Page.html")
        #expect(SavePageFormat.completeHTML.resourcesDirectory(for: file)?.path == "/tmp/Saved/Room Page_files")
        #expect(SavePageFormat.html.resourcesDirectory(for: file) == nil)
        #expect(SavePageFormat.mhtml.resourcesDirectory(for: file) == nil)
        #expect(SavePageFormat.mhtml.fileExtension == "mhtml")
        #expect(SavePageFormat.completeHTML.fileExtension == "html")
    }

    @Test func fakeWritesEachFormat() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(URL(string: "https://example.com/article")!)
        let directory = FileManager.default.temporaryDirectory.appending(path: "room-savepage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let complete = directory.appending(path: "Article.html")
        try await page.savePage(as: .completeHTML, to: complete)
        #expect(try String(contentsOf: complete, encoding: .utf8).contains("https://example.com/article"))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Article_files").path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        let archive = directory.appending(path: "Article.mhtml")
        try await page.savePage(as: .mhtml, to: archive)
        #expect(try String(contentsOf: archive, encoding: .utf8).hasPrefix("From: <Saved by FakeEngine>"))
        #expect(page.savedPages.map(\.format) == [.completeHTML, .mhtml])

        page.close()
        await #expect(throws: EngineError.closed) { try await page.savePage(as: .html, to: directory.appending(path: "x.html")) }
    }

    @Test func devToolsCommandsGoToTheHandlerOrAreRefused() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        await #expect(throws: EngineError.notSupported("sendDevToolsCommand(Page.captureScreenshot)")) {
            _ = try await page.sendDevToolsCommand("Page.captureScreenshot", params: [:])
        }
        page.devToolsCommandHandler = { method, params in
            ["method": method, "beyond": params["captureBeyondViewport"] as? Bool ?? false]
        }
        let result = try await page.sendDevToolsCommand("Page.captureScreenshot", params: ["captureBeyondViewport": true])
        #expect(result["beyond"] as? Bool == true)
        #expect(page.devToolsCommands == ["Page.captureScreenshot", "Page.captureScreenshot"])
    }
}
