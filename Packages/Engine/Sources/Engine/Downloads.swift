import Foundation

/// A snapshot of one download. A new value arrives with every update.
nonisolated public struct DownloadItem: Sendable, Hashable, Identifiable {
    public typealias ID = String

    public enum State: Sendable, Hashable {
        case inProgress
        case complete
        case cancelled
        /// Network or disk failure; `canResume` says whether resuming may work.
        case interrupted
    }

    public var id: ID
    public var url: URL
    /// The server's or the page's filename, before the delegate picks a path.
    public var suggestedFilename: String
    /// Where the file is being written; `nil` until the delegate decides.
    public var destination: URL?
    public var mimeType: String?
    public var receivedBytes: Int64
    /// `nil` when the server sent no length.
    public var totalBytes: Int64?
    /// Bytes per second.
    public var currentSpeed: Int64
    public var state: State
    public var isPaused: Bool
    public var canResume: Bool
    public var startTime: Date

    public init(
        id: ID,
        url: URL,
        suggestedFilename: String,
        destination: URL? = nil,
        mimeType: String? = nil,
        receivedBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        currentSpeed: Int64 = 0,
        state: State = .inProgress,
        isPaused: Bool = false,
        canResume: Bool = false,
        startTime: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.suggestedFilename = suggestedFilename
        self.destination = destination
        self.mimeType = mimeType
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.currentSpeed = currentSpeed
        self.state = state
        self.isPaused = isPaused
        self.canResume = canResume
        self.startTime = startTime
    }

    /// 0...1, or `nil` when the total is unknown.
    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }
}

/// Receives a profile's downloads. Without a delegate, downloads are cancelled.
@MainActor
public protocol DownloadsDelegate: AnyObject {
    /// Pick the destination file. `completion(nil)` cancels the download.
    func profile(_ profile: any Profile, willBeginDownload item: DownloadItem, completion: @escaping (URL?) -> Void)
    /// Progress, pause/resume, completion, cancellation and interruption.
    func profile(_ profile: any Profile, didUpdateDownload item: DownloadItem)
}
