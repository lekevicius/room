import AppKit
import Engine
import FakeEngine
import Model
import Omnibox
import Synchronization
import Testing
@testable import Palette

/// A clipboard whose URL detection and reads the test sees.
final class FakeClipboard: PaletteClipboard {
    var text: String?
    var changeCount = 0
    private(set) var reads = 0
    private(set) var detections = 0

    func set(_ text: String?) {
        self.text = text
        changeCount += 1
    }

    func detectURL(_ completion: @escaping @MainActor (Bool) -> Void) {
        detections += 1
        completion(text.flatMap(URLFixup.url(from:)) != nil)
    }

    func readString() -> String? {
        reads += 1
        return text
    }
}

/// Answers every suggestion request with a fixed list and counts requests.
final class CountingTransport: SuggestTransport, Sendable {
    private let count = Mutex(0)
    var requests: Int { count.withLock { $0 } }

    func data(for request: URLRequest) async throws -> Data {
        count.withLock { $0 += 1 }
        return Data(#"["swi", ["swift", "swiftui", "swimming"]]"#.utf8)
    }
}

/// The debounce elapses when the test says so.
final class Gate: Sendable {
    private let waiting = Mutex<[CheckedContinuation<Void, Never>]>([])
    var count: Int { waiting.withLock { $0.count } }
    var sleep: SuggestClient.Sleep { { [self] _ in await withCheckedContinuation { c in waiting.withLock { $0.append(c) } } } }
    func release() { waiting.withLock { list in defer { list = [] }; return list }.forEach { $0.resume() } }
}

@MainActor
private func settle(until condition: () -> Bool = { false }) async {
    for _ in 0..<500 {
        if condition() { return }
        await Task.yield()
    }
}

@Suite("Palette 2.4b: commands, site search, history, suggest, Paste & Go (spec §C)")
struct Palette2_4bTests {
    @Test("Opening builds no sidebar snapshot; the first keystroke does, once per open")
    func lazyContext() throws {
        let f = try PaletteFixture()
        try f.selectedTab("https://a.example")
        f.palette.toggleNew()
        #expect(f.palette.contextBuilds == 0)
        f.palette.toggleNew()
        f.palette.toggleEdit(docked: false)
        #expect(f.palette.contextBuilds == 0)
        f.palette.setText("a")
        f.palette.setText("ab")
        #expect(f.palette.contextBuilds == 1)
    }

    @Test("Tab from an empty field enters commands; Enter runs the highlighted one after closing")
    func commandsMode() throws {
        let f = try PaletteFixture()
        var ran: [String] = []
        f.palette.commands = { CommandRegistry.all }
        f.palette.onCommand = { ran.append($0) }
        f.palette.toggleNew()
        f.palette.tab()
        #expect(f.palette.typedText == ">")
        #expect(f.palette.result.matches.count == OmniboxResult.limit)
        #expect(f.palette.result.matches.allSatisfy { $0.provider == .commands })
        f.palette.setText(">reopen")
        f.palette.commit(modifier: .none)
        #expect(!f.palette.isOpen)
        #expect(ran == ["reopen-closed-tab"])
    }

    @Test("yt then Tab puts the YouTube chip in the field; Enter searches YouTube; Backspace on empty leaves it")
    func siteSearch() throws {
        let f = try PaletteFixture()
        f.palette.toggleNew()
        f.palette.setText("yt")
        f.palette.tab()
        #expect(f.palette.siteSearch?.name == "YouTube")
        #expect(f.palette.typedText.isEmpty)
        #expect(f.palette.result.isEmpty)
        #expect(f.palette.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.deleteBackward(_:))))
        #expect(f.palette.siteSearch == nil)

        f.palette.setText("yt")
        f.palette.tab()
        f.palette.setText("lofi beats")
        f.palette.commit(modifier: .none)
        #expect(f.today.map(\.currentURL) == ["https://www.youtube.com/results?search_query=lofi%20beats"])
    }

    @Test("Tab after text that is not a keyword still cycles groups")
    func tabCycles() throws {
        let f = try PaletteFixture()
        let work = try f.store.sidebar.createSpace(name: "Work", profile: f.space.profileID)
        try f.store.sidebar.addEntry(.today, url: "https://linear.app", title: "Linear", space: work.id)
        f.palette.toggleNew()
        f.palette.setText("linear")
        f.palette.tab()
        #expect(f.palette.siteSearch == nil)
        #expect(f.palette.highlightedIndex == 1)
    }

    @Test("Visited pages come back as history rows; a typed host completes inline; ⇧Delete removes it and it does not complete again")
    func historyAndDelete() async throws {
        let f = try PaletteFixture()
        try f.store.history.recordVisitNow(url: "https://news.ycombinator.com/", title: "Hacker News", transition: .typed, profile: f.space.profileID)
        try f.store.history.recordVisitNow(url: "https://news.ycombinator.com/item?id=1", title: "A story", transition: .link, profile: f.space.profileID)
        f.palette.toggleNew()
        f.palette.setText("new")
        #expect(f.palette.result.inlineCompletion == "s.ycombinator.com")
        #expect(f.palette.result.matches.first?.isDeletable == true)
        #expect(f.palette.deleteHighlightedSuggestion())
        #expect(try f.store.history.count() == 0)
        #expect(f.palette.result.inlineCompletion == nil)
        #expect(f.palette.result.matches.allSatisfy { $0.provider != .history })
        // The verbatim row is not removable: the key edits text instead.
        #expect(!f.palette.deleteHighlightedSuggestion())
    }

    @Test("Committed palette URLs reach history as typed, searches as generated")
    func transitions() async throws {
        let f = try PaletteFixture()
        f.palette.toggleNew()
        f.palette.setText("example.com")
        f.palette.commit(modifier: .none)
        f.palette.toggleNew()
        f.palette.setText("room browser")
        f.palette.commit(modifier: .none)
        await f.settle()
        try f.store.history.recordVisitNow(url: "https://barrier.invalid/", title: nil, transition: .link, profile: f.space.profileID)
        #expect(try f.store.history.visits(url: "https://example.com", profile: f.space.profileID).map(\.1) == [.typed])
        #expect(try f.store.history.visits(url: "https://www.google.com/search?q=room%20browser", profile: f.space.profileID).map(\.1) == [.generated])
    }

    @Test("Suggestions join the search group when they arrive, keeping the highlighted row; switched off, they go and nothing is sent")
    func suggestions() async throws {
        let f = try PaletteFixture()
        let transport = CountingTransport(), gate = Gate()
        var enabled = true
        f.palette.suggestionsEnabled = { enabled }
        f.palette.suggest = SuggestClient(transport: transport, debounce: .milliseconds(120), sleep: gate.sleep)
        f.palette.toggleNew()
        f.palette.setText("swi")
        await settle { gate.count == 1 }
        #expect(transport.requests == 0)
        f.palette.moveHighlight(0)
        let highlighted = f.palette.result.matches[f.palette.highlightedIndex ?? 0].id
        gate.release()
        await settle { f.palette.result.matches.contains { $0.provider == .suggest } }
        #expect(f.palette.result.matches.filter { $0.provider == .suggest }.map(\.title) == ["swift", "swiftui", "swimming"])
        #expect(f.palette.result.matches[f.palette.highlightedIndex ?? 0].id == highlighted)
        #expect(f.palette.result.matches.first?.provider == .verbatim)

        // A longer query keeps the suggestions that still fit until new ones arrive.
        f.palette.setText("swift")
        #expect(f.palette.result.matches.filter { $0.provider == .suggest }.map(\.title) == ["swiftui"])

        // "swift" waits in its debounce when the switch goes off.
        await settle { gate.count == 1 }
        enabled = false
        f.palette.suggestionsSettingChanged()
        #expect(!f.palette.result.matches.contains { $0.provider == .suggest })
        f.palette.setText("swiftl")
        await settle()
        #expect(gate.count == 1)
        gate.release()
        await settle()
        #expect(transport.requests == 1)
    }

    @Test("Paste & Go: shown on an empty ⌘T when the clipboard holds a URL, read only when chosen")
    func pasteAndGo() throws {
        let f = try PaletteFixture()
        f.clipboard.set("https://swift.org/blog")
        f.palette.toggleNew()
        #expect(f.palette.result.matches.map(\.title) == ["Paste and Go"])
        #expect(f.clipboard.reads == 0)
        f.palette.commit(modifier: .none)
        #expect(f.clipboard.reads == 1)
        #expect(f.today.map(\.currentURL) == ["https://swift.org/blog"])

        // Not a URL: no row. ⌘L never offers it.
        f.clipboard.set("just words")
        f.palette.toggleNew()
        #expect(f.palette.result.isEmpty)
        f.palette.dismiss()
        f.clipboard.set("https://example.com")
        f.palette.toggleEdit(docked: false)
        #expect(f.palette.result.isEmpty)
        #expect(f.clipboard.reads == 1)
    }
}

@Suite("Palette 2.4b: ⌘Y")
struct PaletteHistoryKeyTests {
    @Test("⌘Y opens the palette on the most frecent history; typing searches as usual; again closes")
    func recentHistory() throws {
        let f = try PaletteFixture()
        try f.store.history.recordVisitNow(url: "https://swift.org/", title: "Swift", transition: .typed, profile: f.space.profileID)
        try f.store.history.recordVisitNow(url: "https://example.com/", title: "Example", transition: .link, profile: f.space.profileID)
        f.palette.toggleHistory()
        #expect(f.palette.result.matches.map(\.action.url) == ["https://swift.org/", "https://example.com/"])
        f.palette.setText("exa")
        #expect(f.palette.result.matches.first?.provider == .verbatim)
        f.palette.toggleHistory()
        #expect(!f.palette.isOpen)
        f.palette.toggleNew()
        #expect(f.palette.result.isEmpty)
    }
}
