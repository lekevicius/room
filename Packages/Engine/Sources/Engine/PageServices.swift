import Foundation

// Values for the members Phase 3.4b added: the hung-page question, external
// protocols, infobars and the translate offer, the capture state and the
// media session (docs/engine-api.md).

/// The host's answer when a page's renderer stops responding.
nonisolated public enum UnresponsiveRendererAction: Sendable, Hashable {
    /// Keep waiting; the engine asks again if the page stays hung.
    case wait
    /// End the renderer; `processGone` follows.
    case terminate
}

/// A page asks to open a URL in another application (`mailto:`, a custom
/// scheme), after the engine's own checks (an application exists for it and
/// it is not this browser).
nonisolated public struct ExternalURLRequest: Sendable, Hashable {
    public var url: URL
    /// Lowercased, without the colon.
    public var scheme: String
    /// The site that asked.
    public var initiatingOrigin: URL?
    public var isUserGesture: Bool
    /// The application macOS would open it with ("Mail").
    public var applicationName: String

    public init(url: URL, scheme: String, initiatingOrigin: URL? = nil, isUserGesture: Bool = true, applicationName: String) {
        self.url = url
        self.scheme = scheme
        self.initiatingOrigin = initiatingOrigin
        self.isUserGesture = isUserGesture
        self.applicationName = applicationName
    }
}

/// A notice the engine would show above the page: one of Chromium's
/// infobars, or its translate offer. The host shows it until the UI delegate
/// hears `didRemoveInfoBar`, and answers at most once (`press` or `dismiss`).
@MainActor
public final class InfoBar: Identifiable {
    nonisolated public enum Kind: Sendable, Hashable {
        /// Chromium's infobar with its `InfoBarIdentifier`.
        case engine(identifier: Int)
        /// "Translate this page?" (BCP 47 language codes).
        case translateOffer(source: String, target: String)
    }

    public let id: Int
    public let kind: Kind
    public let message: String
    /// Button labels, the primary first; empty when there are none.
    public let buttons: [String]
    private var handler: ((Int?) -> Void)?

    /// `handler` receives the pressed button's index, or `nil` when dismissed.
    public init(id: Int, kind: Kind, message: String, buttons: [String], handler: @escaping (Int?) -> Void) {
        self.id = id
        self.kind = kind
        self.message = message
        self.buttons = buttons
        self.handler = handler
    }

    /// `false` once answered (or withdrawn by the engine).
    public var isPending: Bool { handler != nil }

    public func press(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        finish(index)
    }

    public func dismiss() { finish(nil) }

    /// The engine removed it: later answers are ignored.
    public func withdraw() { handler = nil }

    private func finish(_ index: Int?) {
        guard let handler else { return }
        self.handler = nil
        handler(index)
    }
}

/// What a page captures now, and whether it is captured itself.
nonisolated public struct CaptureState: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let camera = CaptureState(rawValue: 1 << 0)
    public static let microphone = CaptureState(rawValue: 1 << 1)
    /// A screen.
    public static let display = CaptureState(rawValue: 1 << 2)
    /// Another tab.
    public static let tab = CaptureState(rawValue: 1 << 3)
    /// A window.
    public static let window = CaptureState(rawValue: 1 << 4)
    /// The page itself is being captured (mirrored) by another page.
    public static let mirrored = CaptureState(rawValue: 1 << 5)

    /// Sharing a screen, a window or a tab.
    public var isSharingScreen: Bool { !intersection([.display, .tab, .window]).isEmpty }
}

/// What `WebContents.stopCapturing` ends.
nonisolated public struct CaptureKinds: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// `getUserMedia`: camera and microphone.
    public static let userMedia = CaptureKinds(rawValue: 1 << 0)
    /// `getDisplayMedia`: screens, windows, tabs.
    public static let displayMedia = CaptureKinds(rawValue: 1 << 1)
    public static let all: CaptureKinds = [.userMedia, .displayMedia]
}

/// The page's media session (`navigator.mediaSession.metadata`, or what the
/// engine infers from the playing media); the footer's media row (4.6).
nonisolated public struct MediaSessionInfo: Sendable, Hashable {
    nonisolated public enum PlaybackState: Sendable, Hashable {
        case none, paused, playing
    }

    /// What the page reported about its position (`setPositionState`, or
    /// the player's own): the position when the engine made this value.
    nonisolated public struct Position: Sendable, Hashable {
        public var duration: TimeInterval
        public var position: TimeInterval
        /// 0 while paused.
        public var rate: Double

        public init(duration: TimeInterval, position: TimeInterval, rate: Double) {
            self.duration = duration
            self.position = position
            self.rate = rate
        }
    }

    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    /// The artwork image the engine fetched for the page (PNG data, in the
    /// page's network context); `nil` until it arrives.
    public var artwork: Data?
    public var playbackState: PlaybackState
    /// The actions the page supports (its action handlers; play and pause
    /// for any playing media).
    public var actions: Set<MediaSessionAction>
    public var position: Position?

    public init(title: String, artist: String = "", album: String = "", artworkURL: URL? = nil, artwork: Data? = nil,
                playbackState: PlaybackState = .none, actions: Set<MediaSessionAction> = [], position: Position? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.artwork = artwork
        self.playbackState = playbackState
        self.actions = actions
        self.position = position
    }
}

/// A media session action (`navigator.mediaSession.setActionHandler`).
nonisolated public enum MediaSessionAction: String, Sendable, Hashable, CaseIterable {
    case play, pause, previousTrack, nextTrack, seekBackward, seekForward, seekTo, stop, skipAd
}
