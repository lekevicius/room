#if DEBUG
import Foundation
import Model
import Store

/// `Room -RoomSidebarFixture demo|500` (Debug builds): fills a throwaway
/// state directory with sidebar entries, for checking the sidebar by hand
/// and for screenshots. `demo`: essentials, pinned with nested folders,
/// Today tabs. `500`: 500 entries (scroll check, ROADMAP 2.2 exit). `50`:
/// 50 entries whose first ten Today tabs are the Phase 1.4 typical sites
/// (switching and memory, ROADMAP 2.3 exit; `-RoomSpike switch` loads them).
/// `spaces`: the demo spread over four themed spaces, one of them in a
/// second profile "Work" (captures, by-hand checks). `spaces500`: the 500
/// entries split over five spaces, each with ten local colour pages first
/// in its Today list (`research/spikes/phase-2.5/page.html`; `-RoomSpike
/// spaces` loads them and times the switches, ROADMAP 2.5 exit).
enum SidebarFixtures {
    static var requested: String? { UserDefaults.standard.string(forKey: "RoomSidebarFixture") }

    static func populate(_ store: RoomStore, _ name: String, window: UUID) {
        let sidebar = store.sidebar
        guard let space = sidebar.spaces.first, sidebar.entries.isEmpty else { return }
        var selected: UUID?
        do {
            switch name {
            case "spaces":
                try populateSpaces(store, first: space, window: window)
                return
            case "spaces500":
                try populateSpaces500(store, first: space, window: window)
                return
            case "50":
                for index in 0..<4 {
                    try sidebar.addEntry(.essential, url: "https://essential\(index).example.com", title: "Essential \(index)", space: space.id)
                }
                let folder = try sidebar.addFolder(name: "Folder", space: space.id)
                for index in 0..<14 {
                    try sidebar.addEntry(.pinned, url: "https://pinned\(index).example.com", title: "Pinned \(index)", space: space.id,
                                         folder: index < 4 ? folder.id : nil)
                }
                for (index, url) in SpikeRunner.Context.typicalSites.enumerated() {
                    let entry = try sidebar.addEntry(.today, url: url, title: "Site \(index)", space: space.id)
                    if index == 0 { selected = entry.id }
                }
                for index in 0..<22 {
                    try sidebar.addEntry(.today, url: "https://tab\(index).example.org/article", title: "Today tab \(index)", space: space.id)
                }
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

extension SidebarFixtures {
    /// `research/spikes/phase-2.5/<name>` in the source tree this build came from.
    static func phase25Page(_ name: String) -> URL {
        SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-2.5/\(name)")
    }

    /// A local full-bleed colour page (`page.html?hue=…&n=…`).
    static func colourPage(hue: Int, label: String) -> String {
        var components = URLComponents(url: phase25Page("page.html"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "hue", value: "\(hue)"), URLQueryItem(name: "n", value: label)]
        return components.url!.absoluteString
    }

    /// Four spaces: "Space" (the demo, no theme), "Work" in profile Work
    /// (blue triadic, briefcase), "Reading" (green analogous, 📚), "Music"
    /// (one warm colour, 🎵). Each remembers its own selection.
    static func populateSpaces(_ store: RoomStore, first space: Space, window: UUID) throws {
        let sidebar = store.sidebar
        populate(store, "demo", window: window)
        let work = sidebar.createProfile(name: "Work")
        let spaces = [
            try sidebar.createSpace(name: "Work", profile: work.id, icon: "briefcase", themeColors: ["#3B6FD8"], themeAlgorithm: .triadic,
                                    themeOpacity: 0.6),
            try sidebar.createSpace(name: "Reading", profile: space.profileID, icon: "📚", themeColors: ["#3E9B5B"],
                                    themeAlgorithm: .analogous, themeOpacity: 0.5),
            try sidebar.createSpace(name: "Music", profile: space.profileID, icon: "🎵", themeColors: ["#E0663A"], themeAlgorithm: .floating,
                                    themeOpacity: 0.7),
        ]
        let content: [[(EntryKind, String, String)]] = [
            [(.essential, "https://linear.app", "Linear"), (.essential, "https://github.com", "GitHub"),
             (.pinned, "https://docs.google.com", "Docs"), (.pinned, "https://calendar.google.com", "Calendar"),
             (.today, "https://developer.apple.com/documentation/appkit/nswindow", "NSWindow | Apple Developer"),
             (.today, "https://github.com/apple/swift/pulls", "Pull requests · apple/swift")],
            [(.pinned, "https://www.economist.com", "The Economist"), (.pinned, "https://www.lrb.co.uk", "London Review of Books"),
             (.today, "https://en.wikipedia.org/wiki/Arc_(web_browser)", "Arc (web browser) - Wikipedia")],
            [(.pinned, "https://music.apple.com", "Apple Music"), (.today, "https://bandcamp.com", "Bandcamp")],
        ]
        for (target, entries) in zip(spaces, content) {
            var last: UUID?
            for (kind, url, title) in entries {
                last = try sidebar.addEntry(kind, url: url, title: title, space: target.id).id
            }
            if let last {
                store.windows.select(last, space: target.id, window: window)
                try? sidebar.markActive(last)
            }
        }
    }

    /// 500 entries over five spaces (100 each: 20 pinned, half in folders,
    /// then 80 Today tabs whose first ten are colour pages); each space
    /// selects its first page; the spaces alternate two profiles.
    static func populateSpaces500(_ store: RoomStore, first space: Space, window: UUID) throws {
        let sidebar = store.sidebar
        let work = sidebar.createProfile(name: "Work")
        try sidebar.updateSpace(space.id) { $0.name = "Space 1"; $0.themeColors = ["#5B8DEF"]; $0.themeAlgorithm = .analogous }
        var spaces = [space]
        let colours = ["#3E9B5B", "#E0663A", "#9B59B6", "#D4A72C"]
        for index in 1..<5 {
            spaces.append(try sidebar.createSpace(name: "Space \(index + 1)", profile: index % 2 == 1 ? work.id : space.profileID,
                                                  themeColors: [colours[index - 1]], themeAlgorithm: .analogous))
        }
        for (number, target) in spaces.enumerated() {
            var folder: UUID?
            for index in 0..<20 {
                if index % 10 == 0 { folder = try sidebar.addFolder(name: "Folder \(index / 10 + 1)", space: target.id).id }
                try sidebar.addEntry(.pinned, url: "https://s\(number)-site\(index).example.com", title: "Pinned \(number).\(index)",
                                     space: target.id, folder: index % 2 == 0 ? folder : nil)
            }
            for index in 0..<80 {
                let url = index < 10 ? colourPage(hue: (number * 72 + index * 7) % 360, label: "S\(number + 1) · \(index + 1)")
                    : "https://tab\(index).s\(number).example.org/article"
                let entry = try sidebar.addEntry(.today, url: url, title: index < 10 ? "Page \(number + 1).\(index + 1)" : "Today tab \(index)",
                                                 space: target.id)
                if index == 0 {
                    store.windows.select(entry.id, space: target.id, window: window)
                    try? sidebar.markActive(entry.id)
                }
            }
        }
    }
}
#endif
