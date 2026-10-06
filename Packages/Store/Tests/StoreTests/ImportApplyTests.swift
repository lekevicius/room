import Foundation
import Model
import Testing
@testable import Store

@Suite("Store: applying an import (Phase 4.3a)")
struct ImportApplyTests {
    @Test("One change creates the profile, the space, folders, pinned, Today and essentials; refs are checked first")
    func apply() throws {
        let test = try TestStore()
        let sidebar = test.store.sidebar
        let defaultProfile = try #require(sidebar.profiles.first)
        let home = try #require(sidebar.spaces.first)
        try sidebar.addEntry(.pinned, url: "https://existing.example/", space: home.id)
        var changes = 0
        let token = sidebar.observe { _ in changes += 1 }
        defer { token.cancel() }
        let batch = ImportBatch(
            newProfiles: ["Default", "Work"],
            newSpaces: [ImportBatch.NewSpace(name: "Work", icon: "💼", themeColors: ["#CC4D33"], profile: .new(1))],
            spaces: [
                ImportBatch.SpaceItems(space: .existing(home.id), pinned: [
                    .link(.init(url: "https://a.example/", title: "A")),
                    .folder(name: "F", children: [.link(.init(url: "https://b.example/", title: nil)), .folder(name: "G", children: [])]),
                ], today: [.init(url: "https://t.example/", title: "T")]),
                ImportBatch.SpaceItems(space: .new(0), pinned: [.link(.init(url: "https://w.example/", title: "W"))]),
            ],
            essentials: [ImportBatch.Essentials(profile: .existing(defaultProfile.id),
                                                links: (1...14).map { .init(url: "https://e\($0).example/", title: nil) })])
        let applied = try sidebar.applyImport(batch)
        #expect(changes == 1)
        #expect(sidebar.profiles.map(\.name) == ["Default", "Default 2", "Work"])
        #expect(applied.profiles.count == 2 && applied.spaces.count == 1)
        #expect(applied.folders == 2 && applied.pinned == 3 && applied.today == 1)
        #expect(applied.essentials == EntryRules.essentialsCap && applied.essentialsRefused == 2)
        let work = try #require(sidebar.space(applied.spaces[0]))
        #expect(work.name == "Work" && work.icon == "💼" && work.profileID == applied.profiles[1] && work.themeColors == ["#CC4D33"])
        let root = sidebar.pinned(space: home.id)
        #expect(root.map(\.position) == [0, 1, 2])
        #expect(root.map(\.storedURL) == ["https://existing.example/", "https://a.example/", nil])
        #expect(sidebar.pinned(space: home.id, folder: root[2].id).map(\.displayTitle) == ["https://b.example/", "G"])
        #expect(sidebar.today(space: home.id).map(\.liveURL) == ["https://t.example/"])
        #expect(sidebar.essentials(profile: defaultProfile.id).count == EntryRules.essentialsCap)

        // A batch that names a space that does not exist changes nothing.
        let before = sidebar.entries.count
        let missing = UUID()
        #expect(throws: SidebarError.unknownSpace(missing)) {
            try sidebar.applyImport(ImportBatch(newProfiles: ["X"], spaces: [ImportBatch.SpaceItems(
                space: .existing(missing), pinned: [.link(.init(url: "https://x/", title: nil))])]))
        }
        #expect(sidebar.entries.count == before && sidebar.profiles.count == 3 && changes == 1)
        test.store.close()
    }

    @Test("Folders deeper than five levels when the batch lands give their links to the fifth")
    func depthClipOnApply() throws {
        let test = try TestStore()
        let sidebar = test.store.sidebar
        let home = try #require(sidebar.spaces.first)
        var node = ImportBatch.Node.folder(name: "L7", children: [.link(.init(url: "https://seven.example/", title: nil))])
        for level in (1...6).reversed() {
            node = .folder(name: "L\(level)", children: [.link(.init(url: "https://\(level).example/", title: nil)), node])
        }
        let applied = try sidebar.applyImport(ImportBatch(spaces: [ImportBatch.SpaceItems(space: .existing(home.id), pinned: [node])]))
        #expect(applied.folders == 5 && applied.foldersFlattened == 2 && applied.pinned == 7)
        let deepest = try #require(sidebar.entries.values.first { $0.customLabel == "L5" })
        #expect(FolderRules.depth(of: deepest.id, in: sidebar.entries) == 5)
        #expect(sidebar.pinned(space: home.id, folder: deepest.id).compactMap(\.storedURL)
            == ["https://5.example/", "https://6.example/", "https://seven.example/"])
        test.store.close()
    }
}
