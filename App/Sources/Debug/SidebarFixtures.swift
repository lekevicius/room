#if DEBUG
import Foundation
import Model
import Store

/// `Room -RoomSidebarFixture demo|500` (Debug builds): fills a throwaway
/// state directory with sidebar entries, for checking the sidebar by hand
/// and for screenshots. `demo`: essentials, pinned with nested folders,
/// Today tabs. `500`: 500 entries (scroll check, ROADMAP 2.2 exit).
enum SidebarFixtures {
    static var requested: String? { UserDefaults.standard.string(forKey: "RoomSidebarFixture") }

    static func populate(_ store: RoomStore, _ name: String, window: UUID) {
        let sidebar = store.sidebar
        guard let space = sidebar.spaces.first, sidebar.entries.isEmpty else { return }
        var selected: UUID?
        do {
            switch name {
            case "500":
                var folder: UUID?
                for index in 0..<100 {
                    if index % 20 == 0 {
                        folder = try sidebar.addFolder(name: "Folder \(index / 20 + 1)", space: space.id).id
                    }
                    try sidebar.addEntry(.pinned, url: "https://site\(index).example.com", title: "Pinned \(index)",
                                         space: space.id, folder: index % 2 == 0 ? folder : nil)
                }
                for index in 0..<400 {
                    let entry = try sidebar.addEntry(.today, url: "https://tab\(index).example.org/article", title: "Today tab \(index)",
                                                     space: space.id)
                    if index == 200 { selected = entry.id }
                }
            default:
                for (url, title) in [("https://mail.google.com", "Mail"), ("https://calendar.google.com", "Calendar"),
                                     ("https://github.com", "GitHub"), ("https://figma.com", "Figma"), ("https://linear.app", "Linear")] {
                    try sidebar.addEntry(.essential, url: url, title: title, space: space.id)
                }
                try sidebar.addEntry(.pinned, url: "https://news.ycombinator.com", title: "Hacker News", space: space.id)
                let docs = try sidebar.addEntry(.pinned, url: "https://developer.apple.com/documentation/appkit", title: "AppKit Documentation",
                                                space: space.id)
                let reading = try sidebar.addFolder(name: "Reading", space: space.id)
                try sidebar.addEntry(.pinned, url: "https://www.economist.com", title: "The Economist", space: space.id, folder: reading.id)
                try sidebar.addEntry(.pinned, url: "https://lithub.com", title: "Literary Hub", space: space.id, folder: reading.id)
                let later = try sidebar.addFolder(name: "Later", space: space.id, parent: reading.id)
                try sidebar.addEntry(.pinned, url: "https://www.lrb.co.uk", title: "London Review of Books", space: space.id, folder: later.id)
                let archive = try sidebar.addFolder(name: "Archive", space: space.id)
                try sidebar.setFolderCollapsed(archive.id, true)
                try sidebar.addEntry(.pinned, url: "https://archive.org", title: "Internet Archive", space: space.id, folder: archive.id)
                for (url, title) in [("https://en.wikipedia.org/wiki/Room", "Room - Wikipedia"),
                                     ("https://www.swift.org/documentation/", "(3) Swift Documentation"),
                                     ("https://arc.net", "Arc from The Browser Company"),
                                     ("https://zen-browser.app", nil)] {
                    try sidebar.addEntry(.today, url: url, title: title, space: space.id)
                }
                selected = docs.id
            }
        } catch {
            NSLog("Room: sidebar fixture \(name) failed: \(error)")
        }
        if let selected {
            store.windows.select(selected, space: space.id, window: window)
            try? sidebar.markActive(selected)
        }
    }
}
#endif
