import AppKit
import Engine
import Observation

/// Where a download is saved and how it reads in the list (spec §F, ROADMAP
/// 2.6 task 1), as pure functions.
public enum DownloadRules {
    /// The fallback when the server and the page name nothing usable.
    public static let fallbackName = "download"

    /// Extensions kept whole when a name is made unique ("logs (1).tar.gz").
    static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst", "user.js"]

    /// A name the file system takes: no path separators, colons or control
    /// characters, no leading dots (hidden files), trimmed; empty → "download".
    public static func sanitizedFilename(_ suggested: String) -> String {
        let replaced = suggested.unicodeScalars.map { scalar -> String in
            if scalar == "/" || scalar == ":" || scalar == "\\" { return "-" }
            if CharacterSet.controlCharacters.contains(scalar) { return "" }
            return String(scalar)
        }.joined()
        var name = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // macOS file names are at most 255 bytes of UTF-8.
        while name.utf8.count > 255 {
            let (base, ext) = split(name)
            name = String(base.dropLast()) + (ext.isEmpty ? "" : "." + ext)
        }
        return name.isEmpty ? fallbackName : name
    }

    /// Base name and extension ("report", "pdf"; "logs", "tar.gz"; "README", "").
    static func split(_ name: String) -> (base: String, ext: String) {
        let lower = name.lowercased()
        if let compound = compoundExtensions.first(where: { lower.hasSuffix("." + $0) && lower.count > $0.count + 1 }) {
            let cut = name.index(name.endIndex, offsetBy: -(compound.count + 1))
            return (String(name[..<cut]), String(name[name.index(after: cut)...]))
        }
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty else { return (name, "") }
        return ((name as NSString).deletingPathExtension, ext)
    }

    /// `folder/name`, or "name (1).ext", "name (2).ext" … while a file or a
    /// download in progress already has the name (Chrome's numbering).
    public static func destination(for suggested: String, in folder: URL, isTaken: (URL) -> Bool) -> URL {
        let name = sanitizedFilename(suggested)
        let candidate = folder.appending(path: name, directoryHint: .notDirectory)
        guard isTaken(candidate) else { return candidate }
        let (base, ext) = split(name)
        var counter = 1
        while true {
            let numbered = "\(base) (\(counter))" + (ext.isEmpty ? "" : ".\(ext)")
            let url = folder.appending(path: numbered, directoryHint: .notDirectory)
            if !isTaken(url) { return url }
            counter += 1
        }
    }

    /// The folder Settings names, or the user's Downloads folder.
    public static func folder(setting: String?, downloads: URL) -> URL {
        guard let setting, !setting.isEmpty else { return downloads }
        return URL(fileURLWithPath: (setting as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// The footer ring: received over total across downloads in progress;
    /// `nil` when none is in progress, `-1` when a total is unknown (the ring spins).
    public static func progress(of items: [DownloadItem]) -> Double? {
        let active = items.filter { $0.state == .inProgress }
        guard !active.isEmpty else { return nil }
        var received: Int64 = 0, total: Int64 = 0
        for item in active {
            guard let size = item.totalBytes, size > 0 else { return -1 }
            received += item.receivedBytes
            total += size
        }
        return min(1, Double(received) / Double(total))
    }

    /// The row's second line: "1.2 of 5 MB — 2 MB/s", "5 MB", "Cancelled", "Failed".
    public static func detail(for item: DownloadItem) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        switch item.state {
        case .complete:
            return formatter.string(fromByteCount: item.totalBytes ?? item.receivedBytes)
        case .cancelled:
            return "Cancelled"
        case .interrupted:
            return item.canResume ? "Failed — can resume" : "Failed"
        case .inProgress:
            if item.isPaused { return "Paused — " + formatter.string(fromByteCount: item.receivedBytes) }
            let received = formatter.string(fromByteCount: item.receivedBytes)
            var text = item.totalBytes.map { "\(received) of \(formatter.string(fromByteCount: $0))" } ?? received
            if item.currentSpeed > 0 {
                text += " — \(formatter.string(fromByteCount: item.currentSpeed))/s"
                if let total = item.totalBytes, total > item.receivedBytes {
                    let seconds = Int(ceil(Double(total - item.receivedBytes) / Double(item.currentSpeed)))
                    text += ", " + remaining(seconds)
                }
            }
            return text
        }
    }

    static func remaining(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s left" }
        if seconds < 3600 { return "\(seconds / 60) min left" }
        return "\(seconds / 3600) h left"
    }

    public static func isFinished(_ state: DownloadItem.State) -> Bool {
        state != .inProgress
    }
}

/// Every download of the window's profiles, newest first (one list across
/// profiles, spec §F; each row knows its profile). It is every engine
/// profile's `downloadsDelegate`: it picks the file (`DownloadRules`, the
/// folder from Settings) and keeps the rows the footer button and the
/// popover show.
@Observable
public final class DownloadList: DownloadsDelegate {
    public struct Row: Identifiable, Equatable {
        public var item: DownloadItem
        public let profileName: String
        /// Where Room asked the engine to write the file.
        public let destination: URL?
        public var id: DownloadItem.ID { item.id }

        public static func == (lhs: Row, rhs: Row) -> Bool {
            lhs.item == rhs.item && lhs.profileName == rhs.profileName && lhs.destination == rhs.destination
        }
    }

    public private(set) var rows: [Row] = []
    /// Finished since the popover was last opened (the footer's badge).
    public private(set) var unseenCompleted = 0
    /// The folder downloads go to (Settings; the user's Downloads folder by default).
    @ObservationIgnored public var folder: () -> URL = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
    /// Whether a file exists (tests replace it).
    @ObservationIgnored public var fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    /// Settings ▸ Downloads ▸ "Ask where to save each download" (4.4a).
    @ObservationIgnored public var askWhereToSave: () -> Bool = { false }
    /// The save panel: offered the folder's name for the file, answers the
    /// chosen file or `nil` (the download is cancelled). Without it nothing is asked.
    @ObservationIgnored public var chooseDestination: ((_ proposed: URL, _ answer: @escaping (URL?) -> Void) -> Void)?
    /// Downloads the save panel cancelled: the engine's later updates for them are not listed.
    @ObservationIgnored private var declined: Set<DownloadItem.ID> = []
    /// A download started (the fly-in animation).
    @ObservationIgnored public var onBegin: ((Row) -> Void)?
    /// A download finished writing its file (bounce, badge, toast).
    @ObservationIgnored public var onComplete: ((Row) -> Void)?

    @ObservationIgnored private var profiles: [DownloadItem.ID: WeakProfile] = [:]

    public init() {}

    /// The ring's value (`DownloadRules.progress`).
    public var progress: Double? { DownloadRules.progress(of: rows.map(\.item)) }

    public func row(_ id: DownloadItem.ID) -> Row? { rows.first { $0.id == id } }

    // MARK: DownloadsDelegate

    public func profile(_ profile: any Profile, willBeginDownload item: DownloadItem, completion: @escaping (URL?) -> Void) {
        let folder = folder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Names of downloads still being written count as taken: two at once never share a file.
        let reserved = Set(rows.filter { $0.item.state == .inProgress }.compactMap { $0.destination?.standardizedFileURL })
        let destination = DownloadRules.destination(for: item.suggestedFilename, in: folder) { url in
            reserved.contains(url.standardizedFileURL) || fileExists(url)
        }
        if askWhereToSave(), let chooseDestination {
            chooseDestination(destination) { [weak self, weak profile] chosen in
                guard let self, let profile, let chosen else {
                    self?.declined.insert(item.id)
                    completion(nil)
                    return
                }
                begin(item, at: chosen, profile: profile, completion: completion)
            }
            return
        }
        begin(item, at: destination, profile: profile, completion: completion)
    }

    private func begin(_ item: DownloadItem, at destination: URL, profile: any Profile, completion: @escaping (URL?) -> Void) {
        var started = item
        started.destination = destination
        let row = Row(item: started, profileName: profile.name, destination: destination)
        rows.removeAll { $0.id == item.id }
        rows.insert(row, at: 0)
        profiles[item.id] = WeakProfile(profile)
        completion(destination)
        onBegin?(row)
    }

    public func profile(_ profile: any Profile, didUpdateDownload item: DownloadItem) {
        if declined.contains(item.id) { return }
        guard let index = rows.firstIndex(where: { $0.id == item.id }) else {
            // An update for a download this list did not start (the engine's own); listed as it is.
            rows.insert(Row(item: item, profileName: profile.name, destination: item.destination), at: 0)
            profiles[item.id] = WeakProfile(profile)
            return
        }
        let before = rows[index].item.state
        var updated = item
        if updated.destination == nil { updated.destination = rows[index].destination }
        rows[index].item = updated
        if before != .complete, updated.state == .complete {
            unseenCompleted += 1
            onComplete?(rows[index])
        }
    }

    // MARK: Actions

    public func cancel(_ id: DownloadItem.ID) { profiles[id]?.profile?.cancelDownload(id: id) }
    public func pause(_ id: DownloadItem.ID) { profiles[id]?.profile?.pauseDownload(id: id) }
    public func resume(_ id: DownloadItem.ID) { profiles[id]?.profile?.resumeDownload(id: id) }

    /// Shows the file (or its folder while it is not there) in the Finder.
    public func reveal(_ id: DownloadItem.ID) {
        guard let url = row(id)?.item.destination ?? row(id)?.destination else { return }
        if fileExists(url) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    /// Opens a finished file with its app.
    public func open(_ id: DownloadItem.ID) {
        guard let row = row(id), row.item.state == .complete, let url = row.item.destination ?? row.destination else { return }
        NSWorkspace.shared.open(url)
    }

    /// "Clear": the finished rows go, from the engine's list and its
    /// download history too (`Profile.removeDownload`, B-59), so a relaunch
    /// does not list them again; downloads in progress stay.
    public func clear() {
        let finished = rows.filter { DownloadRules.isFinished($0.item.state) }.map(\.id)
        for id in finished { forget(id) }
    }

    /// The Library's Remove: one row leaves the list and the engine's history
    /// (a download in progress is cancelled first, as Chrome's Clear does).
    public func remove(_ id: DownloadItem.ID) {
        if row(id)?.item.state == .inProgress { cancel(id) }
        forget(id)
    }

    private func forget(_ id: DownloadItem.ID) {
        profiles[id]?.profile?.removeDownload(id: id)
        rows.removeAll { $0.id == id }
        profiles.removeValue(forKey: id)
    }

    public var canClear: Bool { rows.contains { DownloadRules.isFinished($0.item.state) } }

    /// The popover opened: the badge goes.
    public func markSeen() { unseenCompleted = 0 }
}

private struct WeakProfile {
    weak var profile: (any Profile)?
    init(_ profile: any Profile) { self.profile = profile }
}
