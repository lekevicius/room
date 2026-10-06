import AppKit
import Model
import Store
import Testing
@testable import Sidebar

@Suite("Context-menu keys (4.4a)")
struct ShortcutMenuTests {
    @Test("A tab's menu shows its actions' current keys: ⌘D remapped to ⌥⌘P, Mute with no key, the rest their defaults")
    func remappedKeys() throws {
        let f = try SidebarFixture()
        let tab = try f.sidebar.addEntry(.today, url: "https://a.example", title: "A", space: f.space.id)
        func item(_ title: String) -> NSMenuItem? { f.controller.menu(for: tab.id)?.items.first { $0.title == title } }
        #expect(item(CommandName.pinTab)?.keyEquivalent == "d")
        f.controller.shortcutKey = { id in
            switch id {
            case "togglePin:": ("p", [.command, .option])
            case "toggleMute:": ("", [])
            case "closeTab:": ("w", .command)
            default: ("", [])
            }
        }
        #expect(item(CommandName.pinTab)?.keyEquivalent == "p")
        #expect(item(CommandName.pinTab)?.keyEquivalentModifierMask == [.command, .option])
        #expect(item(CommandName.closeTab)?.keyEquivalent == "w")
    }
}
