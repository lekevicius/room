import Foundation

/// On-disk locations owned by the app.
public enum AppPaths {
    /// `~/Library/Application Support/Room`
    public static var applicationSupport: URL {
        URL.applicationSupportDirectory.appending(path: "Room", directoryHint: .isDirectory)
    }

    /// The engine's data root (profiles, caches, `Local State`, `RoomCore.log`,
    /// Crashpad): `~/Library/Application Support/Room/RoomCore`. (Chapters 1–2's
    /// CEF engine used `Room/Engine`, which nothing reads any more.)
    public static var engineUserData: URL {
        applicationSupport.appending(path: "RoomCore", directoryHint: .isDirectory)
    }

    /// `~/Library/Logs/Room`
    public static var logs: URL {
        URL.libraryDirectory.appending(path: "Logs/Room", directoryHint: .isDirectory)
    }

    /// Creates `url` (and parents) if missing and returns it.
    @discardableResult
    public static func ensureDirectory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
