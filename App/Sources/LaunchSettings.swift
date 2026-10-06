import Engine
import Foundation
import Model

/// Settings the engine reads once at launch (4.7a), read from the state
/// database before the store and the engine open (`main.swift`). Chromium
/// fixes its feature list at startup, so a change applies at the next launch
/// (Settings says so).
enum LaunchSettings {
    /// `//room`'s feature behind Settings ▸ Downloads ▸ PDFs ▸ Download: the
    /// profiles' `plugins.always_open_pdf_externally` default (a PDF
    /// navigation becomes a download instead of Chrome's viewer).
    static let pdfsDownloadFeature = "RoomPdfsDownload"

    static func engineFeatures(stateDirectory: URL) -> EngineFeatures {
        let settings: Settings
        do {
            settings = try RoomDatabase.storedSettings(at: stateDirectory.appending(path: RoomStorage.databaseName))
        } catch {
            NSLog("Room: launch settings not read (\(error)); the engine starts with its defaults")
            return EngineFeatures()
        }
        return engineFeatures(for: settings)
    }

    static func engineFeatures(for settings: Settings) -> EngineFeatures {
        var features = EngineFeatures()
        if !settings.pdfsOpenInRoom {
            features.enabled.insert(pdfsDownloadFeature)
            NSLog("Room: PDFs download (Settings ▸ Downloads): --enable-features=%@", pdfsDownloadFeature)
        }
        return features
    }
}
