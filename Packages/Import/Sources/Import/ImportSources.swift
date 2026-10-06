import Foundation

/// The browsers the sheet offers (Phase 4.3a; ROADMAP Chapter 4 "before the
/// loop" 7: every browser equally).
public enum BrowserKind: String, Hashable, Sendable, CaseIterable {
    /// Chrome's layout: `<root>/Local State`, `<root>/<profile>/{Bookmarks, History, Preferences}`.
    case chrome, brave, edge, vivaldi
    /// `<root>/StorableSidebar.json` and Chrome's layout under `<root>/User Data`.
    case arc
    /// `<root>/Bookmarks.plist`, `<root>/History.db`.
    case safari
    /// `places.sqlite` is not read (4.3b's call): bookmarks through an exported HTML file.
    case firefox
    /// A Netscape bookmark file (any browser's HTML export).
    case bookmarksFile

    public var displayName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        case .vivaldi: "Vivaldi"
        case .arc: "Arc"
        case .safari: "Safari"
        case .firefox: "Firefox"
        case .bookmarksFile: "Bookmarks file"
        }
    }

    /// Where the browser keeps its data, relative to the home directory.
    var installPath: String {
        switch self {
        case .chrome: "Library/Application Support/Google/Chrome"
        case .brave: "Library/Application Support/BraveSoftware/Brave-Browser"
        case .edge: "Library/Application Support/Microsoft Edge"
        case .vivaldi: "Library/Application Support/Vivaldi"
        case .arc: "Library/Application Support/Arc"
        case .safari: "Library/Safari"
        case .firefox: "Library/Application Support/Firefox"
        case .bookmarksFile: ""
        }
    }

    var isChromeFamily: Bool { [.chrome, .brave, .edge, .vivaldi].contains(self) }
}

/// One place to import from: a detected install, a fixture directory or a
/// chosen file or folder. Nothing is read to make one beyond directory
/// listings and file existence.
public struct ImportSource: Hashable, Sendable, Identifiable {
    public var kind: BrowserKind
    public var name: String
    /// The install's directory (a Chrome-family root or profile directory,
    /// Arc's directory, Safari's), or the bookmark file.
    public var location: URL
    /// A line the sheet shows under the source (Firefox's "bookmarks via an exported HTML file").
    public var note: String?

    public var id: String { kind.rawValue + ":" + location.path }

    public init(kind: BrowserKind, name: String, location: URL, note: String? = nil) {
        self.kind = kind
        self.name = name
        self.location = location
        self.note = note
    }

    /// Firefox is listed but not read (4.3b decides on `places.sqlite`).
    public var isReadable: Bool { kind != .firefox }
}

/// A Chromium profile of a source (`Local State`'s name, its directory).
public struct ImportProfileChoice: Hashable, Sendable, Identifiable {
    public var directory: String
    public var name: String
    public var id: String { directory }

    public init(directory: String, name: String) {
        self.directory = directory
        self.name = name
    }
}

public enum ImportSources {
    public static let firefoxNote = "Bookmarks via an exported HTML file (Firefox ▸ Bookmarks ▸ Manage Bookmarks ▸ Export)."

    /// Installs found by their directories' existence under `home` (nothing is read).
    public static func detectInstalls(home: URL, fileManager: FileManager = .default) -> [ImportSource] {
        BrowserKind.allCases.compactMap { kind in
            guard kind != .bookmarksFile else { return nil }
            let directory = home.appending(path: kind.installPath, directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return ImportSource(kind: kind, name: kind.displayName, location: directory, note: kind == .firefox ? firefoxNote : nil)
        }
    }

    /// What a chosen file or folder is, by its name and the names of the
    /// files in it (nothing is read). `nil` when nothing Room reads is there.
    public static func identify(_ url: URL, name: String? = nil, fileManager: FileManager = .default) -> ImportSource? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
        let label = name ?? url.lastPathComponent
        if !isDirectory.boolValue {
            switch url.lastPathComponent {
            case "Bookmarks.plist", "History.db": return ImportSource(kind: .safari, name: name ?? "Safari", location: url.deletingLastPathComponent())
            case "StorableSidebar.json": return ImportSource(kind: .arc, name: name ?? "Arc", location: url.deletingLastPathComponent())
            case "Bookmarks", "History", "Preferences", "Secure Preferences":
                return ImportSource(kind: .chrome, name: name ?? url.deletingLastPathComponent().lastPathComponent,
                                    location: url.deletingLastPathComponent())
            default:
                let ext = url.pathExtension.lowercased()
                return ext == "html" || ext == "htm" ? ImportSource(kind: .bookmarksFile, name: label, location: url) : nil
            }
        }
        func has(_ path: String) -> Bool { fileManager.fileExists(atPath: url.appending(path: path).path) }
        if has("StorableSidebar.json") { return ImportSource(kind: .arc, name: label, location: url) }
        if has("Bookmarks.plist") || has("History.db") { return ImportSource(kind: .safari, name: label, location: url) }
        if has("Local State") || has("Default/Bookmarks") || has("Default/History") || has("Bookmarks") || has("History") {
            return ImportSource(kind: .chrome, name: label, location: url)
        }
        // In a folder, an HTML file counts only when its name says bookmarks (Firefox's
        // "bookmarks.html", Chrome's "bookmarks_10_6_26.html", Safari's "Safari Bookmarks.html").
        let html = ((try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
            .first { ["html", "htm"].contains(($0 as NSString).pathExtension.lowercased()) && $0.lowercased().contains("bookmark") }
        if let html { return ImportSource(kind: .bookmarksFile, name: label, location: url.appending(path: html)) }
        return nil
    }

    /// DEBUG `-RoomImportSource <directory>`: each subdirectory that holds a
    /// source is listed as a detected install named "<subdirectory> (fixture)".
    public static func sources(inDirectory directory: URL, fileManager: FileManager = .default) -> [ImportSource] {
        let children = ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        return children.compactMap { child in
            identify(directory.appending(path: child, directoryHint: .isDirectory), name: "\(child) (fixture)", fileManager: fileManager)
        }
    }

    /// The source's Chromium profiles, by `Local State`'s names, keeping
    /// those whose directory exists. Read when the source is picked, never
    /// before. A profile directory picked on its own, Safari, Arc (whose
    /// profiles come with its sidebar) and a bookmark file have none.
    public static func profiles(of source: ImportSource, fileManager: FileManager = .default) -> [ImportProfileChoice] {
        guard source.kind.isChromeFamily else { return [] }
        let localState = source.location.appending(path: "Local State")
        guard let data = fileManager.contents(atPath: localState.path),
              let listed = try? ChromeLocalStateReader.profiles(data) else {
            return []
        }
        return listed.filter { fileManager.fileExists(atPath: source.location.appending(path: $0.directory).path) }
            .map { ImportProfileChoice(directory: $0.directory, name: $0.name) }
    }
}
