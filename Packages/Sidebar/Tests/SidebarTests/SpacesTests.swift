import AppKit
import Model
import Chrome
import Store
import Testing
@testable import Sidebar

/// Spaces in the sidebar (ROADMAP 2.5): switching, per-space selection
/// memory, prepared lists, the cross-profile warning, icon drops, Delete
/// Space with Undo. Headless: the lists are never in a window.
@Suite("Sidebar: spaces (spec §B)")
struct SpacesTests {
    /// Three spaces of one profile, the first active.
    private func fixture() throws -> (SidebarFixture, [Space]) {
        let f = try SidebarFixture()
        let second = try f.sidebar.createSpace(name: "Two", profile: f.profile.id)
        let third = try f.sidebar.createSpace(name: "Three", profile: f.profile.id)
        return (f, [f.space, second, third])
    }

    @Test("Each space remembers its selection; switching back shows it in the card again")
    func selectionMemory() throws {
        let (f, spaces) = try fixture()
        let a = try f.sidebar.addEntry(.today, url: "https://a.example", space: spaces[0].id)
        let b = try f.sidebar.addEntry(.today, url: "https://b.example", space: spaces[1].id)
        f.controller.select(a.id)
        f.controller.showSpace(spaces[1].id, animated: false)
        #expect(f.controller.selectedEntryID == nil)
        f.controller.select(b.id)
        f.controller.showSpace(spaces[0].id, animated: false)
        #expect(f.controller.selectedEntryID == a.id)
        #expect(f.host.activated.last == a.id)
        f.controller.showSpace(spaces[1].id, animated: false)
        #expect(f.controller.selectedEntryID == b.id)
        #expect(f.store.windows.window(f.controller.windowID)?.activeSpaceID == spaces[1].id)
    }

    @Test("⌃digit picks the Nth space; ⌥⌘←/→ wrap around")
    func keys() throws {
        let (f, spaces) = try fixture()
        f.controller.showSpace(digit: 3)
        #expect(f.controller.activeSpaceID == spaces[2].id)
        f.controller.showAdjacentSpace(1)
        #expect(f.controller.activeSpaceID == spaces[0].id)
        f.controller.showAdjacentSpace(-1)
        #expect(f.controller.activeSpaceID == spaces[2].id)
        f.controller.showSpace(digit: 9)
        #expect(f.controller.activeSpaceID == spaces[2].id, "no ninth space: nothing happens")
    }

    @Test("A switch to a prepared space loads no list (the slide never waits on a reload)")
    func preparedLists() throws {
        let (f, spaces) = try fixture()
        for space in spaces { _ = try f.sidebar.addEntry(.today, url: "https://\(space.name).example", space: space.id) }
        f.controller.prepareSpaces()
        for space in spaces { f.controller.preparedPane(space.id) }
        let loads = f.controller.debugPaneLoads
        f.controller.showSpace(spaces[1].id)
        f.controller.showSpace(spaces[2].id)
        f.controller.showSpace(spaces[0].id)
        #expect(f.controller.debugPaneLoads == loads)
        // A list kept up to date while off screen: a tab added to a hidden space is in its outline.
        let late = try f.sidebar.addEntry(.today, url: "https://late.example", space: spaces[2].id)
        f.controller.showSpace(spaces[2].id, animated: false)
        #expect(f.controller.tree.displayedNode(for: late.id) != nil)
        #expect(f.controller.debugPaneLoads == loads)
    }

    @Test("The cross-profile warning shows once, and Cancel leaves the tab where it was")
    func warnOnce() throws {
        let f = try SidebarFixture()
        let work = f.sidebar.createProfile(name: "Work")
        let workSpace = try f.sidebar.createSpace(name: "Work", profile: work.id)
        let same = try f.sidebar.createSpace(name: "Same", profile: f.profile.id)
        let a = try f.sidebar.addEntry(.today, url: "https://a.example", space: f.space.id)
        let b = try f.sidebar.addEntry(.today, url: "https://b.example", space: f.space.id)
        var asked: [String] = []
        var answer = false
        f.controller.confirmations = { message in
            asked.append(message)
            return answer
        }
        f.controller.moveEntries([a.id], toSpace: same.id)
        #expect(asked.isEmpty, "same profile: no warning")
        f.controller.moveEntries([b.id], toSpace: workSpace.id)
        #expect(asked == ["Logins and cookies won't carry over"])
        #expect(f.sidebar.entry(b.id)?.spaceID == f.space.id)
        answer = true
        f.controller.moveEntries([b.id], toSpace: workSpace.id)
        #expect(f.sidebar.entry(b.id)?.spaceID == workSpace.id)
        #expect(f.sidebar.entry(b.id)?.profileID == work.id)
        f.controller.moveEntries([a.id], toSpace: workSpace.id)
        #expect(asked.count == 2, "confirmed once, never asked again")
        #expect(f.store.settings.settings.crossProfileMoveWarned)
    }

    @Test("Set Profile moves the space's tabs after the warning; the grid shows the new profile's essentials")
    func setProfile() throws {
        let f = try SidebarFixture()
        f.controller.confirmations = { _ in true }
        let work = f.sidebar.createProfile(name: "Work")
        let tab = try f.sidebar.addEntry(.today, url: "https://a.example", space: f.space.id)
        _ = try f.sidebar.addEntry(.essential, url: "https://mail.example", space: f.space.id)
        #expect(f.controller.tree.essentialIDs.count == 1)
        f.controller.setProfile(of: f.space.id, to: work.id)
        #expect(f.sidebar.entry(tab.id)?.profileID == work.id)
        #expect(f.controller.tree.essentialIDs.isEmpty)
    }

    @Test("Delete Space removes it with its tabs; Undo brings everything back")
    func deleteUndo() throws {
        let (f, spaces) = try fixture()
        let toasts = RecordingToasts()
        f.controller.toasts = toasts
        let tab = try f.sidebar.addEntry(.today, url: "https://a.example", space: spaces[1].id)
        f.controller.showSpace(spaces[1].id, animated: false)
        f.controller.select(tab.id)
        f.controller.deleteSpace(spaces[1].id)
        #expect(f.sidebar.space(spaces[1].id) == nil)
        #expect(f.host.unloaded.contains(tab.id))
        #expect(f.controller.activeSpaceID != spaces[1].id)
        let undo = try #require(toasts.shown.last?.action)
        undo.handler()
        #expect(f.sidebar.spaces.map(\.id) == spaces.map(\.id))
        #expect(f.sidebar.today(space: spaces[1].id).map(\.id) == [tab.id])
        #expect(f.controller.activeSpaceID == spaces[1].id)
    }

    @Test("New Space opens the space window; its form creates a space with its look and shows it")
    func formCreates() throws {
        let f = try SidebarFixture()
        var tints: [SpaceTheme?] = []
        var windows: [(UUID?, SpaceFormFocus)] = []
        f.controller.onTintChange = { theme, _ in tints.append(theme) }
        f.controller.onShowSpaceWindow = { windows.append(($0, $1)) }
        f.controller.newSpace()
        #expect(windows.count == 1 && windows.first?.0 == nil)
        let model = try #require(f.controller.spaceFormModel(for: nil))
        model.name = "Garden"
        model.icon = "leaf"
        model.wells = [SpaceFormModel.color(hex: "#3E9B5B")!]
        model.algorithm = .complementary
        f.controller.previewTheme(model)
        #expect(tints.last??.colors.count == 2)
        let id = f.controller.commitSpaceForm(model)
        let created = try #require(f.sidebar.spaces.last)
        #expect(id == created.id)
        #expect(created.name == "Garden")
        #expect(created.icon == "leaf")
        #expect(created.themeColors == ["#3E9B5B"])
        #expect(f.controller.activeSpaceID == created.id)
    }

    @Test("An empty name takes the default; Cancel writes nothing and the tint goes back")
    func formDefaults() throws {
        let f = try SidebarFixture()
        var tints: [SpaceTheme?] = []
        f.controller.onTintChange = { theme, _ in tints.append(theme) }
        let cancelled = try #require(f.controller.spaceFormModel(for: nil))
        cancelled.wells = [SpaceFormModel.color(hex: "#3E9B5B")!]
        f.controller.previewTheme(cancelled)
        f.controller.endThemePreview(animated: false)
        #expect(f.sidebar.spaces.count == 1)
        #expect(tints.last! == f.sidebar.spaces[0].theme)
        f.controller.commitSpaceForm(try #require(f.controller.spaceFormModel(for: nil)))
        #expect(f.sidebar.spaces.map(\.name) == ["Space", "Space 2"])
    }

    @Test("The space window's edit saves name, icon, theme and profile")
    func formEdits() throws {
        let f = try SidebarFixture()
        f.controller.confirmations = { _ in true }
        let space = f.sidebar.spaces[0]
        let work = f.sidebar.createProfile(name: "Work")
        let model = try #require(f.controller.spaceFormModel(for: space.id, focus: .routes))
        #expect(model.spaceID == space.id && model.initialFocus == .routes && model.name == space.name)
        model.name = "Home"
        model.icon = "🏠"
        model.wells = [SpaceFormModel.color(hex: "#3E9B5B")!]
        model.algorithm = .triadic
        model.opacity = 0.8
        model.profileID = work.id
        #expect(f.controller.commitSpaceForm(model) == space.id)
        let saved = try #require(f.sidebar.space(space.id))
        #expect(saved.name == "Home" && saved.icon == "🏠" && saved.themeColors == ["#3E9B5B"])
        #expect(saved.themeAlgorithm == .triadic && saved.themeOpacity == 0.8 && saved.profileID == work.id)
    }
}
