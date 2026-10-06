import Foundation
import GRDB
import Testing
@testable import Model

@Suite("Schema and migrations")
struct SchemaTests {
    @Test("v1 to v9 apply in order; v6 leaves no Chapter 2 history table behind")
    func v1Tables() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let tables = ["profile", "space", "entry", "split_group", "window", "window_space", "favicon", "kv", "archive", "routing_rule"]
        let missing = try queue.read { db in try tables.filter { try !db.tableExists($0) } }
        #expect(missing.isEmpty)
        let history = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE name LIKE '%history%'")
        }
        #expect(history.isEmpty)
        let applied = try queue.read { db in try Schema.migrator.appliedMigrations(db) }
        #expect(applied == [Schema.v1, Schema.v2, Schema.v3, Schema.v4, Schema.v5, Schema.v6, Schema.v7, Schema.v8, Schema.v9])
        let completed = try queue.read { db in try Schema.migrator.hasCompletedMigrations(db) }
        #expect(completed)
    }

    @Test("v6 archives what the engine's history does not hold beside the database, then drops the tables (B-66)")
    func v6ArchivesThenDrops() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let queue = try DatabaseQueue(path: directory.url.appending(path: "Room.sqlite").path)
        var migrator = Schema.migrator
        try migrator.migrate(queue, upTo: Schema.v5)
        let imported = UUID(), neverImported = UUID()
        let now = Date()
        let old = now.addingTimeInterval(-200 * 86_400), recent = now.addingTimeInterval(-86_400)
        func add(_ db: Database, _ profile: UUID, _ url: String, _ visits: [(Date, String)]) throws {
            try db.execute(sql: """
                INSERT INTO history_url (profileID, url, title, visitCount, typedCount, lastVisitAt, host) VALUES (?, ?, ?, ?, ?, ?, '')
                """, arguments: [profile, url, "T " + url, visits.count, visits.filter { $0.1 == "typed" }.count,
                                  Timestamp(visits.map(\.0).max() ?? now)])
            let id = db.lastInsertedRowID
            for (time, transition) in visits {
                try db.execute(sql: "INSERT INTO history_visit (urlID, visitedAt, transition) VALUES (?, ?, ?)",
                               arguments: [id, Timestamp(time), transition])
            }
        }
        try queue.write { db in
            var settings = Settings()
            settings.historyImportedProfiles = [imported]
            let json = String(data: try JSONEncoder().encode(settings), encoding: .utf8)!
            try db.execute(sql: "INSERT INTO kv (key, value) VALUES (?, ?)", arguments: [KVKey.settings, json])
            try add(db, imported, "https://old.example/", [(old, "typed"), (recent, "link")])
            try add(db, imported, "https://recent.example/", [(recent, "link")])
            try add(db, neverImported, "https://other.example/", [(recent, "link"), (old, "typed")])
        }
        migrator = Schema.migrator
        try migrator.migrate(queue)

        let history = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE name LIKE '%history%'")
        }
        #expect(history.isEmpty)
        let archive = try #require(HistoryArchive.read(from: directory.url.appending(path: HistoryArchive.fileName)))
        #expect(archive.engineRetentionDays == 89)
        let first = try #require(archive.profiles.first { $0.profileID == imported })
        #expect(first.imported && first.tableURLs == 2)
        // Only the visit older than 89 days: the import kept the rest in the engine.
        #expect(first.urls.map(\.url) == ["https://old.example/"])
        #expect(first.urls.first?.visits.count == 1 && first.urls.first?.visits.first?.transition == "typed")
        #expect(first.urls.first?.visitCount == 2 && first.urls.first?.typedCount == 1)
        let second = try #require(archive.profiles.first { $0.profileID == neverImported })
        // A profile never imported keeps every visit (the next launch imports them).
        #expect(!second.imported && second.cutoff == nil && second.tableURLs == 1)
        #expect(second.urls.map(\.url) == ["https://other.example/"] && second.urls.first?.visits.count == 2)
    }

    @Test("Opening a database that is mostly free pages (v6 on a large history) gives them back")
    func vacuumAfterDrop() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.url.appending(path: "Room.sqlite")
        do {
            let queue = try DatabaseQueue(path: url.path)
            try queue.write { db in
                try db.execute(sql: "CREATE TABLE filler (blob BLOB)")
                for _ in 0..<600 { try db.execute(sql: "INSERT INTO filler VALUES (zeroblob(4000))") }
            }
            try queue.write { db in try db.execute(sql: "DROP TABLE filler") }
        }
        let database = try RoomDatabase(url: url)
        let free = try database.pool.read { db in try Int.fetchOne(db, sql: "PRAGMA freelist_count") }
        #expect(free == 0)
    }

    @Test("v6 writes no archive when the history tables are empty")
    func v6EmptyHistory() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let queue = try DatabaseQueue(path: directory.url.appending(path: "Room.sqlite").path)
        try Schema.migrator.migrate(queue)
        #expect(!FileManager.default.fileExists(atPath: directory.url.appending(path: HistoryArchive.fileName).path))
    }

    @Test("v4 gives existing splits their pane order: section, then position")
    func v4Backfill() throws {
        let queue = try DatabaseQueue()
        var migrator = Schema.migrator
        try migrator.migrate(queue, upTo: Schema.v3)
        let profile = Profile(name: "P", position: 0)
        let space = Space(name: "S", profileID: profile.id, position: 0)
        let group = UUID()
        let today0 = Entry(kind: .today, spaceID: space.id, profileID: profile.id, splitGroupID: group, position: 0)
        let pinned = Entry(kind: .pinned, spaceID: space.id, profileID: profile.id, splitGroupID: group, position: 3)
        let today1 = Entry(kind: .today, spaceID: space.id, profileID: profile.id, splitGroupID: group, position: 1)
        try queue.write { db in
            try profile.insert(db)
            try space.insert(db)
            try db.execute(sql: "INSERT INTO split_group (id, layout, ratios) VALUES (?, 'hbox', '[0.3,0.3,0.4]')", arguments: [group])
            // The v3 column set (Entry gained navigationState in v5).
            for entry in [today1, pinned, today0] {
                try db.execute(sql: """
                    INSERT INTO entry (id, kind, spaceID, profileID, splitGroupID, position, isCollapsed, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, 0, 1)
                    """, arguments: [entry.id, entry.kind, entry.spaceID, entry.profileID, entry.splitGroupID, entry.position])
            }
        }
        migrator = Schema.migrator
        try migrator.migrate(queue)
        let loaded = try queue.read { db in try SplitGroup.fetchOne(db, key: group) }
        #expect(loaded?.members == [pinned.id, today0.id, today1.id])
        #expect(loaded?.ratios == [0.3, 0.3, 0.4])
    }

    @Test("v5 keeps every entry and gives each an empty navigation state; a state written after it round-trips")
    func v5NavigationState() throws {
        let queue = try DatabaseQueue()
        var migrator = Schema.migrator
        try migrator.migrate(queue, upTo: Schema.v4)
        let profile = Profile(name: "P", position: 0)
        let space = Space(name: "S", profileID: profile.id, position: 0)
        let entry = Entry(kind: .today, spaceID: space.id, profileID: profile.id, liveURL: "https://a.example/2", liveTitle: "Two")
        try queue.write { db in
            try profile.insert(db)
            try space.insert(db)
            // The v4 column set (no navigationState yet).
            try db.execute(sql: """
                INSERT INTO entry (id, kind, spaceID, profileID, position, isCollapsed, createdAt, liveURL, liveTitle)
                VALUES (?, 'today', ?, ?, 0, 0, 1, ?, ?)
                """, arguments: [entry.id, space.id, profile.id, entry.liveURL, entry.liveTitle])
        }
        migrator = Schema.migrator
        try migrator.migrate(queue)
        let migrated = try queue.read { db in try Entry.fetchOne(db, key: entry.id) }
        #expect(migrated?.liveURL == "https://a.example/2" && migrated?.navigationState == nil)
        var updated = try #require(migrated)
        updated.navigationState = Data([0, 1, 2, 255])
        try queue.write { db in try updated.update(db) }
        #expect(try queue.read { db in try Entry.fetchOne(db, key: entry.id) }?.navigationState == Data([0, 1, 2, 255]))
    }

    @Test("v7 adds an empty archive and keeps every entry; an archived row written after it round-trips with its navigation state")
    func v7Archive() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let queue = try DatabaseQueue(path: directory.url.appending(path: "Room.sqlite").path)
        var migrator = Schema.migrator
        try migrator.migrate(queue, upTo: Schema.v6)
        let profile = Profile(name: "P", position: 0)
        let space = Space(name: "S", profileID: profile.id, position: 0)
        let entry = Entry(kind: .today, spaceID: space.id, profileID: profile.id, liveURL: "https://a.example/", liveTitle: "A",
                          navigationState: Data([1, 2, 3]))
        try queue.write { db in
            try profile.insert(db)
            try space.insert(db)
            try insertBeforeV9(entry, db)
        }
        #expect(try queue.read { db in try db.tableExists("archive") } == false)
        migrator = Schema.migrator
        try migrator.migrate(queue)
        #expect(try queue.read { db in try Entry.fetchOne(db, key: entry.id) } == entry)
        #expect(try queue.read { db in try ArchivedEntry.fetchCount(db) } == 0)
        let columns = try queue.read { db in try db.columns(in: "archive").map(\.name) }
        #expect(Set(columns) == ["id", "url", "title", "faviconID", "spaceID", "profileID", "archivedAt", "reason", "navigationState"])
        // A row for a space that no longer exists is allowed (no foreign key: B-15).
        let row = try #require(ArchivedEntry(entry, reason: .spaceDeleted, at: Timestamp(milliseconds: 9_000)))
        var gone = row
        gone.id = UUID()
        gone.spaceID = UUID()
        try queue.write { db in
            try row.insert(db)
            try gone.insert(db)
        }
        let read = try queue.read { db in try ArchivedEntry.fetchOne(db, key: entry.id) }
        #expect(read == row && read?.navigationState == Data([1, 2, 3]) && read?.reason == .spaceDeleted)
        #expect(read?.url == "https://a.example/" && read?.title == "A")
        // The reason is one of the five.
        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try db.execute(sql: "UPDATE archive SET reason = 'lost' WHERE id = ?", arguments: [entry.id])
            }
        }
    }

    @Test("v8 adds an empty routing_rule table and keeps everything; a rule written after it round-trips; its space must exist")
    func v8RoutingRules() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let queue = try DatabaseQueue(path: directory.url.appending(path: "Room.sqlite").path)
        var migrator = Schema.migrator
        try migrator.migrate(queue, upTo: Schema.v7)
        let profile = Profile(name: "P", position: 0)
        let space = Space(name: "S", profileID: profile.id, position: 0)
        let entry = Entry(kind: .today, spaceID: space.id, profileID: profile.id, liveURL: "https://a.example/")
        let row = try #require(ArchivedEntry(entry, reason: .manual, at: Timestamp(milliseconds: 5)))
        try queue.write { db in
            try profile.insert(db)
            try space.insert(db)
            try insertBeforeV9(entry, db)
            try row.insert(db)
        }
        #expect(try queue.read { db in try db.tableExists("routing_rule") } == false)
        migrator = Schema.migrator
        try migrator.migrate(queue)
        #expect(try queue.read { db in try Entry.fetchOne(db, key: entry.id) } == entry)
        #expect(try queue.read { db in try ArchivedEntry.fetchOne(db, key: row.id) } == row)
        #expect(try queue.read { db in try RoutingRule.fetchCount(db) } == 0)
        let columns = try queue.read { db in try db.columns(in: "routing_rule").map(\.name) }
        #expect(Set(columns) == ["id", "match", "pattern", "targetSpaceID", "position", "enabled"])
        let rule = RoutingRule(match: .equals, pattern: "example.com", targetSpaceID: space.id, position: 0, enabled: false)
        try queue.write { db in try rule.insert(db) }
        #expect(try queue.read { db in try RoutingRule.fetchOne(db, key: rule.id) } == rule)
        // The match kind is one of the three.
        #expect(throws: DatabaseError.self) {
            try queue.write { db in try db.execute(sql: "UPDATE routing_rule SET match = 'prefix' WHERE id = ?", arguments: [rule.id]) }
        }
        // A rule for a space that does not exist fails at commit (deferred foreign key).
        #expect(throws: DatabaseError.self) {
            try queue.write { db in try RoutingRule(match: .contains, pattern: "x", targetSpaceID: UUID()).insert(db) }
        }
    }

    @Test("v9 gives the Today rows of a v8 state to the first window by position; permanent entries stay shared (NULL)")
    func v9EntryWindow() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let queue = try DatabaseQueue(path: directory.url.appending(path: "Room.sqlite").path)
        var migrator = Schema.migrator
        try migrator.migrate(queue, upTo: Schema.v8)
        let profile = Profile(name: "P", position: 0)
        let space = Space(name: "S", profileID: profile.id, position: 0)
        // Two windows: the first by position is not the first inserted.
        let second = WindowState(sidebarWidth: 240, activeSpaceID: space.id, position: 1)
        let first = WindowState(sidebarWidth: 240, activeSpaceID: space.id, position: 0)
        let today1 = Entry(kind: .today, spaceID: space.id, profileID: profile.id, position: 0, liveURL: "https://a.example/")
        let today2 = Entry(kind: .today, spaceID: space.id, profileID: profile.id, position: 1, liveURL: "https://b.example/")
        let pinned = Entry(kind: .pinned, spaceID: space.id, profileID: profile.id, storedURL: "https://p.example/")
        let essential = Entry(kind: .essential, spaceID: nil, profileID: profile.id, storedURL: "https://e.example/")
        let folder = Entry(kind: .folder, spaceID: space.id, profileID: profile.id, position: 1, customLabel: "F")
        try queue.write { db in
            try profile.insert(db)
            try space.insert(db)
            try second.insert(db)
            try first.insert(db)
            for entry in [today1, today2, pinned, essential, folder] { try insertBeforeV9(entry, db) }
        }
        migrator = Schema.migrator
        try migrator.migrate(queue)
        let read = try queue.read { db in try Entry.fetchAll(db) }
        let byID = Dictionary(uniqueKeysWithValues: read.map { ($0.id, $0) })
        #expect(byID[today1.id]?.windowID == first.id && byID[today2.id]?.windowID == first.id)
        #expect(byID[pinned.id]?.windowID == nil && byID[essential.id]?.windowID == nil && byID[folder.id]?.windowID == nil)
        // Everything else is as it was.
        var expected = today1
        expected.windowID = first.id
        #expect(byID[today1.id] == expected && byID[pinned.id] == pinned)
        // A state with no window row keeps its Today rows window-less (the first window adopts them).
        let bare = try DatabaseQueue()
        migrator = Schema.migrator
        try migrator.migrate(bare, upTo: Schema.v8)
        try bare.write { db in
            try profile.insert(db)
            try space.insert(db)
            try insertBeforeV9(today1, db)
        }
        try migrator.migrate(bare)
        #expect(try bare.read { db in try Entry.fetchOne(db, key: today1.id) }?.windowID == nil)
    }

    @Test("A JSON snapshot from before v9 decodes with window-less entries")
    func entryDecodesWithoutWindow() throws {
        let state = sampleState()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json["entries"] = (json["entries"] as! [[String: Any]]).map { entry in entry.filter { $0.key != "windowID" } }
        let decoded = try JSONDecoder().decode(RoomState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.entries.allSatisfy { $0.windowID == nil })
        #expect(state.entries.contains { $0.kind == .today && $0.windowID != nil })
    }

    @Test("A JSON snapshot from before v8 decodes with no rules; snapshots keep the rules and the routing settings")
    func snapshotRoutingRules() throws {
        let state = sampleState()
        #expect(!state.routingRules.isEmpty)
        let encoded = try StateSnapshot(generation: 2, state: state).encoded()
        let decoded = try JSONDecoder().decode(StateSnapshot.self, from: encoded)
        #expect(decoded.state.canonical().routingRules == state.canonical().routingRules)
        #expect(decoded.state.settings.routeLinksBetweenSpaces && decoded.state.settings.externalLinksSpaceID == state.settings.externalLinksSpaceID)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var inner = try #require(object["state"] as? [String: Any])
        inner["routingRules"] = nil
        var settings = try #require(inner["settings"] as? [String: Any])
        settings["routeLinksBetweenSpaces"] = nil
        settings["externalLinksSpaceID"] = nil
        inner["settings"] = settings
        object["state"] = inner
        let old = try JSONDecoder().decode(StateSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.state.routingRules.isEmpty)
        #expect(!old.state.settings.routeLinksBetweenSpaces && old.state.settings.externalLinksSpaceID == nil)
    }

    @Test("A folder or an entry without a URL has no archive row")
    func archiveRowNeedsAURL() {
        let profile = UUID(), space = UUID()
        #expect(ArchivedEntry(Entry(kind: .folder, spaceID: space, profileID: profile, customLabel: "F"), reason: .manual, at: .now) == nil)
        #expect(ArchivedEntry(Entry(kind: .today, spaceID: space, profileID: profile), reason: .manual, at: .now) == nil)
        let pinned = Entry(kind: .pinned, spaceID: space, profileID: profile, storedURL: "https://s.example/", storedTitle: "S")
        #expect(ArchivedEntry(pinned, reason: .spaceDeleted, at: .now)?.url == "https://s.example/")
    }

    @Test("A JSON snapshot from before v7 decodes with an empty archive; snapshots leave the archive out")
    func snapshotWithoutArchive() throws {
        var state = sampleState()
        let entry = try #require(state.entries.first { $0.kind == .today })
        state.archive = [try #require(ArchivedEntry(entry, reason: .auto, at: Timestamp(milliseconds: 1)))]
        let encoded = try StateSnapshot(generation: 3, state: state).encoded()
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var inner = try #require(object["state"] as? [String: Any])
        #expect((inner["archive"] as? [Any])?.isEmpty == true)
        inner["archive"] = nil
        object["state"] = inner
        let decoded = try JSONDecoder().decode(StateSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.state.canonical() == snapshotted(state))
    }

    @Test("A JSON snapshot leaves the entries' navigation states out (B-73); the database keeps them")
    func snapshotWithoutNavigationStates() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url)
        let opened = try storage.open()
        let state = sampleState()
        #expect(state.entries.contains { $0.navigationState != nil })
        try storage.makeWriter(for: opened).writeAndWait(state, generation: opened.generation + 1)
        let snapshot = try StateSnapshot.read(from: storage.snapshotURL)
        #expect(snapshot.state.entries.allSatisfy { $0.navigationState == nil })
        #expect(!String(decoding: try Data(contentsOf: storage.snapshotURL), as: UTF8.self).contains("navigationState\":\""))
        #expect(try opened.database.loadState().state.entries.contains { $0.navigationState != nil })
    }

    @Test("A JSON snapshot from before v5 decodes with no navigation state")
    func entryDecodesWithoutNavigationState() throws {
        let entry = Entry(kind: .pinned, spaceID: UUID(), profileID: UUID(), storedURL: "https://a.example/")
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        object["navigationState"] = nil
        let decoded = try JSONDecoder().decode(Entry.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.navigationState == nil && decoded.storedURL == "https://a.example/")
    }

    @Test("A JSON snapshot from before v4 decodes with no pane order")
    func splitGroupDecodesWithoutMembers() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","layout":"vbox","ratios":[0.5,0.5]}"#
        let group = try JSONDecoder().decode(SplitGroup.self, from: Data(json.utf8))
        #expect(group.id == id && group.layout == .vbox && group.members.isEmpty)
    }

    @Test("Entry columns match the Entry record")
    func entryColumns() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let columns = try queue.read { db in try db.columns(in: "entry").map(\.name) }
        #expect(Set(columns) == [
            "id", "kind", "spaceID", "profileID", "folderID", "splitGroupID", "position", "storedURL", "storedTitle",
            "customLabel", "customIcon", "faviconID", "isCollapsed", "createdAt", "lastActiveAt", "liveURL", "liveTitle",
            "navigationState", "windowID",
        ])
    }

    @Test("The profiles are read without opening the store; no file reads as none (4.4b's directory move)")
    func storedProfiles() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.url.appending(path: "Room.sqlite")
        #expect(try RoomDatabase.storedProfiles(at: url).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path), "nothing created")
        var state = sampleState()
        state.profiles.append(Profile(name: "Work", position: 1))
        do {
            let database = try RoomDatabase(url: url)
            let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
            try writer.writeAndWait(state, generation: 1)
        }
        #expect(try RoomDatabase.storedProfiles(at: url) == state.profiles)
    }

    @Test("The settings are read without opening the store; no file reads as the defaults (4.7a's launch switches)")
    func storedSettings() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.url.appending(path: "Room.sqlite")
        #expect(try RoomDatabase.storedSettings(at: url).pdfsOpenInRoom)
        #expect(!FileManager.default.fileExists(atPath: url.path), "nothing created")
        var state = sampleState()
        state.settings.pdfsOpenInRoom = false
        do {
            let database = try RoomDatabase(url: url)
            let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
            try writer.writeAndWait(state, generation: 1)
        }
        #expect(try RoomDatabase.storedSettings(at: url) == state.settings)
    }

    @Test("Reopening a migrated file migrates nothing and keeps the data")
    func reopen() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let url = directory.url.appending(path: "Room.sqlite")
        let state = sampleState()
        do {
            let database = try RoomDatabase(url: url)
            let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
            try writer.writeAndWait(state, generation: 1)
        }
        let reopened = try RoomDatabase(url: url)
        let loaded = try reopened.loadState()
        #expect(loaded.generation == 1)
        #expect(loaded.state.canonical() == state.canonical())
        #expect(try reopened.integrityCheck() == ["ok"])
    }

    @Test("Schema checks reject an essential with a space and an unknown kind")
    func checks() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let profile = Profile(name: "P", position: 0)
        let space = Space(name: "S", profileID: profile.id, position: 0)
        try queue.write { db in
            try profile.insert(db)
            try space.insert(db)
            let bad = Entry(kind: .essential, spaceID: space.id, profileID: profile.id)
            #expect(throws: DatabaseError.self) { try bad.insert(db) }
            #expect(throws: DatabaseError.self) {
                try db.execute(sql: "INSERT INTO entry (id, kind, profileID, position, isCollapsed, createdAt) VALUES (x'01', 'tab', ?, 0, 0, 0)",
                               arguments: [profile.id])
            }
        }
    }

    @Test("Deferred foreign keys reject a dangling reference at commit")
    func foreignKeys() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let database = try RoomDatabase(url: directory.url.appending(path: "Room.sqlite"))
        let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
        var state = sampleState()
        state.entries[0].profileID = UUID()
        #expect(throws: DatabaseError.self) { try writer.writeAndWait(state, generation: 1) }
        #expect(try database.generation() == 0)
        #expect(try database.loadState().state.isEmpty)
    }

    @Test("Favicons insert by host with an autoincremented id")
    func favicon() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let saved = try queue.write { db in
            var icon = Favicon(host: "example.com", png: Data([1, 2, 3]), sha256: "abc", updatedAt: Timestamp(milliseconds: 9))
            try icon.insert(db)
            return icon
        }
        #expect(saved.id != nil)
        let fetched = try queue.read { db in try Favicon.filter(Column("host") == "example.com").fetchOne(db) }
        #expect(fetched == saved)
    }
}

@Suite("State writer")
struct StateWriterTests {
    @Test("Round trip: every field of every record survives")
    func roundTrip() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let database = try RoomDatabase(url: directory.url.appending(path: "Room.sqlite"))
        let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
        let state = sampleState()
        #expect(try writer.writeAndWait(state, generation: 1) == .committed)
        let loaded = try database.loadState()
        #expect(loaded.state.canonical() == state.canonical())
        #expect(try loaded.state.canonicalJSON() == state.canonicalJSON())
        #expect(loaded.state.settings.permanentCloseBehavior == .unloadSwitch)
        // Settings v0 (ROADMAP 2.8 task 2).
        #expect(loaded.state.settings == state.settings)
        #expect(loaded.state.settings.sidebarSide == .right && loaded.state.settings.appearance == .dark)
    }

    @Test("The archive is written with the state: rows inserted, updated and deleted in the same transaction as the entries")
    func archiveDiff() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let database = try RoomDatabase(url: directory.url.appending(path: "Room.sqlite"))
        let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
        var state = sampleState()
        try writer.writeAndWait(state, generation: 1)
        // The Today tab leaves the sidebar for the archive in one write.
        let today = try #require(state.entries.first { $0.kind == .today })
        state.entries.removeAll { $0.id == today.id }
        state.splitGroups = []
        for i in state.windowSpaces.indices where state.windowSpaces[i].selectedEntryID == today.id {
            state.windowSpaces[i].selectedEntryID = nil
        }
        state.archive = [try #require(ArchivedEntry(today, reason: .clear, at: Timestamp(milliseconds: 7_000)))]
        try writer.writeAndWait(state, generation: 2)
        var loaded = try database.loadState().state
        #expect(loaded.entries.contains { $0.id == today.id } == false)
        #expect(loaded.archive == state.archive)
        // Restore: the row goes, the entry comes back.
        state.archive = []
        state.entries.append(today)
        state.entries[state.entries.count - 1].splitGroupID = nil
        try writer.writeAndWait(state, generation: 3)
        loaded = try database.loadState().state
        #expect(loaded.archive.isEmpty && loaded.entries.contains { $0.id == today.id })
    }

    @Test("Diffs: updates, inserts and deletes land; untouched rows stay")
    func diff() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let database = try RoomDatabase(url: directory.url.appending(path: "Room.sqlite"))
        let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
        var state = sampleState()
        try writer.writeAndWait(state, generation: 1)
        state.entries[0].customLabel = "Inbox"
        let removed = state.entries.removeLast()
        state.windowSpaces.removeAll()
        state.entries.append(Entry(kind: .today, spaceID: state.spaces[0].id, profileID: state.profiles[0].id, liveURL: "https://new.example"))
        state.splitGroups.removeAll()
        try writer.writeAndWait(state, generation: 2)
        let loaded = try database.loadState()
        #expect(loaded.generation == 2)
        #expect(loaded.state.canonical() == state.canonical())
        #expect(!loaded.state.entries.contains { $0.id == removed.id })
        #expect(try database.foreignKeyViolations() == 0)
    }

    @Test("A stale generation is dropped")
    func staleGeneration() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let database = try RoomDatabase(url: directory.url.appending(path: "Room.sqlite"))
        let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
        var newer = sampleState()
        newer.entries[0].customLabel = "newer"
        var older = newer
        older.entries[0].customLabel = "older"
        #expect(try writer.writeAndWait(newer, generation: 5) == .committed)
        #expect(try writer.writeAndWait(older, generation: 4) == .stale)
        #expect(try writer.writeAndWait(older, generation: 5) == .stale)
        #expect(try database.loadState().state.entries.first { $0.id == newer.entries[0].id }?.customLabel == "newer")
        #expect(try database.generation() == 5)
    }

    @Test("A writer behind the database's generation refuses to write")
    func behindDatabase() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let database = try RoomDatabase(url: directory.url.appending(path: "Room.sqlite"))
        let first = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
        try first.writeAndWait(sampleState(), generation: 10)
        let second = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
        #expect(throws: StateWriterError.generationBehindDatabase(3, 10)) { try second.writeAndWait(sampleState(), generation: 3) }
    }

    @Test("Asynchronous writes queued out of order still end at the newest")
    func asyncOrdering() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let database = try RoomDatabase(url: directory.url.appending(path: "Room.sqlite"))
        let writer = StateWriter(database: database, snapshotURL: nil, committed: RoomState(), generation: 0)
        var states: [Int64: RoomState] = [:]
        var base = sampleState()
        for generation in Int64(1)...20 {
            base.entries[0].customLabel = "g\(generation)"
            states[generation] = base
        }
        for generation in [Int64(3), 1, 2, 20, 7, 19, 4] { writer.write(states[generation]!, generation: generation) }
        writer.drain()
        #expect(try database.generation() == 20)
        #expect(try database.loadState().state.canonical() == states[20]!.canonical())
    }

    @Test("JSON snapshot follows each commit")
    func snapshot() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url)
        let opened = try storage.open()
        let writer = storage.makeWriter(for: opened)
        let state = sampleState()
        try writer.writeAndWait(state, generation: opened.generation + 1)
        let snapshot = try StateSnapshot.read(from: storage.snapshotURL)
        #expect(snapshot.generation == opened.generation + 1)
        #expect(snapshot.state == snapshotted(state))
    }
}

@Suite("Storage: sessions and recovery")
struct StorageTests {
    @Test("The running flag detects an unclean exit; a clean-exit write clears it")
    func runningFlag() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url)
        let first = try storage.open()
        #expect(!first.uncleanExit)
        // Reopen without a clean exit: as after kill -9.
        let second = try storage.open()
        #expect(second.uncleanExit)
        let writer = storage.makeWriter(for: second)
        try writer.writeAndWait(sampleState(), generation: 1, cleanExit: true)
        #expect(try !storage.open().uncleanExit)
    }

    @Test("Opening runs quick_check after a clean quit and the full integrity_check only after an unclean exit (B-42)")
    func integrityCheckByExit() throws {
        #expect(RoomStorage.integrityCheck(afterUncleanExit: false) == .quick)
        #expect(RoomStorage.integrityCheck(afterUncleanExit: true) == .full)
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url)
        let first = try storage.open()
        #expect(first.check == .quick)  // a new database: no previous session
        // Reopen without a clean exit: as after kill -9.
        let second = try storage.open()
        #expect(second.check == .full)
        try storage.makeWriter(for: second).writeAndWait(sampleState(), generation: 1, cleanExit: true)
        #expect(try storage.open().check == .quick)
    }

    @Test("A clean exit with nothing new to write still clears the flag")
    func cleanExitStale() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url)
        let opened = try storage.open()
        let writer = storage.makeWriter(for: opened)
        try writer.writeAndWait(sampleState(), generation: 1)
        #expect(try writer.writeAndWait(sampleState(), generation: 1, cleanExit: true) == .stale)
        #expect(try !storage.open().uncleanExit)
    }

    @Test("A corrupt database is moved aside and rebuilt from the JSON snapshot")
    func recoverFromSnapshot() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url)
        let state = sampleState()
        do {
            let opened = try storage.open()
            try storage.makeWriter(for: opened).writeAndWait(state, generation: 7)
        }
        try? FileManager.default.removeItem(at: directory.url.appending(path: RoomStorage.databaseName + "-wal"))
        try Data(repeating: 0x5A, count: 8192).write(to: storage.databaseURL)
        let reopened = try storage.open()
        guard case .fromSnapshot(let generation, let aside) = reopened.recovery else {
            Issue.record("expected snapshot recovery, got \(String(describing: reopened.recovery))")
            return
        }
        #expect(generation == 7)
        #expect(reopened.generation == 7)
        #expect(reopened.state.canonical() == snapshotted(state))
        #expect(FileManager.default.fileExists(atPath: aside.appending(path: RoomStorage.databaseName).path))
        #expect(try reopened.database.integrityCheck() == ["ok"])
    }

    @Test("Opening brings a lagging or broken snapshot level with the database")
    func snapshotRefresh() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url)
        let state = sampleState()
        do {
            let opened = try storage.open()
            let writer = storage.makeWriter(for: opened)
            try writer.writeAndWait(state, generation: 1)
            var newer = state
            newer.entries[0].customLabel = "newer"
            try writer.writeAndWait(newer, generation: 2)
        }
        // As if killed between commit 2 and its snapshot.
        try StateSnapshot(generation: 1, state: state).encoded().write(to: storage.snapshotURL)
        _ = try storage.open()
        #expect(try StateSnapshot.read(from: storage.snapshotURL).generation == 2)
        try Data("{".utf8).write(to: storage.snapshotURL)
        _ = try storage.open()
        let refreshed = try StateSnapshot.read(from: storage.snapshotURL)
        #expect(refreshed.generation == 2 && refreshed.state.entries.contains { $0.customLabel == "newer" })
    }

    @Test("A database another connection holds locked fails the open and stays where it is (2.1 review)")
    func lockedIsNotCorrupt() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url, busyTimeout: 0.1)
        let state = sampleState()
        do {
            let opened = try storage.open()
            try storage.makeWriter(for: opened).writeAndWait(state, generation: 3)
            try opened.database.pool.close()
        }
        // A second Room instance in the middle of a write transaction.
        var configuration = Configuration()
        configuration.allowsUnsafeTransactions = true
        let other = try DatabaseQueue(path: storage.databaseURL.path, configuration: configuration)
        try other.writeWithoutTransaction { db in try db.execute(sql: "BEGIN IMMEDIATE") }
        #expect {
            _ = try storage.open()
        } throws: { error in
            guard case RoomStorage.OpenError.inUse = error else { return false }
            return true
        }
        #expect(!FileManager.default.fileExists(atPath: directory.url.appending(path: "Corrupt").path))
        try other.writeWithoutTransaction { db in try db.execute(sql: "ROLLBACK") }
        try other.close()
        let reopened = try storage.open()
        #expect(reopened.recovery == nil)
        #expect(reopened.generation == 3)
        #expect(reopened.state.canonical() == state.canonical())
    }

    @Test("A corrupt database without a snapshot starts empty")
    func recoverEmpty() throws {
        let directory = try TemporaryDirectory()
        defer { directory.cleanup() }
        let storage = RoomStorage(directory: directory.url)
        try Data(repeating: 0x5A, count: 8192).write(to: storage.databaseURL)
        let opened = try storage.open()
        guard case .empty = opened.recovery else {
            Issue.record("expected empty recovery")
            return
        }
        #expect(opened.state.isEmpty)
    }
}
