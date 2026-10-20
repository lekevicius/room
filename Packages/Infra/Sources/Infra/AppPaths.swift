import Foundation

/// On-disk locations owned by the app.
public enum AppPaths {
    /// The shipping identity (PLAN §4 Identity): Release builds and the DMG.
    public static let releaseBundleIdentifier = "app.room.desktop"
    /// The Debug app's identity (5.0a): Room.app over either engine and the embryo host.
    public static let devBundleIdentifier = "app.room.desktop.dev"

    /// The folder under Application Support (and Logs) an identity owns: "Room"
    /// for the shipping app, "Room Dev" for the Debug app, so a Debug launch
    /// without `-RoomStateDirectory` never opens the user's state or engine root
    /// (whose Chromium singleton would hand the launch to the user's Room).
    public static func folderName(bundleIdentifier: String?) -> String {
        bundleIdentifier == devBundleIdentifier ? "Room Dev" : "Room"
    }

    private static var folderName: String { folderName(bundleIdentifier: Bundle.main.bundleIdentifier) }

    /// `~/Library/Application Support/Room` (`Room Dev` for the Debug app)
    public static var applicationSupport: URL {
        URL.applicationSupportDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }

    /// The engine's data root (profiles, caches, `Local State`, `RoomCore.log`,
    /// Crashpad): `~/Library/Application Support/Room/RoomCore`. (Chapters 1–2's
    /// CEF engine used `Room/Engine`, which nothing reads any more.)
    public static var engineUserData: URL {
        applicationSupport.appending(path: "RoomCore", directoryHint: .isDirectory)
    }

    /// `~/Library/Logs/Room` (`Room Dev` for the Debug app)
    public static var logs: URL {
        URL.libraryDirectory.appending(path: "Logs/\(folderName)", directoryHint: .isDirectory)
    }

    /// Creates `url` (and parents) if missing and returns it.
    @discardableResult
    public static func ensureDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
