import Foundation
import GRDB
import Testing
@testable import Model

@Suite("Schema and migrations")
struct SchemaTests {
    @Test("v1 creates every table; v2 (history frecency), v3 (history per profile) and v4 (split pane order) follow")
    func v1Tables() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        let tables = ["profile", "space", "entry", "split_group", "window", "window_space", "favicon",
                      "history_url", "history_visit", "history_fts", "history_host", "kv"]
        let missing = try queue.read { db in try tables.filter { try !db.tableExists($0) } }
        #expect(missing.isEmpty)
        let applied = try queue.read { db in try Schema.migrator.appliedMigrations(db) }
        #expect(applied == [Schema.v1, Schema.v2, Schema.v3, Schema.v4])
        let completed = try queue.read { db in try Schema.migrator.hasCompletedMigrations(db) }
        #expect(completed)
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
            for entry in [today1, pinned, today0] { try entry.insert(db) }
        }
        migrator = Schema.migrator
        try migrator.migrate(queue)
        let loaded = try queue.read { db in try SplitGroup.fetchOne(db, key: group) }
        #expect(loaded?.members == [pinned.id, today0.id, today1.id])
        #expect(loaded?.ratios == [0.3, 0.3, 0.4])
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
        ])
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

    @Test("History FTS (trigram, external content) follows history_url")
    func historyFTS() throws {
        let queue = try DatabaseQueue()
        try Schema.migrator.migrate(queue)
        try queue.write { db in
            let profile = UUID()
            try db.execute(sql: "INSERT INTO history_url (profileID, url, title, lastVisitAt) VALUES (?, ?, ?, 0)",
                           arguments: [profile, "https://en.wikipedia.org/wiki/Vilnius", "Vilnius - Wikipedia"])
            try db.execute(sql: "INSERT INTO history_url (profileID, url, title, lastVisitAt) VALUES (?, ?, ?, 0)",
                           arguments: [profile, "https://example.com", "Example Domain"])
            let match = try String.fetchAll(db, sql: "SELECT url FROM history_fts WHERE history_fts MATCH ?", arguments: ["ikip"])
            #expect(match == ["https://en.wikipedia.org/wiki/Vilnius"])
            try db.execute(sql: "UPDATE history_url SET title = 'Renamed' WHERE url = 'https://example.com'")
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM history_fts WHERE history_fts MATCH 'Renamed'") == 1)
            try db.execute(sql: "DELETE FROM history_url WHERE url LIKE '%wikipedia%'")
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM history_fts WHERE history_fts MATCH 'ikip'") == 0)
        }
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
        #expect(snapshot.state == state.canonical())
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
        #expect(reopened.state.canonical() == state.canonical())
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
