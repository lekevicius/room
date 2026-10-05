import AppKit
import Engine
import FakeEngine
import Model
import Omnibox
import Testing
@testable import Palette

@MainActor
private func settle(until condition: () -> Bool = { false }) async {
    for _ in 0..<500 {
        if condition() { return }
        await Task.yield()
    }
}

/// The palette on an engine with an omnibox (ROADMAP 3.5 tasks 2–3).
@MainActor
private func engineFixture() throws -> (PaletteFixture, FakeProfile, FakeHistory) {
    let f = try PaletteFixture()
    let profile = try f.engine.profile(named: "Default")
    let history = FakeHistory()
    profile.fakeHistory = history
    profile.providesAutocomplete = true
    f.palette.makeAutocomplete = { [unowned f] id in f.tabs.engineProfiles[id]?.makeAutocompleteController() }
    f.palette.engineHistory = { [unowned f] id in f.tabs.engineProfiles[id]?.history }
    f.palette.suggestionsEnabled = { false }
    return (f, profile, history)
}

@Suite("Palette 3.5: Chrome's history and suggestions through the engine")
struct PaletteEngineTests {
    @Test("History rows and inline completion come from the engine; the store's table is not asked")
    func historyFromEngine() throws {
        let (f, profile, history) = try engineFixture()
        history.addVisit(URL(string: "https://github.com/")!, title: "GitHub", transition: .typed)
        history.addVisit(URL(string: "https://github.com/apple/swift")!, title: "apple/swift")
        try f.store.history.recordVisitNow(url: "https://git-local-only.example/", title: "Local only", transition: .typed, profile: f.space.profileID)
        f.palette.toggleNew()
        f.palette.setText("gi")
        #expect(f.palette.usesEngineAutocomplete)
        #expect(f.palette.result.inlineCompletion == "thub.com")
        let rows = f.palette.result.matches.filter { $0.provider == .history }
        #expect(Set(rows.compactMap(\.action.url)) == ["https://github.com/", "https://github.com/apple/swift"])
        #expect(!f.palette.result.matches.contains { $0.action.url == "https://git-local-only.example/" })
        #expect(profile.autocompleteControllers.count == 1)
    }

    @Test("Suggestions off: SearchProvider is never asked; on: asked per keystroke and its suggestions join the search group; off again drops them")
    func switchRule() throws {
        let f = try PaletteFixture()
        let profile = try f.engine.profile(named: "Default")
        profile.fakeHistory = FakeHistory()
        profile.providesAutocomplete = true
        f.palette.makeAutocomplete = { [unowned f] id in f.tabs.engineProfiles[id]?.makeAutocompleteController() }
        var enabled = false
        f.palette.suggestionsEnabled = { enabled }
        f.palette.toggleNew()
        f.palette.setText("swift")
        let controller = try #require(profile.autocompleteControllers.first)
        controller.suggestions = { ["\($0) concurrency", "\($0) tutorial"] }
        f.palette.setText("swift ")
        #expect(controller.starts.allSatisfy { !$0.providers.contains(.search) })
        #expect(!f.palette.result.matches.contains { $0.provider == .suggest })

        enabled = true
        f.palette.setText("swift c")
        #expect(controller.starts.last?.providers.contains(.search) == true)
        #expect(f.palette.result.matches.filter { $0.provider == .suggest }.map(\.title) == ["swift c concurrency", "swift c tutorial"])

        enabled = false
        let stops = controller.stops
        f.palette.suggestionsSettingChanged()
        #expect(controller.stops > stops)
        #expect(!f.palette.result.matches.contains { $0.provider == .suggest })
        f.palette.setText("swift co")
        #expect(controller.starts.last?.providers.contains(.search) == false)
    }

    @Test("⌘Y lists the engine's history, most recent first")
    func commandY() async throws {
        let (f, _, history) = try engineFixture()
        let now = Date()
        for hour in 1...3 { history.addVisit(URL(string: "https://news.example/")!, title: "News", at: now.addingTimeInterval(Double(-hour) * 3_600)) }
        history.addVisit(URL(string: "https://latest.example/")!, title: "Latest", at: now)
        f.palette.toggleHistory()
        await settle { f.palette.result.matches.count == 2 }
        #expect(f.palette.result.matches.map(\.title) == ["Latest", "News"])
    }

    @Test("⇧Delete on an engine history row deletes it in the engine's history")
    func deleteRow() throws {
        let (f, _, history) = try engineFixture()
        history.addVisit(URL(string: "https://delete.example/page")!, title: "Delete me")
        f.palette.toggleNew()
        f.palette.setText("delete")
        let index = try #require(f.palette.result.matches.firstIndex { $0.action.url == "https://delete.example/page" })
        #expect(f.palette.deleteSuggestion(at: index))
        #expect(history.entries["https://delete.example/page"] == nil)
        #expect(!f.palette.result.matches.contains { $0.action.url == "https://delete.example/page" })
    }
}
