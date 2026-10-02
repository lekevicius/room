import AppKit
import Engine
import FakeEngine
import Observation
import Synchronization
import Testing

@Suite("Navigation state")
struct NavigationStateTests {
    @Test func newContentsIsBlank() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        #expect(page.url == nil)
        #expect(page.title == nil)
        #expect(!page.isLoading)
        #expect(!page.canGoBack && !page.canGoForward)
        #expect(page.state == .alive)
        #expect(page.securityState == .none)
    }

    @Test func loadCommitsAndFinishes() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://example.com/a"))
        #expect(page.url == url("https://example.com/a"))
        #expect(page.title == "example.com")
        #expect(!page.isLoading)
        #expect(page.loadProgress == 1)
        #expect(page.securityState.level == .secure)
        #expect(!page.canGoBack)
    }

    @Test func asynchronousLoadReportsProgressUntilFinished() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.loadsSynchronously = false
        page.load(url("http://example.org"))
        #expect(page.isLoading)
        #expect(page.loadProgress < 1)
        #expect(page.url == url("http://example.org"))
        #expect(page.title == nil)
        #expect(page.securityState.level == .insecure)
        page.finishLoading()
        #expect(!page.isLoading)
        #expect(page.title == "example.org")
    }

    @Test func stopEndsLoading() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.loadsSynchronously = false
        page.load(url("https://slow.example"))
        page.stop()
        #expect(!page.isLoading)
        #expect(page.loadProgress == 1)
    }

    @Test func backForwardWalkTheHistory() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://a.example"))
        page.load(url("https://b.example"))
        page.load(url("https://c.example"))
        #expect(page.canGoBack && !page.canGoForward)

        page.goBack()
        #expect(page.url == url("https://b.example"))
        #expect(page.canGoBack && page.canGoForward)

        page.goBack()
        #expect(page.url == url("https://a.example"))
        #expect(!page.canGoBack)
        page.goBack()
        #expect(page.url == url("https://a.example"))

        page.goForward()
        #expect(page.url == url("https://b.example"))
    }

    @Test func navigatingAfterGoingBackDropsForwardEntries() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://a.example"))
        page.load(url("https://b.example"))
        page.goBack()
        page.load(url("https://d.example"))
        #expect(page.backForwardList == [url("https://a.example"), url("https://d.example")])
        #expect(!page.canGoForward)
    }

    @Test func reloadKeepsTheEntry() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://a.example"))
        page.reloadIgnoringCache()
        #expect(page.url == url("https://a.example"))
        #expect(page.backForwardList.count == 1)
    }

    @Test func discardKeepsURLAndReloadRevives() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://a.example"))
        page.simulateAudio(true)
        try page.discard()
        #expect(page.state == .discarded)
        #expect(page.url == url("https://a.example"))
        #expect(!page.isAudible)
        page.reload()
        #expect(page.state == .alive)
        #expect(page.title == "a.example")
    }

    @Test func discardAfterCloseThrows() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.close()
        #expect(page.state == .closed)
        #expect(throws: EngineError.closed) { try page.discard() }
        page.load(url("https://a.example"))
        #expect(page.url == nil)
    }

    @Test func crashBlanksThePageUntilReload() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://a.example"))
        page.simulateCrash(.outOfMemory)
        #expect(page.isCrashed)
        page.reload()
        #expect(!page.isCrashed)
    }

    @Test func zoomIsClamped() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.zoomFactor = 1.5
        #expect(page.zoomFactor == 1.5)
        page.zoomFactor = 20
        #expect(page.zoomFactor == 5)
    }

    @Test func titleChangesAreObservable() throws {
        let (_, profile) = try makeProfile()
        let page: any WebContents = profile.makeWebContents()
        let changed = Mutex(false)
        withObservationTracking {
            _ = page.title
        } onChange: {
            changed.withLock { $0 = true }
        }
        page.load(url("https://observed.example"))
        #expect(changed.withLock { $0 })
    }

    @Test func viewShowsTheURL() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://shown.example/path"))
        let textView = try #require((page.nativeView as? NSScrollView)?.documentView as? NSTextView)
        #expect(textView.string.contains("https://shown.example/path"))
    }

    @Test func findCountsAndCyclesMatches() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://example.com/example"))
        // URL line has two, the title one more.
        page.find("EXAMPLE")
        #expect(page.findResult == FindResult(matchCount: 3, activeMatch: 1, isFinal: true))
        page.find("EXAMPLE")
        #expect(page.findResult?.activeMatch == 2)
        page.find("EXAMPLE", forward: false, matchCase: false)
        #expect(page.findResult?.activeMatch == 1)
        page.find("EXAMPLE", forward: false, matchCase: false)
        #expect(page.findResult?.activeMatch == 3)
        page.find("EXAMPLE", forward: true, matchCase: true)
        #expect(page.findResult == FindResult(matchCount: 0, activeMatch: 0, isFinal: true))
        page.stopFind(clearSelection: true)
        #expect(page.findResult == nil)
    }

    @Test func javaScriptBuiltinsAndErrors() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://js.example/"))
        #expect(try await page.executeJavaScript("document.title") == "\"js.example\"")
        #expect(try await page.executeJavaScript("location.href;") == "\"https:\\/\\/js.example\\/\"")
        await #expect(throws: EngineError.self) { try await page.executeJavaScript("1 + 1") }
        page.javaScriptHandler = { _ in "2" }
        #expect(try await page.executeJavaScript("1 + 1") == "2")
    }

    @Test func captureViewportMatchesViewSize() async throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.load(url("https://capture.example"))
        page.nativeView.frame = NSRect(x: 0, y: 0, width: 320, height: 200)
        let image = try await page.captureViewport()
        #expect(image.size == NSSize(width: 320, height: 200))
    }

    @Test func devToolsOpenInTheHostViewAndClose() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let devTools = try #require(page.devTools)
        devTools.inspectElement(at: NSPoint(x: 10, y: 10), in: host)
        #expect(devTools.isOpen)
        #expect(host.subviews.count == 1)
        devTools.close()
        #expect(!devTools.isOpen)
        #expect(host.subviews.isEmpty)
    }
}
