import AppKit
import Engine
import FakeEngine
import Testing

/// The media session controls (4.6): the fake records what the host called
/// and moves the session as a page whose handlers play and pause would.
@Suite("Media session controls")
struct MediaSessionControlTests {
    @Test func controlsAreRecordedAndMoveThePlaybackState() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.simulateMediaSession(MediaSessionInfo(title: "One", artist: "Room", playbackState: .playing,
                                                   actions: [.play, .pause, .nextTrack, .previousTrack, .seekTo],
                                                   position: .init(duration: 30, position: 4, rate: 1)))
        page.simulateAudio(true)

        page.mediaPause()
        #expect(page.mediaSession?.playbackState == .paused)
        #expect(page.mediaSession?.position?.rate == 0)
        #expect(!page.isAudible)

        page.mediaPlay()
        #expect(page.mediaSession?.playbackState == .playing)
        #expect(page.isAudible)

        page.mediaNextTrack()
        page.mediaPreviousTrack()
        page.mediaSeek(to: 12)
        #expect(page.mediaSession?.position?.position == 12)
        page.mediaSeek(to: 99)
        #expect(page.mediaSession?.position?.position == 30)
        #expect(page.mediaControls == [.pause, .play, .nextTrack, .previousTrack, .seek(12), .seek(99)])
    }

    @Test func controlsWithoutASessionChangeNothing() throws {
        let (_, profile) = try makeProfile()
        let page = profile.makeWebContents()
        page.mediaPlay()
        page.mediaSeek(to: 3)
        #expect(page.mediaSession == nil)
        #expect(!page.isAudible)
        #expect(page.mediaControls == [.play, .seek(3)])
    }
}
