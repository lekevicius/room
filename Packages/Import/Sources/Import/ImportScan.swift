import Foundation

/// What a source holds, read off the main thread when the sheet picks it
/// (Phase 4.3a): one result per kind of data the source has a file for
/// (`nil`: no such file), and how long each read took.
public struct ImportScan: Sendable {
    public var source: ImportSource
    public var profile: ImportProfileChoice?
    public var bookmarks: Result<ImportedBookmarks, ImportError>?
    public var history: Result<ImportedHistory, ImportError>?
    public var extensions: Result<ImportedExtensions, ImportError>?
    public var sidebar: Result<ImportedSidebar, ImportError>?
    /// Seconds per part ("bookmarks", "history", "extensions", "sidebar").
    public var seconds: [String: Double] = [:]

    public init(source: ImportSource, profile: ImportProfileChoice?) {
        self.source = source
        self.profile = profile
    }

    /// The readers' errors, for the sheet.
    public var errors: [ImportError] {
        [bookmarks.flatMap(\.failure), history.flatMap(\.failure), extensions.flatMap(\.failure), sidebar.flatMap(\.failure)].compactMap { $0 }
    }

    /// Nothing at all was read.
    public var isEmpty: Bool { bookmarks == nil && history == nil && sidebar == nil && extensions == nil }

    /// macOS kept Room out of the source's files (no Full Disk Access): a
    /// read refused with permission denied, or Safari's folder showing none
    /// of its files (TCC hides them from a process without access). The
    /// sheet then offers the open panel, whose grant opens the folder.
    public var needsFileAccess: Bool {
        errors.contains { $0.kind == .permissionDenied } || (source.kind == .safari && isEmpty)
    }
}

extension Result {
    public var value: Success? { if case .success(let value) = self { value } else { nil } }
    public var failure: Failure? { if case .failure(let error) = self { error } else { nil } }
}

/// Progress for the sheet: a fraction of the steps and the step's name.
public struct ImportProgress: Hashable, Sendable {
    public var fraction: Double
    public var step: String

    public init(fraction: Double, step: String) {
        self.fraction = fraction
        self.step = step
    }
}

public enum ImportScanner {
    /// The files a source's parts come from (`nil`: the source has none).
    public struct Files: Hashable, Sendable {
        public var bookmarks: URL?
        public var bookmarksFormat: ImportFormat = .chromeBookmarks
        public var history: URL?
        public var historyFormat: ImportFormat = .chromeHistory
        /// `Preferences` and `Secure Preferences`, both read.
        public var preferences: [URL] = []
        public var sidebar: URL?
        public var localState: URL?
    }

    public static func files(of source: ImportSource, profile: ImportProfileChoice?, fileManager: FileManager = .default) -> Files {
        func existing(_ url: URL) -> URL? { fileManager.fileExists(atPath: url.path) ? url : nil }
        var files = Files()
        switch source.kind {
        case .chrome, .brave, .edge, .vivaldi:
            let root = source.location
            let directory: URL = if let profile { root.appending(path: profile.directory, directoryHint: .isDirectory) }
                else if existing(root.appending(path: "Local State")) != nil { root.appending(path: "Default", directoryHint: .isDirectory) }
                else { root }
            files.bookmarks = existing(directory.appending(path: "Bookmarks"))
            files.history = existing(directory.appending(path: "History"))
            files.preferences = ["Preferences", "Secure Preferences"].compactMap { existing(directory.appending(path: $0)) }
        case .arc:
            let data = source.location.appending(path: "User Data", directoryHint: .isDirectory)
            let directory = data.appending(path: profile?.directory ?? "Default", directoryHint: .isDirectory)
            files.sidebar = existing(source.location.appending(path: "StorableSidebar.json"))
            files.localState = existing(data.appending(path: "Local State"))
            files.history = existing(directory.appending(path: "History"))
            files.preferences = ["Preferences", "Secure Preferences"].compactMap { existing(directory.appending(path: $0)) }
        case .safari:
            files.bookmarks = existing(source.location.appending(path: "Bookmarks.plist"))
            files.bookmarksFormat = .safariBookmarks
            files.history = existing(source.location.appending(path: "History.db"))
            files.historyFormat = .safariHistory
        case .bookmarksFile:
            files.bookmarks = existing(source.location)
            files.bookmarksFormat = .netscapeBookmarks
        case .firefox:
            // The install's `Profiles/<dir>` (the picked profile, else the first), or a profile folder chosen on its own.
            let directory: URL? = if let profile { source.location.appending(path: profile.directory, directoryHint: .isDirectory) }
                else if existing(source.location.appending(path: "places.sqlite")) != nil { source.location }
                else { ImportSources.firefoxProfiles(in: source.location, fileManager: fileManager).first
                    .map { source.location.appending(path: $0.directory, directoryHint: .isDirectory) } }
            if let places = directory.flatMap({ existing($0.appending(path: "places.sqlite")) }) {
                files.bookmarks = places
                files.bookmarksFormat = .firefoxPlaces
                files.history = places
                files.historyFormat = .firefoxPlaces
            }
        }
        return files
    }

    /// Reads every part the source has. Synchronous: call it off the main thread.
    public static func scan(_ source: ImportSource, profile: ImportProfileChoice?, fileManager: FileManager = .default,
                            progress: (@Sendable (ImportProgress) -> Void)? = nil) -> ImportScan {
        let files = files(of: source, profile: profile, fileManager: fileManager)
        var scan = ImportScan(source: source, profile: profile)
        let steps = Double([files.bookmarks, files.history, files.sidebar].compactMap { $0 }.count + (files.preferences.isEmpty ? 0 : 1))
        var done = 0.0
        func step<T>(_ name: String, _ body: () throws(ImportError) -> T) -> Result<T, ImportError> {
            progress?(ImportProgress(fraction: steps == 0 ? 0 : done / steps, step: "Reading \(name)…"))
            let start = ContinuousClock.now
            let result: Result<T, ImportError>
            do throws(ImportError) { result = .success(try body()) } catch { result = .failure(error) }
            let elapsed = ContinuousClock.now - start
            scan.seconds[name] = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            done += 1
            return result
        }
        func data(_ url: URL, _ format: ImportFormat) throws(ImportError) -> Data {
            guard let data = fileManager.contents(atPath: url.path) else {
                throw fileManager.fileExists(atPath: url.path) ? ImportError(.permissionDenied, format, url.lastPathComponent)
                    : ImportError(.unreadable, format, "no file at \(url.path)")
            }
            return data
        }
        if let url = files.bookmarks {
            let format = files.bookmarksFormat
            scan.bookmarks = step("bookmarks") { () throws(ImportError) -> ImportedBookmarks in
                if format == .firefoxPlaces { return try FirefoxPlacesReader.bookmarks(at: url) }
                let bytes = try data(url, format)
                switch format {
                case .safariBookmarks: return try SafariBookmarksReader.read(bytes)
                case .netscapeBookmarks: return try NetscapeBookmarksReader.read(bytes)
                default: return try ChromeBookmarksReader.read(bytes)
                }
            }
        }
        if let url = files.sidebar {
            let names = files.localState.flatMap { fileManager.contents(atPath: $0.path) }.flatMap { try? ChromeLocalStateReader.profiles($0) }
            let profileNames = Dictionary((names ?? []).map { ($0.directory, $0.name) }, uniquingKeysWith: { first, _ in first })
            scan.sidebar = step("sidebar") { () throws(ImportError) -> ImportedSidebar in
                try ArcSidebarReader.read(try data(url, .arcSidebar), profileNames: profileNames)
            }
        }
        if let url = files.history {
            let format = files.historyFormat
            scan.history = step("history") { () throws(ImportError) -> ImportedHistory in
                switch format {
                case .safariHistory: try SafariHistoryReader.read(at: url)
                case .firefoxPlaces: try FirefoxPlacesReader.history(at: url)
                default: try ChromeHistoryReader.read(at: url)
                }
            }
        }
        if !files.preferences.isEmpty {
            scan.extensions = step("extensions") { () throws(ImportError) -> ImportedExtensions in
                var merged = ImportedExtensions()
                for url in files.preferences {
                    let read = try ChromeExtensionsReader.read(try data(url, .chromePreferences))
                    for item in read.extensions where !merged.extensions.contains(where: { $0.id == item.id }) { merged.extensions.append(item) }
                    for item in read.skipped where !merged.skipped.contains(item) { merged.skipped.append(item) }
                }
                return merged
            }
        }
        progress?(ImportProgress(fraction: 1, step: "Read"))
        return scan
    }
}
