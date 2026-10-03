import AppKit
import Design
import Engine
import FakeEngine
import Testing
@testable import Chrome

@Suite("Find in page: the count and stepping (spec §C)")
struct FindTests {
    @Test("The count reads “3 of 12”, “No results” once the engine has finished, nothing before there is text or a result")
    func label() {
        #expect(FindRules.label(text: "", result: FindResult(matchCount: 4, activeMatch: 1, isFinal: true)) == "")
        #expect(FindRules.label(text: "room", result: nil) == "")
        #expect(FindRules.label(text: "room", result: FindResult(matchCount: 12, activeMatch: 3, isFinal: true)) == "3 of 12")
        #expect(FindRules.label(text: "room", result: FindResult(matchCount: 12, activeMatch: 0, isFinal: false)) == "1 of 12")
        #expect(FindRules.label(text: "zzz", result: FindResult(matchCount: 0, activeMatch: 0, isFinal: false)) == "")
        #expect(FindRules.label(text: "zzz", result: FindResult(matchCount: 0, activeMatch: 0, isFinal: true)) == "No results")
        #expect(!FindRules.canStep(text: "zzz", result: FindResult(matchCount: 0, activeMatch: 0, isFinal: true)))
        #expect(!FindRules.canStep(text: "", result: nil))
        #expect(FindRules.canStep(text: "room", result: nil))
    }

    @Test("Typing finds, ⌘G / ⇧⌘G step through the matches and wrap; each page keeps its own text")
    func steppingOnFakeEngine() throws {
        let engine = FakeApplication()
        try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        let profile = try engine.profile(named: "Default")
        let page = profile.makeWebContents()
        page.load(URL(string: "https://room.example/a")!)
        let other = profile.makeWebContents()
        other.load(URL(string: "https://other.example/b")!)
        // FakeEngine finds in the lines its page view shows: the URL and the title.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let find = FindController(host: host)
        find.setPage(page)
        find.showFindBar()
        let field = try #require((find.barView as? FindBarView)?.field)
        field.stringValue = "room"
        (find.barView as? FindBarView)?.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        #expect(page.findResult == FindResult(matchCount: 2, activeMatch: 1, isFinal: true))
        find.findNext(forward: true)
        #expect(page.findResult?.activeMatch == 2)
        find.findNext(forward: true)
        #expect(page.findResult?.activeMatch == 1)
        find.findNext(forward: false)
        #expect(page.findResult?.activeMatch == 2)
        find.setPage(other)
        #expect(!find.isVisible)
        find.setPage(page)
        #expect(find.isVisible)
        #expect((find.barView as? FindBarView)?.field.stringValue == "room")
        find.close()
        #expect(!find.isVisible)
        #expect(page.findResult == nil)
        withExtendedLifetime(host) {}
    }
}

@Suite("Zoom: Chrome's preset steps (ROADMAP 2.6 task 3)")
struct ZoomTests {
    @Test("⌘= and ⌘- move to the next preset and stop at 25% and 500%; a factor between presets goes to the nearest one beyond it")
    func steps() {
        #expect(ZoomRules.zoomIn(from: 1) == 1.1)
        #expect(ZoomRules.zoomOut(from: 1) == 0.9)
        #expect(ZoomRules.zoomIn(from: 1.2) == 1.25)
        #expect(ZoomRules.zoomOut(from: 1.2) == 1.1)
        #expect(ZoomRules.zoomIn(from: 5) == 5)
        #expect(ZoomRules.zoomOut(from: 0.25) == 0.25)
        // The engine's log-scale round trip leaves factors a hair off a preset.
        #expect(ZoomRules.zoomIn(from: 1.0999999) == 1.25)
        #expect(ZoomRules.zoomOut(from: 0.90000001) == 0.8)
        #expect(ZoomRules.label(1.1) == "110%")
        #expect(ZoomRules.label(1.0 / 3) == "33%")
        #expect(ZoomRules.isDefault(1.0000001))
    }
}

@Suite("The status pill: delay, full URL, dodging (spec §I.14)")
struct StatusPillTests {
    let clock = ManualScheduler()

    @Test("A link's URL shows after 600 ms, widens after 1.5 s; leaving hides it after a grace; link to link shows at once")
    func timing() {
        let pill = StatusPillState(scheduler: clock)
        pill.setStatus("https://a.example/long/path")
        clock.advance(by: 0.59)
        #expect(!pill.isVisible)
        clock.advance(by: 0.02)
        #expect(pill.shownText == "https://a.example/long/path")
        #expect(pill.width == .standard)
        clock.advance(by: 1.49)
        #expect(pill.width == .standard)
        clock.advance(by: 0.02)
        #expect(pill.width == .full)
        pill.setStatus("https://b.example/")
        #expect(pill.shownText == "https://b.example/")
        #expect(pill.width == .standard)
        pill.setStatus(nil)
        clock.advance(by: 0.05)
        pill.setStatus("https://c.example/")
        #expect(pill.shownText == "https://c.example/")
        pill.setStatus(nil)
        clock.advance(by: 0.1)
        #expect(!pill.isVisible)
    }

    @Test("Hovering briefly shows nothing; an empty status counts as none")
    func briefHover() {
        let pill = StatusPillState(scheduler: clock)
        pill.setStatus("https://a.example/")
        clock.advance(by: 0.3)
        pill.setStatus("")
        clock.advance(by: 1)
        #expect(!pill.isVisible)
    }

    @Test("The pointer near the bottom-left pill moves it bottom-right; it comes back when the pointer leaves; near both it stays")
    func dodge() {
        let pill = StatusPillState(scheduler: clock)
        pill.setStatus("https://a.example/")
        clock.advance(by: 0.6)
        pill.pointerMoved(nearLeading: true, nearTrailing: false)
        #expect(pill.side == .trailing)
        pill.pointerMoved(nearLeading: true, nearTrailing: true)
        #expect(pill.side == .trailing)
        pill.pointerMoved(nearLeading: false, nearTrailing: true)
        #expect(pill.side == .leading)
        pill.pointerMoved(nearLeading: false, nearTrailing: false)
        #expect(pill.side == .leading)
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 600)
        let leading = StatusPillRules.frame(side: .leading, width: .standard, textWidth: 150, bounds: bounds)
        #expect(leading.minX == StatusPillMetrics.inset && leading.maxY == 600 - StatusPillMetrics.inset)
        #expect(StatusPillRules.isNear(CGPoint(x: leading.maxX + 10, y: leading.midY), leading))
        #expect(!StatusPillRules.isNear(CGPoint(x: leading.maxX + 40, y: leading.midY), leading))
        #expect(StatusPillRules.frame(side: .leading, width: .standard, textWidth: 2000, bounds: bounds).width == 300)
        #expect(StatusPillRules.frame(side: .trailing, width: .full, textWidth: 2000, bounds: bounds).maxX == 900 - StatusPillMetrics.inset)
    }
}
