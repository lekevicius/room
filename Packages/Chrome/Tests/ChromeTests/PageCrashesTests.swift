import Foundation
import Engine
import FakeEngine
import Testing
@testable import Chrome

@Suite("The crashed-page view (processGone, 2.6b)")
struct PageCrashesTests {
    private func page() throws -> FakeWebContents {
        let engine = FakeApplication()
        try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        let page = try engine.profile(named: "Default").makeWebContents()
        page.load(URL(string: "https://a.example/")!)
        return page
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test("A crashed page shows the view until it reloads; a normal exit is not a crash")
    func crashUntilReload() async throws {
        let chrome = PageChrome()
        let page = try page()
        page.uiDelegate = chrome
        let id = ObjectIdentifier(page)
        page.simulateCrash(.normal)
        #expect(chrome.crashes.status(of: id) == nil)
        page.simulateCrash(.killed)
        #expect(chrome.crashes.status(of: id) == .killed)
        await settle()
        #expect(chrome.crashes.status(of: id) == .killed)
        chrome.crashes.reload(id)
        #expect(chrome.crashes.status(of: id) == nil)
        #expect(!page.isCrashed)
    }

    @Test("A navigation away from the crashed page ends it")
    func navigationEndsCrash() async throws {
        let chrome = PageChrome()
        let page = try page()
        page.uiDelegate = chrome
        page.loadsSynchronously = false
        page.simulateCrash(.crashed)
        await settle()
        page.load(URL(string: "https://b.example/")!)
        await settle()
        #expect(chrome.crashes.status(of: ObjectIdentifier(page)) == nil)
    }
}
