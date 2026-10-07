import AppKit
import Model
import Store
import Testing
@testable import Sidebar

/// The incognito window's sidebar (4.8b, ROADMAP 4.8 task 7): a Today list
/// under a note, no pinned section, no essentials, no pin commands.
@Suite("Incognito sidebar")
@MainActor
struct IncognitoSidebarTests {
    @Test("The tree is the note, the Today list and New Tab; pinning and essentials do not apply")
    func todayOnly() throws {
        let profile = Profile(name: "Default", position: 0)
        let store = RoomStore.incognito(profile: profile, settings: Settings(), sidebarWidth: 240, themeColors: ["#26262C"])
        let window = try #require(store.windows.windows.first)
        let space = try #require(store.sidebar.spaces.first)
        let controller = SidebarController(store: store, windowID: window.id, incognito: true)
        let host = RecordingHost()
        controller.host = host
        controller.bodyView.frame = NSRect(x: 0, y: 0, width: 240, height: 800)
        let one = try store.sidebar.addEntry(.today, url: "https://one.example/", title: "One", space: space.id, window: window.id)
        let two = try store.sidebar.addEntry(.today, url: "https://two.example/", title: "Two", space: space.id, window: window.id)
        // Even an entry pinned behind the sidebar's back (none should be) is not listed.
        let pinned = try store.sidebar.addEntry(.pinned, url: "https://pinned.example/", title: "Pinned", space: space.id)
        controller.reloadFromStore()
        let tree = controller.tree
        #expect(tree.isIncognito)
        let root = tree.children(of: nil).map(\.kind)
        #expect(root == [.spaceTitle, .separator, .entry(two.id), .entry(one.id), .newTab]
            || root == [.spaceTitle, .separator, .entry(one.id), .entry(two.id), .newTab])
        #expect(tree.children(of: tree.spaceTitle).isEmpty && !tree.isExpandable(tree.spaceTitle))
        #expect(!controller.debugIsListed(pinned.id))
        #expect(SidebarTree.incognitoNote == "Pages here are not saved")
        controller.select(one.id)
        #expect(controller.pinCommandTitle == nil && controller.essentialsCommandTitle == nil)
        #expect(controller.grid.isHidden && controller.footer.plusButton.isHidden)
        #expect(store.sidebar.spaces.count == 1)
    }
}
