import CryptoKit
import Foundation
import Model

/// The favicon cache by host (spec §I.2: cached per origin), outside the
/// state pipeline: rows are written as pages report icons, and entries point
/// at them through `Entry.faviconID`, so an unloaded entry still shows its
/// icon after a relaunch. Rows are read once at open; images are PNG data
/// (the UI decodes and keeps its own images).
public final class FaviconStore {
    private let database: RoomDatabase?
    private var rows: [Int64: Row] = [:]
    private var byHost: [String: Int64] = [:]

    struct Row {
        var host: String
        var png: Data
        var sha256: String
    }

    /// `database == nil`: an in-memory cache only (tests, a store that could not open).
    public init(database: RoomDatabase?) {
        self.database = database
        guard let database else { return }
        do {
            for favicon in try database.favicons() {
                guard let id = favicon.id else { continue }
                rows[id] = Row(host: favicon.host, png: favicon.png, sha256: favicon.sha256)
                byHost[favicon.host] = id
            }
        } catch {
            NSLog("Room: favicons not loaded: \(error)")
        }
    }

    public func png(_ id: Int64) -> Data? { rows[id]?.png }

    public func id(forHost host: String) -> Int64? { byHost[host] }

    /// Stores `png` as `host`'s icon (replacing an older one) and returns its
    /// row id; an unchanged icon is not written again.
    @discardableResult
    public func save(png: Data, host: String) -> Int64? {
        let sha = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        if let id = byHost[host], rows[id]?.sha256 == sha { return id }
        let record = Favicon(id: byHost[host], host: host, png: png, sha256: sha, updatedAt: .now)
        let saved: Int64?
        if let database {
            do { saved = try database.saveFavicon(record) } catch {
                NSLog("Room: favicon for \(host) not saved: \(error)")
                return nil
            }
        } else {
            saved = record.id ?? (rows.keys.max() ?? 0) + 1
        }
        guard let id = saved else { return nil }
        rows[id] = Row(host: host, png: png, sha256: sha)
        byHost[host] = id
        return id
    }
}
