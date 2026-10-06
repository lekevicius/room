import Engine
import Foundation
import Model
import Store
import Testing
@testable import Import

/// A fresh state as the store seeds it: profile "Default", space "Space".
private func freshState() -> (RoomState, Model.Profile, Space) {
    let profile = Model.Profile(name: "Default", position: 0)
    let space = Space(name: "Space", profileID: profile.id, position: 0)
    return (RoomState(profiles: [profile], spaces: [space]), profile, space)
}

private func scan(_ kind: BrowserKind, profile: ImportProfileChoice? = nil) throws -> ImportScan {
    let source = try #require(ImportSources.sources(inDirectory: Fixtures.directory).first { $0.kind == kind })
    return ImportScanner.scan(source, profile: profile)
}

@Suite("Import: the plan and its preview (ROADMAP 4.3a task 2)")
struct PlannerTests {
    @Test("Chrome, one space, the bar into Essentials: 12 essentials, the rest pinned, folders clipped at depth 5, duplicates skipped")
    func chromeOneSpace() throws {
        let (state, profile, _) = freshState()
        var options = ImportOptions(targetSpace: .new(name: "Chrome"), targetProfile: profile.id)
        options.barIntoEssentials = true
        let plan = ImportPlanner.plan(try scan(.chrome, profile: .init(directory: "Default", name: "Person 1")), options: options,
                                      target: ImportTarget(state: state))
        let preview = plan.preview
        #expect(preview.spaces == 1 && preview.newProfiles == 0)
        #expect(preview.essentials == EntryRules.essentialsCap && preview.essentialsOverflow == 2)
        #expect(preview.pinned == 15 && preview.folders == 7 && preview.foldersFlattened == 2)
        #expect(preview.duplicates == 3)
        #expect(preview.skipped.map(\.reason) == ["a javascript: link", "hidden (a subframe)", "a chrome: page"])
        #expect(preview.historyURLs == 9 && preview.historyVisits == 15 && plan.historyProfile == profile.id)
        #expect(plan.batch.newSpaces.map(\.name) == ["Chrome"])
        let root = try #require(plan.batch.spaces.first?.pinned)
        // The bar's overflow and folders first, then "other", then mobile.
        #expect(root.map(title) == ["Site 11", "Site 12", "Work", "L1", "Beta", "Reading", "Example", "Mobile"])
        #expect(depth(root) == FolderRules.maxDepth)
    }

    @Test("Safari, one space per top-level folder: loose links in the target space, each folder its own space")
    func safariPerFolder() throws {
        let (state, profile, _) = freshState()
        var options = ImportOptions(targetSpace: .new(name: "Safari"), targetProfile: profile.id)
        options.layout = .spacePerFolder
        let plan = ImportPlanner.plan(try scan(.safari), options: options, target: ImportTarget(state: state))
        #expect(plan.batch.newSpaces.map(\.name) == ["Safari", "Dev", "Recipes", "Reading List", "Travel"])
        #expect(plan.preview.spaces == 5 && plan.preview.pinned == 9 && plan.preview.folders == 0 && plan.preview.duplicates == 1)
        #expect(plan.batch.spaces.map(\.pinned.count) == [3, 2, 1, 2, 1])
        #expect(plan.preview.historyURLs == 4 && plan.preview.historyVisits == 6)
        #expect(plan.preview.skipped.contains(SkippedItem("https://broken.example/", reason: "no successful visit")))
    }

    @Test("Netscape into an existing space: its pinned URLs and its profile's essentials count as duplicates; place: queries are skipped")
    func netscapeExisting() throws {
        var (state, profile, space) = freshState()
        state.entries = [Entry(kind: .pinned, spaceID: space.id, profileID: profile.id, storedURL: "https://www.mozilla.org"),
                         Entry(kind: .essential, spaceID: nil, profileID: profile.id, storedURL: "https://example.org/docs")]
        let options = ImportOptions(targetSpace: .existing(space.id), targetProfile: profile.id)
        let plan = ImportPlanner.plan(try scan(.bookmarksFile), options: options, target: ImportTarget(state: state))
        #expect(plan.preview.spaces == 0 && plan.preview.duplicates == 2)
        #expect(plan.preview.pinned == 4 && plan.preview.folders == 3)
        #expect(plan.preview.skipped.map(\.reason) == ["no URL", "a place: link"])
        #expect(plan.batch.spaces.map(\.space) == [.existing(space.id)])
    }

    @Test("Arc: a space per Arc space with its icon and colour, the default profile mapped to Room's, a profile made for the other, essentials, Today")
    func arc() throws {
        let (state, profile, _) = freshState()
        let plan = ImportPlanner.plan(try scan(.arc), options: ImportOptions(targetSpace: .new(name: "Arc"), targetProfile: profile.id),
                                      target: ImportTarget(state: state))
        #expect(plan.batch.newProfiles == ["Work"])
        #expect(plan.batch.newSpaces == [
            ImportBatch.NewSpace(name: "Home", icon: "🏠", themeColors: ["#3366CC"], profile: .existing(profile.id)),
            ImportBatch.NewSpace(name: "Work", icon: "💼", themeColors: ["#CC4D33"], profile: .new(0)),
            ImportBatch.NewSpace(name: "Side", profile: .existing(profile.id)),
        ])
        #expect(plan.batch.essentials.map(\.links.count) == [2, 1])
        let preview = plan.preview
        #expect(preview.spaces == 3 && preview.newProfiles == 1 && preview.essentials == 3 && preview.pinned == 5 && preview.folders == 2)
        #expect(preview.today == 3 && preview.duplicates == 1 && preview.skipped.count == 2 && plan.history.isEmpty)
        // A Room profile named "work" already there is used, not duplicated.
        var named = state
        named.profiles.append(Model.Profile(name: "work", position: 1))
        let reuse = ImportPlanner.plan(try scan(.arc), options: ImportOptions(targetSpace: .new(name: "Arc"), targetProfile: profile.id),
                                       target: ImportTarget(state: named))
        #expect(reuse.batch.newProfiles.isEmpty && reuse.batch.newSpaces[1].profile == .existing(named.profiles[1].id))
    }

    @Test("Arc essentials past the cap are pinned in the profile's first space")
    func arcEssentialsFull() throws {
        var (state, profile, space) = freshState()
        state.entries = (0..<11).map { Entry(kind: .essential, spaceID: nil, profileID: profile.id, storedURL: "https://e\($0).example/") }
        _ = space
        let plan = ImportPlanner.plan(try scan(.arc), options: ImportOptions(targetSpace: .new(name: "Arc"), targetProfile: profile.id),
                                      target: ImportTarget(state: state))
        #expect(plan.preview.essentials == 2 && plan.preview.essentialsOverflow == 1)
        #expect(plan.batch.spaces.first?.pinned.last == .link(ImportBatch.Link(url: "https://calendar.example.com/", title: "Calendar")))
    }

    @Test("History goes to the engine in batches of 2,000 with its visits and transitions")
    func historyBatches() throws {
        let (state, profile, _) = freshState()
        let times = (0..<4_500).map { Date(timeIntervalSince1970: 1_790_000_000 + Double($0)) }
        var scan = ImportScan(source: ImportSource(kind: .chrome, name: "Synthetic", location: Fixtures.directory), profile: nil)
        scan.history = .success(ImportedHistory(urls: times.enumerated().map { index, time in
            ImportedHistoryURL(url: "https://h\(index).example/", title: index == 0 ? "" : "Page \(index)", visitCount: 1, typedCount: 1,
                               lastVisit: time, visits: [ImportedVisit(time: time, transition: .typed)])
        }))
        let plan = ImportPlanner.plan(scan, options: ImportOptions(targetSpace: .new(name: "x"), targetProfile: profile.id),
                                      target: ImportTarget(state: state))
        #expect(plan.history.map(\.count) == [2_000, 2_000, 500])
        #expect(plan.history[0][0] == HistoryImportEntry(url: URL(string: "https://h0.example/")!, title: nil,
                                                         visits: [HistoryVisit(time: times[0], transition: .typed)]))
        #expect(plan.preview.historyURLs == 4_500 && plan.batch.isEmpty && plan.preview.spaces == 0)
    }
}

/// The plan applied to a real store (ROADMAP 4.3a exit: fixtures land with the preview's counts).
@Suite("Import: a plan applied to the store lands with the preview's counts")
@MainActor
struct ApplyTests {
    @Test("Chrome, Safari, Netscape and Arc in turn into one store: each import's rows equal its preview")
    func applyAll() throws {
        let directory = try Fixtures.scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try RoomStore.open(directory: directory)
        defer { store.close() }
        let sidebar = store.sidebar
        let profile = try #require(sidebar.profiles.first)
        let space = try #require(sidebar.spaces.first)
        func rows(_ kind: EntryKind) -> Int { sidebar.entries.values.count { $0.kind == kind } }
        func check(_ scan: ImportScan, _ options: ImportOptions) throws -> ImportPreview {
            let plan = ImportPlanner.plan(scan, options: options, target: ImportTarget(state: store.currentState()))
            let before = (sidebar.spaces.count, sidebar.profiles.count, rows(.folder), rows(.pinned), rows(.essential), rows(.today))
            let applied = try sidebar.applyImport(plan.batch)
            let preview = plan.preview
            #expect(sidebar.spaces.count - before.0 == preview.spaces && sidebar.profiles.count - before.1 == preview.newProfiles)
            #expect(rows(.folder) - before.2 == preview.folders && rows(.pinned) - before.3 == preview.pinned)
            #expect(rows(.essential) - before.4 == preview.essentials && rows(.today) - before.5 == preview.today)
            #expect(applied.essentialsRefused == 0 && applied.foldersFlattened == 0)
            return preview
        }
        var chrome = ImportOptions(targetSpace: .new(name: "Chrome"), targetProfile: profile.id)
        chrome.barIntoEssentials = true
        _ = try check(try scan(.chrome, profile: .init(directory: "Default", name: "Person 1")), chrome)
        #expect(sidebar.essentials(profile: profile.id).count == EntryRules.essentialsCap)
        var safari = ImportOptions(targetSpace: .new(name: "Safari"), targetProfile: profile.id)
        safari.layout = .spacePerFolder
        _ = try check(try scan(.safari), safari)
        let netscape = try check(try scan(.bookmarksFile), ImportOptions(targetSpace: .existing(space.id), targetProfile: profile.id))
        // "Docs" is one of the profile's essentials now (Chrome's bar).
        #expect(netscape.duplicates == 1)
        let arc = try check(try scan(.arc), ImportOptions(targetSpace: .new(name: "Arc"), targetProfile: profile.id))
        #expect(arc.essentials == 1 && arc.essentialsOverflow == 2)
        #expect(sidebar.spaces.map(\.name) == ["Space", "Chrome", "Safari", "Dev", "Recipes", "Reading List", "Travel", "Home", "Work", "Side"])
        #expect(sidebar.profiles.map(\.name) == ["Default", "Work"])
        let deepest = sidebar.entries.values.filter { $0.kind == .folder }.compactMap { FolderRules.depth(of: $0.id, in: sidebar.entries) }.max()
        #expect(deepest == FolderRules.maxDepth)
    }
}

private func title(_ node: ImportBatch.Node) -> String {
    switch node {
    case .link(let link): link.title ?? link.url
    case .folder(let name, _): name
    }
}

private func depth(_ nodes: [ImportBatch.Node]) -> Int {
    nodes.map { node in
        if case .folder(_, let children) = node { 1 + depth(children) } else { 0 }
    }.max() ?? 0
}
