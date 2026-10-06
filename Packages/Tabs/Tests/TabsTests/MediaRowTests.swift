import AppKit
import Engine
import FakeEngine
import Model
import Sidebar
import Testing
@testable import Tabs

@Suite("Media row (spec §F, §I.5; ROADMAP 4.6)")
struct MediaRowTests {
    private let a = UUID(), b = UUID(), c = UUID()

    @Test("The most recent session that is not on screen, audible or playing or paused; nothing else")
    func rule() {
        typealias C = MediaRowRule.Candidate
        let candidates = [
            C(entry: a, isAudible: true, playback: nil, startedAt: 1),
            C(entry: b, isAudible: false, playback: .paused, startedAt: 3),
            C(entry: c, isAudible: false, playback: .none, startedAt: 4),
        ]
        #expect(MediaRowRule.choose(candidates, visible: [], dismissedAt: nil) == b, "the most recent; a .none session is not media")
        #expect(MediaRowRule.choose(candidates, visible: [b], dismissedAt: nil) == a, "the selected entry never shows")
        #expect(MediaRowRule.choose(candidates, visible: [a, b], dismissedAt: nil) == nil)
        #expect(MediaRowRule.choose([C(entry: c, isAudible: false, playback: nil, startedAt: 9)], visible: [], dismissedAt: nil) == nil,
                "a silent page without a session")
    }

    @Test("× hides the row until a session starts after it")
    func dismissal() {
        typealias C = MediaRowRule.Candidate
        let playing = [C(entry: a, isAudible: true, playback: .playing, startedAt: 2)]
        #expect(MediaRowRule.choose(playing, visible: [], dismissedAt: 2) == nil)
        #expect(MediaRowRule.choose(playing + [C(entry: b, isAudible: false, playback: .playing, startedAt: 3)], visible: [], dismissedAt: 2) == b)
        #expect(MediaRowRule.choose([C(entry: a, isAudible: true, playback: .playing, startedAt: 5)], visible: [], dismissedAt: 2) == a)
    }

    @Test("On the fake: a session in a background tab shows the row; its buttons call the engine's controls; selecting it hides the row")
    func controller() async throws {
        let f = try TabssFixture()
        let music = try f.fixture.today("https://music.example/", title: "Music")
        let other = try f.fixture.today("https://other.example/", title: "Other")
        try f.fixture.select(music.id)
        let page = try #require(f.fixture.page(music.id))
        page.simulateMediaSession(MediaSessionInfo(title: "Song", artist: "Band", playbackState: .playing, actions: [.play, .pause, .nextTrack]))
        page.simulateAudio(true)
        await f.fixture.settle()
        #expect(f.fixture.tabs.mediaRow == nil, "the selected entry's media shows no row")

        try f.fixture.select(other.id)
        await f.fixture.settle()
        let row = try #require(f.fixture.tabs.mediaRow)
        #expect(row.entry == music.id && row.title == "Song" && row.subtitle == "Band" && row.isPlaying && row.canGoNext)
        #expect(f.fixture.sidebar.mediaRowContent == row)

        f.fixture.tabs.performMediaRowAction(.playPause, entry: music.id)
        await f.fixture.settle()
        #expect(page.mediaControls == [.pause])
        #expect(f.fixture.tabs.mediaRow?.isPlaying == false, "paused with its session: the row stays, showing Play")
        f.fixture.tabs.performMediaRowAction(.playPause, entry: music.id)
        f.fixture.tabs.performMediaRowAction(.next, entry: music.id)
        #expect(page.mediaControls == [.pause, .play, .nextTrack])

        f.fixture.tabs.performMediaRowAction(.select, entry: music.id)
        await f.fixture.settle()
        #expect(f.fixture.tabs.currentEntryID == music.id)
        #expect(f.fixture.tabs.mediaRow == nil)
    }

    @Test("On the fake: × hides the row until a page starts playing again; the most recent session wins")
    func controllerDismissal() async throws {
        let f = try TabssFixture()
        let one = try f.fixture.today("https://one.example/", title: "One")
        let two = try f.fixture.today("https://two.example/", title: "Two")
        let shown = try f.fixture.today("https://shown.example/", title: "Shown")
        try f.fixture.select(one.id)
        try f.fixture.select(two.id)
        try f.fixture.select(shown.id)
        let first = try #require(f.fixture.page(one.id)), second = try #require(f.fixture.page(two.id))
        first.simulateAudio(true)
        await f.fixture.settle()
        #expect(f.fixture.tabs.mediaRow?.entry == one.id, "audible without a session")
        #expect(f.fixture.tabs.mediaRow?.title == first.title ?? "one.example", "no session: the page's title")
        second.simulateMediaSession(MediaSessionInfo(title: "Later", playbackState: .playing))
        await f.fixture.settle()
        #expect(f.fixture.tabs.mediaRow?.entry == two.id, "the most recent session")

        f.fixture.tabs.performMediaRowAction(.dismiss, entry: two.id)
        #expect(f.fixture.tabs.mediaRow == nil)
        #expect(f.fixture.sidebar.mediaRowContent == nil)
        first.simulateAudio(false)
        await f.fixture.settle()
        first.simulateAudio(true)
        await f.fixture.settle()
        #expect(f.fixture.tabs.mediaRow?.entry == one.id, "a new start after × shows the row again")
    }
}

/// `TabsFixture` held by a reference the tests keep for their whole body.
private final class TabssFixture {
    let fixture: TabsFixture
    init() throws { fixture = try TabsFixture() }
}
