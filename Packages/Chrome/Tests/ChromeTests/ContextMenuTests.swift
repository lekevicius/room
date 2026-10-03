import AppKit
import Engine
import FakeEngine
import Testing
import UniformTypeIdentifiers
@testable import Chrome

@MainActor
@Suite("Context menus: MenuModel → NSMenu with Room's items (ROADMAP 2.6 task 2)")
struct ContextMenuTests {
    private let items: [MenuItem] = [
        .separator(),
        MenuItem(id: 100, title: "Back", isEnabled: false),
        MenuItem(id: 101, title: "Reload", keyEquivalent: "r", keyEquivalentModifiers: .command),
        .separator(), .separator(),
        MenuItem(id: 102, kind: .checkbox, title: "Spelling", isChecked: true),
        MenuItem(id: 103, kind: .submenu([MenuItem(id: 104, kind: .radio(group: 1), title: "English", isChecked: true)]), title: "Language"),
        .separator(),
    ]

    @Test("Engine items keep their ids, state and key equivalents; stray separators go")
    func mapping() {
        let model = MenuModel(items: items) { _ in }
        let menu = ContextMenu(model: model, element: ContextMenuElement(location: .zero)) { _ in }.menu
        #expect(menu.items.map(\.title) == ["Back", "Reload", "", "Spelling", "Language"])
        #expect(menu.items[0].tag == 100 && !menu.items[0].isEnabled)
        #expect(menu.items[1].keyEquivalent == "r" && menu.items[1].keyEquivalentModifierMask == .command)
        #expect(menu.items[2].isSeparatorItem)
        #expect(menu.items[3].state == .on)
        let language = try? #require(menu.items[4].submenu)
        #expect(language?.items.first?.tag == 104 && language?.items.first?.state == .on)
    }

    @Test("A link gets Open Link in New Tab, Open Link in Peek (disabled until 2.7) and Copy Link, before the engine's items")
    func linkItems() {
        let link = URL(string: "https://example.com/a")!
        let model = MenuModel(items: items) { _ in }
        let menu = ContextMenu(model: model, element: ContextMenuElement(location: .zero, linkURL: link)) { _ in }.menu
        #expect(Array(menu.items.prefix(4).map(\.title)) == ["Open Link in New Tab", "Open Link in Peek", "Copy Link", ""])
        #expect(menu.items[0].isEnabled && !menu.items[1].isEnabled)
        let image = ContextMenuElement(location: .zero, sourceURL: URL(string: "https://example.com/i.png")!, mediaType: .image)
        #expect(ContextMenu.roomActions(for: image) == [.openImageInNewTab(URL(string: "https://example.com/i.png")!),
                                                         .copyImageAddress(URL(string: "https://example.com/i.png")!)])
        #expect(ContextMenu.roomActions(for: ContextMenuElement(location: .zero, linkURL: URL(string: "javascript:void(0)")!)).isEmpty)
    }

    @Test("The engine hears once: its item's id, or cancel for a Room item or no choice")
    func engineHearsOnce() async throws {
        _ = NSApplication.shared  // menu items send their actions through NSApp
        var heard: [MenuItem.ID?] = []
        var performed: [RoomMenuAction] = []
        let link = URL(string: "https://example.com/a")!
        let engineChoice = ContextMenu(model: MenuModel(items: items) { heard.append($0) },
                                       element: ContextMenuElement(location: .zero, linkURL: link)) { performed.append($0) }
        let reload = try #require(engineChoice.menu.items.firstIndex { $0.tag == 101 })
        engineChoice.menu.performActionForItem(at: reload)
        engineChoice.menuDidClose(engineChoice.menu)

        let roomChoice = ContextMenu(model: MenuModel(items: items) { heard.append($0) },
                                     element: ContextMenuElement(location: .zero, linkURL: link)) { performed.append($0) }
        roomChoice.menu.performActionForItem(at: 2)
        roomChoice.menuDidClose(roomChoice.menu)

        let noChoice = ContextMenu(model: MenuModel(items: items) { heard.append($0) },
                                   element: ContextMenuElement(location: .zero)) { performed.append($0) }
        noChoice.menuDidClose(noChoice.menu)
        for _ in 0..<5 { await Task.yield() }
        #expect(heard == [101, nil, nil])
        #expect(performed == [.copyLink(link)])
    }

    @Test("PageChrome presents the menu and runs Room's actions on the page that asked (FakeEngine)")
    func onAPage() async throws {
        _ = NSApplication.shared
        let engine = FakeApplication()
        try engine.initialize(EngineConfiguration(userDataDirectory: FileManager.default.temporaryDirectory))
        let page = try engine.profile(named: "Default").makeWebContents()
        let chrome = PageChrome()
        page.uiDelegate = chrome
        var presented: ContextMenu?
        chrome.presentMenu = { menu, _, _ in presented = menu }
        var opened: [URL] = []
        chrome.performMenuAction = { action, _ in if case .openLinkInNewTab(let url) = action { opened.append(url) } }
        let link = URL(string: "https://example.com/b")!
        let chosen = Task { await page.simulateContextMenu(ContextMenuElement(location: NSPoint(x: 4, y: 4), linkURL: link), items: items) }
        for _ in 0..<10 { await Task.yield() }
        let menu = try #require(presented)
        menu.menu.performActionForItem(at: 0)
        #expect(await chosen.value == nil)
        #expect(opened == [link])
    }
}

@Suite("File chooser: the accept attribute filters the panel (ROADMAP 2.6 task 2)")
struct FileChooserTests {
    @Test("MIME types, wildcards and extensions map to content types; unknown ones leave any file pickable")
    func acceptTypes() {
        #expect(FileChooser.contentTypes(accept: ["image/*"]) == [.image])
        #expect(FileChooser.contentTypes(accept: ["video/*", "audio/*"]) == [.movie, .audio])
        #expect(FileChooser.contentTypes(accept: [".pdf", "application/pdf", "  .PNG "]) == [.pdf, .png])
        #expect(FileChooser.contentTypes(accept: ["text/csv"]) == [.commaSeparatedText])
        #expect(FileChooser.contentTypes(accept: []).isEmpty)
        #expect(FileChooser.contentTypes(accept: ["application/x-room-unknown-type-*"]).isEmpty)
    }
}
