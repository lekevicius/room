import AppKit
import Engine
import Sidebar

/// Which page the footer's media row shows (spec §F, §I.5; 4.6). Pure.
public enum MediaRowRule {
    /// A loaded page as the rule sees it.
    public struct Candidate: Equatable, Sendable {
        public var entry: UUID
        public var isAudible: Bool
        /// `nil`: the page has no media session.
        public var playback: MediaSessionInfo.PlaybackState?
        /// The media clock's value when the page last started playing (or its session appeared).
        public var startedAt: Int

        public init(entry: UUID, isAudible: Bool, playback: MediaSessionInfo.PlaybackState?, startedAt: Int) {
            self.entry = entry
            self.isAudible = isAudible
            self.playback = playback
            self.startedAt = startedAt
        }
    }

    /// Playing, for the start stamp: audible, or a session that plays.
    public static func isPlaying(isAudible: Bool, playback: MediaSessionInfo.PlaybackState?) -> Bool {
        isAudible || playback == .playing
    }

    /// The page for the row: audible or with a playing or paused session,
    /// not on screen (the selected entry, a shown split's panes), started
    /// after the last × (`dismissedAt`); of those the most recent session.
    public static func choose(_ candidates: [Candidate], visible: Set<UUID>, dismissedAt: Int?) -> UUID? {
        candidates
            .filter { candidate in
                !visible.contains(candidate.entry)
                    && (candidate.isAudible || candidate.playback == .playing || candidate.playback == .paused)
                    && dismissedAt.map { candidate.startedAt > $0 } ?? true
            }
            .max { ($0.startedAt, $0.entry.uuidString) < ($1.startedAt, $1.entry.uuidString) }?
            .entry
    }
}

// MARK: - The row's model

extension TabController {
    /// Re-evaluates the row on the next main-actor turn (several page changes in one turn make one pass).
    func setNeedsMediaRowUpdate() {
        guard !mediaRowUpdatePending else { return }
        mediaRowUpdatePending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            mediaRowUpdatePending = false
            updateMediaRow()
        }
    }

    /// Stamps a start on the media clock: the page plays after not playing,
    /// or has a session where it had none. Called from the page's
    /// observation (`track`), so each change is seen in order.
    func noteMediaState(_ page: Page) {
        let contents = page.contents
        let session = contents.state == .closed ? nil : contents.mediaSession
        let playing = MediaRowRule.isPlaying(isAudible: contents.isAudible, playback: session?.playbackState)
        if (playing && !page.mediaWasPlaying) || (session != nil && !page.mediaHadSession) {
            mediaClock += 1
            page.mediaStartedAt = mediaClock
        }
        page.mediaWasPlaying = playing
        page.mediaHadSession = session != nil
        setNeedsMediaRowUpdate()
    }

    /// Chooses the row's page and hands its content to the sidebar.
    func updateMediaRow() {
        let candidates = pages.map { entry, page in
            let contents = page.contents
            let session = contents.state == .closed ? nil : contents.mediaSession
            return MediaRowRule.Candidate(entry: entry, isAudible: contents.isAudible, playback: session?.playbackState,
                                          startedAt: page.mediaStartedAt)
        }
        let chosen = MediaRowRule.choose(candidates, visible: visibleEntryIDs, dismissedAt: mediaDismissedAt)
        let content = chosen.flatMap { mediaRowContent(for: $0) }
        guard content != mediaRow else { return }
        mediaRow = content
        sidebar?.setMediaRow(content)
    }

    private func mediaRowContent(for entry: UUID) -> MediaRowContent? {
        guard let page = pages[entry] else { return nil }
        let contents = page.contents
        let session = contents.mediaSession
        let host = contents.url?.host() ?? store.sidebar.entry(entry).flatMap { URL(string: $0.liveURL ?? $0.storedURL ?? "")?.host() } ?? ""
        let title = session.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? contents.title ?? host
        let artist = session.map(\.artist).flatMap { $0.isEmpty ? nil : $0 } ?? host
        let playing = session.map { $0.playbackState == .playing } ?? contents.isAudible
        return MediaRowContent(entry: entry, title: title, subtitle: artist == title ? "" : artist,
                               image: artworkImage(session?.artwork) ?? page.favicon ?? contents.favicon,
                               isPlaying: playing, canGoNext: session?.actions.contains(.nextTrack) ?? false)
    }

    /// The session's artwork as an image, decoded once per artwork.
    private func artworkImage(_ data: Data?) -> NSImage? {
        guard let data else { return nil }
        if let cached = mediaArtwork, cached.data == data { return cached.image }
        let image = NSImage(data: data)
        mediaArtwork = image.map { (data, $0) }
        return image
    }

    /// A click on the media row (the app wires the sidebar's row here).
    public func performMediaRowAction(_ action: MediaRowAction, entry: UUID) {
        let contents = pages[entry]?.contents
        switch action {
        case .playPause:
            guard let contents else { return }
            let playing = contents.mediaSession.map { $0.playbackState == .playing } ?? contents.isAudible
            if playing { contents.mediaPause() } else { contents.mediaPlay() }
        case .next:
            contents?.mediaNextTrack()
        case .dismiss:
            // Hidden until a page starts playing again (the next session).
            mediaDismissedAt = mediaClock
            updateMediaRow()
        case .select:
            sidebar?.reveal(entry)
        }
    }
}
