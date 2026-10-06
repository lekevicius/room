import Foundation
import Model
import Tabs

/// 4.4b's one-time move of the engine's profile directories (B-22): from
/// `Room Profile <name>` to `Room Profile <id>`, so a rename keeps the
/// profile's cookies. Runs from `main.swift` before the engine starts:
/// Chromium opens its last used profile during startup, before the app gets
/// control, so a directory moved later would be moved under an open profile.
/// The decision is `EngineProfileDirectories.moves` (Tabs, tested); the
/// marker is the directories themselves (a moved profile has its id
/// directory, so nothing moves twice). Chromium's Local State names the last
/// used profile and its profile list by directory: those names follow the
/// move, so the next startup opens the moved profile rather than making an
/// empty one at the old path.
enum EngineProfileMigration {
    /// This launch's moves and whether Local State followed (the `profiles` spike reports them).
    private(set) static var moved: [EngineProfileDirectories.Move] = []
    private(set) static var localStateUpdated = false

    static func run(engineRoot: URL, stateDirectory: URL, prefix: String) {
        let profiles: [Model.Profile]
        do {
            profiles = try RoomDatabase.storedProfiles(at: stateDirectory.appending(path: RoomStorage.databaseName))
        } catch {
            return NSLog("Room: engine profile directories not checked: the state database cannot be read (\(error))")
        }
        guard !profiles.isEmpty else { return }
        let fileManager = FileManager.default
        let existing = Set((try? fileManager.contentsOfDirectory(atPath: engineRoot.path)) ?? [])
        let moves = EngineProfileDirectories.moves(profiles: profiles, existing: existing, prefix: prefix)
        var done: [EngineProfileDirectories.Move] = []
        for move in moves {
            do {
                try fileManager.moveItem(at: engineRoot.appending(path: move.from, directoryHint: .isDirectory),
                                         to: engineRoot.appending(path: move.to, directoryHint: .isDirectory))
                done.append(move)
                NSLog("Room: engine profile directory moved: \"%@\" → \"%@\" (B-22)", move.from, move.to)
            } catch {
                NSLog("Room: engine profile directory \"%@\" not moved: %@", move.from, "\(error)")
            }
        }
        moved = done
        if !done.isEmpty { localStateUpdated = renameInLocalState(engineRoot.appending(path: "Local State"), done) }
    }

    /// `profile.last_used`, `profile.last_active_profiles` and the keys of
    /// `profile.info_cache` follow the moved directories.
    private static func renameInLocalState(_ url: URL, _ moves: [EngineProfileDirectories.Move]) -> Bool {
        guard let data = try? Data(contentsOf: url),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var profile = root["profile"] as? [String: Any] else { return false }
        let renamed = Dictionary(moves.map { ($0.from, $0.to) }, uniquingKeysWith: { first, _ in first })
        if let last = profile["last_used"] as? String, let to = renamed[last] { profile["last_used"] = to }
        if let active = profile["last_active_profiles"] as? [String] { profile["last_active_profiles"] = active.map { renamed[$0] ?? $0 } }
        if var cache = profile["info_cache"] as? [String: Any] {
            for (from, to) in renamed where cache[to] == nil {
                if let entry = cache.removeValue(forKey: from) { cache[to] = entry }
            }
            profile["info_cache"] = cache
        }
        root["profile"] = profile
        do {
            try JSONSerialization.data(withJSONObject: root).write(to: url, options: .atomic)
            NSLog("Room: Local State follows %ld moved profile directories", moves.count)
            return true
        } catch {
            NSLog("Room: Local State not updated after the move: \(error)")
            return false
        }
    }
}
