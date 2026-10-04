import Foundation
import Testing
@testable import Model

@Suite("Rule: isChanged normalisation (§A.1)")
struct ChangedTests {
    @Test("Trailing slash and fragment are ignored", arguments: [
        ("https://example.com/", "https://example.com"),
        ("https://example.com/docs/", "https://example.com/docs"),
        ("https://example.com/docs#intro", "https://example.com/docs"),
        ("https://example.com/docs/#intro", "https://example.com/docs"),
        ("HTTPS://Example.COM/docs", "https://example.com/docs"),
        ("https://example.com/?", "https://example.com/"),
    ])
    func same(_ pair: (String, String)) {
        #expect(URLNormalization.isSame(pair.0, pair.1))
    }

    @Test("Query, path, path case and scheme differences count", arguments: [
        ("https://example.com/?a=1", "https://example.com/"),
        ("https://example.com/?a=1", "https://example.com/?a=2"),
        ("https://example.com/a", "https://example.com/b"),
        ("https://example.com/Docs", "https://example.com/docs"),
        ("http://example.com", "https://example.com"),
        ("https://example.com:8443", "https://example.com"),
    ])
    func different(_ pair: (String, String)) {
        #expect(!URLNormalization.isSame(pair.0, pair.1))
    }

    @Test("Only loaded permanent entries can be changed")
    func entryKinds() {
        let profile = UUID(), space = UUID()
        var pinned = Entry(kind: .pinned, spaceID: space, profileID: profile, storedURL: "https://a.com/x")
        #expect(!EntryRules.isChanged(pinned), "unloaded")
        pinned.liveURL = "https://a.com/x/#top"
        #expect(!EntryRules.isChanged(pinned))
        pinned.liveURL = "https://a.com/y"
        #expect(EntryRules.isChanged(pinned))
        var essential = pinned
        essential.kind = .essential
        essential.spaceID = nil
        #expect(EntryRules.isChanged(essential))
        let today = Entry(kind: .today, spaceID: space, profileID: profile, liveURL: "https://a.com/y")
        #expect(!EntryRules.isChanged(today))
    }
}

@Suite("Rule: type conversions and the Essentials cap (§A.9)")
struct ConversionTests {
    let profile: Profile
    let space: Space

    init() {
        profile = Profile(name: "Default", position: 0)
        space = Space(name: "S", profileID: profile.id, position: 0)
    }

    @Test("Today → Pinned stores the current page")
    func todayToPinned() throws {
        let today = Entry(kind: .today, spaceID: space.id, profileID: profile.id, liveURL: "https://a.com/p", liveTitle: "P")
        let pinned = try EntryRules.converted(today, to: .pinned, in: space, essentialsCount: 0)
        #expect(pinned.kind == .pinned)
        #expect(pinned.storedURL == "https://a.com/p")
        #expect(pinned.storedTitle == "P")
        #expect(pinned.liveURL == "https://a.com/p")
        #expect(!EntryRules.isChanged(pinned))
    }

    @Test("Pinned → Today drops stored state, keeps the page")
    func pinnedToToday() throws {
        let folder = UUID()
        let pinned = Entry(kind: .pinned, spaceID: space.id, profileID: profile.id, folderID: folder,
                           storedURL: "https://a.com", storedTitle: "A", liveURL: "https://a.com/deep", liveTitle: "Deep")
        let today = try EntryRules.converted(pinned, to: .today, in: space, essentialsCount: 0)
        #expect(today.kind == .today)
        #expect(today.storedURL == nil && today.storedTitle == nil)
        #expect(today.liveURL == "https://a.com/deep" && today.liveTitle == "Deep")
        #expect(today.folderID == nil)
    }

    @Test("An unloaded pinned entry moved to Today opens its stored URL")
    func unloadedPinnedToToday() throws {
        let pinned = Entry(kind: .pinned, spaceID: space.id, profileID: profile.id, storedURL: "https://a.com", storedTitle: "A")
        let today = try EntryRules.converted(pinned, to: .today, in: space, essentialsCount: 0)
        #expect(today.liveURL == "https://a.com" && today.liveTitle == "A")
    }

    @Test("→ Essentials clears space and folder and respects the cap of 12")
    func toEssentials() throws {
        let pinned = Entry(kind: .pinned, spaceID: space.id, profileID: profile.id, folderID: UUID(), storedURL: "https://a.com")
        let essential = try EntryRules.converted(pinned, to: .essentials, in: space, essentialsCount: 11)
        #expect(essential.kind == .essential && essential.spaceID == nil && essential.folderID == nil)
        #expect(throws: EntryConversionError.essentialsFull(cap: 12)) {
            try EntryRules.converted(pinned, to: .essentials, in: space, essentialsCount: 12)
        }
        // Reordering inside a full grid is not an addition.
        #expect(try EntryRules.converted(essential, to: .essentials, in: space, essentialsCount: 12).kind == .essential)
        #expect(EntryRules.canAddEssential(currentCount: 11))
        #expect(!EntryRules.canAddEssential(currentCount: 12))
    }

    @Test("Today → Essentials stores the page; a Today tab without a page cannot be pinned")
    func todayToEssentials() throws {
        let today = Entry(kind: .today, spaceID: space.id, profileID: profile.id, liveURL: "https://a.com")
        let essential = try EntryRules.converted(today, to: .essentials, in: space, essentialsCount: 0)
        #expect(essential.storedURL == "https://a.com" && essential.spaceID == nil)
        let blank = Entry(kind: .today, spaceID: space.id, profileID: profile.id)
        #expect(throws: EntryConversionError.noURL) { try EntryRules.converted(blank, to: .pinned, in: space, essentialsCount: 0) }
    }

    @Test("Essential → Pinned keeps the stored URL and takes the target space")
    func essentialToPinned() throws {
        let essential = Entry(kind: .essential, spaceID: nil, profileID: profile.id, storedURL: "https://a.com", liveURL: "https://a.com/x")
        let pinned = try EntryRules.converted(essential, to: .pinned, in: space, essentialsCount: 5)
        #expect(pinned.kind == .pinned && pinned.spaceID == space.id && pinned.storedURL == "https://a.com")
        #expect(EntryRules.isChanged(pinned))
    }

    @Test("Folders stay in the pinned section; conversion takes the target profile")
    func folders() throws {
        let otherProfile = UUID()
        let target = Space(name: "T", profileID: otherProfile, position: 1)
        let folder = Entry(kind: .folder, spaceID: space.id, profileID: profile.id, customLabel: "F")
        #expect(throws: EntryConversionError.folderOutsidePinned) { try EntryRules.converted(folder, to: .today, in: space, essentialsCount: 0) }
        #expect(throws: EntryConversionError.folderOutsidePinned) { try EntryRules.converted(folder, to: .essentials, in: space, essentialsCount: 0) }
        let moved = try EntryRules.converted(folder, to: .pinned, in: target, essentialsCount: 0)
        #expect(moved.spaceID == target.id && moved.profileID == otherProfile)
    }
}

@Suite("Rule: folder depth ≤ 5 (§A.6)")
struct FolderDepthTests {
    /// A chain of `count` nested folders; returns them outermost first.
    func chain(_ count: Int, space: UUID = UUID(), profile: UUID = UUID()) -> [Entry] {
        var result: [Entry] = []
        for _ in 0..<count {
            result.append(Entry(kind: .folder, spaceID: space, profileID: profile, folderID: result.last?.id))
        }
        return result
    }

    func map(_ entries: [Entry]) -> [UUID: Entry] { Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) }) }

    @Test("Depth counts folders from the root")
    func depth() {
        let folders = chain(5)
        let entries = map(folders)
        #expect(folders.enumerated().allSatisfy { FolderRules.depth(of: $0.element.id, in: entries) == $0.offset + 1 })
    }

    @Test("A sixth level is refused; a tab may go into the fifth")
    func newFolder() throws {
        let folders = chain(5)
        let entries = map(folders)
        try FolderRules.validateNewFolder(in: folders[3].id, in: entries)
        #expect(throws: FolderPlacementError.tooDeep(maxDepth: 5)) { try FolderRules.validateNewFolder(in: folders[4].id, in: entries) }
        let tab = Entry(kind: .pinned, spaceID: folders[0].spaceID, profileID: folders[0].profileID)
        try FolderRules.validatePlacement(of: tab.id, into: folders[4].id, in: map(folders + [tab]))
    }

    @Test("Moving a subtree counts its own height")
    func subtree() throws {
        let outer = chain(3)
        let moving = chain(2)
        let entries = map(outer + moving)
        try FolderRules.validatePlacement(of: moving[0].id, into: outer[2].id, in: entries)
        let deeper = chain(3)
        #expect(throws: FolderPlacementError.tooDeep(maxDepth: 5)) {
            try FolderRules.validatePlacement(of: deeper[0].id, into: outer[2].id, in: map(outer + deeper))
        }
    }

    @Test("A folder cannot move into itself or a descendant")
    func cycle() {
        let folders = chain(3)
        let entries = map(folders)
        #expect(throws: FolderPlacementError.cycle) { try FolderRules.validatePlacement(of: folders[0].id, into: folders[2].id, in: entries) }
        #expect(throws: FolderPlacementError.cycle) { try FolderRules.validatePlacement(of: folders[1].id, into: folders[1].id, in: entries) }
    }
}

@Suite("Rule: MRU, ⌘W and sidebar order (§A.3, §A.7, §G)")
struct NavigationTests {
    let profile = UUID(), space = UUID()

    func entry(_ kind: EntryKind, active: Int64? = nil, folder: UUID? = nil, collapsed: Bool = false) -> Entry {
        Entry(kind: kind, spaceID: kind == .essential ? nil : space, profileID: profile, folderID: folder,
              storedURL: kind.isPermanent ? "https://a.com" : nil, isCollapsed: collapsed,
              lastActiveAt: active.map(Timestamp.init(milliseconds:)), liveURL: kind == .today ? "https://t.com" : nil)
    }

    @Test("⌘W steps for every behaviour and kind", arguments: PermanentCloseBehavior.allCases)
    func closeSteps(_ behavior: PermanentCloseBehavior) {
        let expected: CloseSteps = switch behavior {
        case .resetUnloadSwitch: [.switchAway, .unload, .reset]
        case .unloadSwitch: [.switchAway, .unload]
        case .resetSwitch: [.switchAway, .reset]
        case .switchOnly: [.switchAway]
        case .reset: [.reset]
        case .close: [.switchAway, .unload, .remove]
        }
        #expect(NavigationRules.closeSteps(for: .pinned, behavior: behavior) == expected)
        #expect(NavigationRules.closeSteps(for: .essential, behavior: behavior) == expected)
        #expect(NavigationRules.closeSteps(for: .today, behavior: behavior) == [.switchAway, .unload, .remove])
        #expect(NavigationRules.closeSteps(for: .folder, behavior: behavior).isEmpty)
    }

    @Test("The default behaviour is reset-unload-switch, and permanent entries are never removed by it")
    func defaultBehavior() {
        #expect(Settings().permanentCloseBehavior == .resetUnloadSwitch)
        #expect(!NavigationRules.closeSteps(for: .pinned, behavior: Settings().permanentCloseBehavior).contains(.remove))
    }

    @Test("MRU: most recent first, never-used last in sidebar order")
    func mru() {
        let a = entry(.pinned, active: 10), b = entry(.today, active: 30), c = entry(.today), d = entry(.today, active: 20), e = entry(.pinned)
        #expect(NavigationRules.mruOrder([a, b, c, d, e]).map(\.id) == [b, d, a, c, e].map(\.id))
    }

    @Test("Closing falls back to the MRU other entry")
    func fallbackMRU() {
        let a = entry(.pinned, active: 10), b = entry(.today, active: 30), c = entry(.today, active: 20)
        #expect(NavigationRules.closeFallback(closing: b, order: [a, b, c]) == .select(c.id))
        #expect(NavigationRules.closeFallback(closing: a, order: [a, b, c]) == .select(b.id))
    }

    @Test("Without MRU history: first Today tab, then a new tab or the empty state")
    func fallbackWithoutHistory() {
        let pinned = entry(.pinned, active: 5), today1 = entry(.today), today2 = entry(.today)
        #expect(NavigationRules.closeFallback(closing: pinned, order: [pinned, today1, today2]) == .select(today1.id))
        #expect(NavigationRules.closeFallback(closing: pinned, order: [pinned]) == .newTodayTabAndPalette)
        let lone = entry(.today, active: 3)
        #expect(NavigationRules.closeFallback(closing: lone, order: [lone]) == .emptyState)
        #expect(NavigationRules.closeFallback(closing: lone, order: [lone, entry(.folder)]) == .emptyState)
    }

    @Test("Sidebar order: essentials, pinned depth-first skipping collapsed folders, then Today")
    func sidebarOrder() {
        let e1 = entry(.essential), e2 = entry(.essential)
        let open = entry(.folder), closed = entry(.folder, collapsed: true)
        let p1 = entry(.pinned), inOpen = entry(.pinned, folder: open.id), inClosed = entry(.pinned, folder: closed.id), p2 = entry(.pinned)
        let t1 = entry(.today), t2 = entry(.today)
        let order = NavigationRules.sidebarOrder(
            essentials: [e1, e2], pinnedRoot: [p1, open, closed, p2],
            pinnedChildren: [open.id: [inOpen], closed.id: [inClosed]], today: [t1, t2])
        #expect(order.map(\.id) == [e1, e2, p1, inOpen, p2, t1, t2].map(\.id))
        let collapsedSection = NavigationRules.sidebarOrder(
            essentials: [e1], pinnedRoot: [p1], pinnedChildren: [:], today: [t1], pinnedCollapsed: true)
        #expect(collapsedSection.map(\.id) == [e1, t1].map(\.id))
    }

    @Test("⌘1…⌘8 pick the Nth item, ⌘9 the last")
    func digits() {
        let items = (0..<10).map { _ in entry(.today) }
        #expect(NavigationRules.digitTarget(1, in: items)?.id == items[0].id)
        #expect(NavigationRules.digitTarget(8, in: items)?.id == items[7].id)
        #expect(NavigationRules.digitTarget(9, in: items)?.id == items[9].id)
        #expect(NavigationRules.digitTarget(5, in: Array(items.prefix(3))) == nil)
        #expect(NavigationRules.digitTarget(9, in: Array(items.prefix(3)))?.id == items[2].id)
        #expect(NavigationRules.digitTarget(9, in: []) == nil)
        #expect(NavigationRules.digitTarget(0, in: items) == nil)
    }

    @Test("⇧⌘] / ⌥⌘↓ step through the sidebar order and wrap; no selection starts at an end (§G)")
    func adjacent() {
        let items = (0..<3).map { _ in entry(.today) }
        #expect(NavigationRules.adjacent(to: items[0].id, offset: 1, in: items)?.id == items[1].id)
        #expect(NavigationRules.adjacent(to: items[2].id, offset: 1, in: items)?.id == items[0].id)
        #expect(NavigationRules.adjacent(to: items[0].id, offset: -1, in: items)?.id == items[2].id)
        #expect(NavigationRules.adjacent(to: nil, offset: 1, in: items)?.id == items[0].id)
        #expect(NavigationRules.adjacent(to: UUID(), offset: -1, in: items)?.id == items[2].id)
        #expect(NavigationRules.adjacent(to: nil, offset: 1, in: []) == nil)
    }

    @Test("A tab opened from a page goes below a Today opener, after its previous one, or to the top of Today (§A.7)")
    func relatedTabIndex() {
        let today = (0..<4).map { _ in entry(.today) }
        let pinned = entry(.pinned)
        #expect(NavigationRules.relatedTabIndex(opener: today[1], lastRelated: nil, today: today) == 2)
        #expect(NavigationRules.relatedTabIndex(opener: today[1], lastRelated: today[2].id, today: today) == 3)
        #expect(NavigationRules.relatedTabIndex(opener: pinned, lastRelated: nil, today: today) == 0)
        #expect(NavigationRules.relatedTabIndex(opener: pinned, lastRelated: today[0].id, today: today) == 1)
        // The previous related tab was closed meanwhile: right below the opener again.
        #expect(NavigationRules.relatedTabIndex(opener: today[3], lastRelated: UUID(), today: today) == 4)
    }
}

@Suite("Values")
struct ValueTests {
    @Test("Settings decode missing and unknown keys to defaults")
    func settingsDefaults() throws {
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(#"{"permanentCloseBehavior":"bogus","future":1}"#.utf8))
        #expect(decoded == Settings())
        let partial = try JSONDecoder().decode(Settings.self, from: Data(#"{"archiveAfterHours":24}"#.utf8))
        #expect(partial.archiveAfterHours == 24 && partial.permanentCloseBehavior == .resetUnloadSwitch)
        // Suggestions are on and the engine is Google unless the user chose otherwise (2026-10-03).
        #expect(partial.searchSuggestions && partial.searchEngine == "google")
        // Settings v0 (2.8a): a database written before them reads the left sidebar and the system appearance.
        #expect(partial.sidebarSide == .left && partial.appearance == .system)
        let unknown = try JSONDecoder().decode(Settings.self, from: Data(#"{"sidebarSide":"top","appearance":"sepia"}"#.utf8))
        #expect(unknown.sidebarSide == .left && unknown.appearance == .system)
        // 2.8b: a database written before the first run shows the card once; both opt-ins read off.
        #expect(!partial.firstRunDone && !partial.crashReports && !partial.automaticUpdateChecks)
        let wrong = try JSONDecoder().decode(Settings.self, from: Data(#"{"crashReports":"yes","automaticUpdateChecks":1}"#.utf8))
        #expect(!wrong.crashReports && !wrong.automaticUpdateChecks)
    }

    @Test("Timestamps round-trip through JSON and rounding is stable")
    func timestamps() throws {
        let date = Date(timeIntervalSince1970: 1_759_500_000.123_456)
        let stamp = Timestamp(date)
        #expect(stamp.milliseconds == 1_759_500_000_123)
        #expect(Timestamp(stamp.date) == stamp)
        let data = try JSONEncoder().encode(stamp)
        #expect(String(decoding: data, as: UTF8.self) == "1759500000123")
        #expect(try JSONDecoder().decode(Timestamp.self, from: data) == stamp)
    }

    @Test("Canonical form does not depend on array order")
    func canonical() throws {
        let state = sampleState()
        var shuffled = state
        shuffled.entries.reverse()
        shuffled.spaces.reverse()
        #expect(try state.canonicalJSON() == shuffled.canonicalJSON())
    }
}
