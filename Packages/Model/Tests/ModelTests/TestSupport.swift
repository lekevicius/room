import Foundation
@testable import Model

/// A fresh directory under the temporary directory, removed by `cleanup()`.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "RoomModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: url) }
}

/// A small but complete state: one profile, two spaces, a folder, every kind.
func sampleState() -> RoomState {
    let profile = Profile(name: "Default", position: 0)
    let work = Space(name: "Work", themeColors: ["#FF8800"], profileID: profile.id, position: 0)
    let home = Space(name: "Home", icon: "house", profileID: profile.id, position: 1)
    let essential = Entry(kind: .essential, spaceID: nil, profileID: profile.id, storedURL: "https://mail.example.com/",
                          storedTitle: "Mail", createdAt: Timestamp(milliseconds: 1_000))
    let folder = Entry(kind: .folder, spaceID: work.id, profileID: profile.id, customLabel: "Docs",
                       createdAt: Timestamp(milliseconds: 2_000))
    let pinned = Entry(kind: .pinned, spaceID: work.id, profileID: profile.id, folderID: folder.id,
                       storedURL: "https://docs.example.com", storedTitle: "Docs", createdAt: Timestamp(milliseconds: 3_000),
                       lastActiveAt: Timestamp(milliseconds: 5_000), liveURL: "https://docs.example.com/page", liveTitle: "Page")
    let todayID = UUID()
    let group = SplitGroup(layout: .vbox, ratios: [0.25, 0.75], members: [todayID])
    let today = Entry(id: todayID, kind: .today, spaceID: home.id, profileID: profile.id, splitGroupID: group.id,
                      createdAt: Timestamp(milliseconds: 4_000), liveURL: "https://news.example.com", liveTitle: "News")
    var window = WindowState(sidebarWidth: 260, sidebarVisible: false, activeSpaceID: home.id)
    window.frame = CGRect(x: 10, y: 20, width: 1200, height: 800)
    var settings = Settings()
    settings.permanentCloseBehavior = .unloadSwitch
    // Settings v0 (2.8a), every field away from its default.
    settings.searchEngine = "kagi"
    settings.searchSuggestions = false
    settings.downloadDirectory = "/tmp/Room Downloads"
    settings.peekOffSiteLinks = false
    settings.sidebarSide = .right
    settings.appearance = .dark
    // 2.8b: the first run and the two opt-ins.
    settings.firstRunDone = true
    settings.crashReports = true
    settings.automaticUpdateChecks = true
    return RoomState(
        profiles: [profile], spaces: [work, home], entries: [essential, folder, pinned, today], splitGroups: [group],
        windows: [window], windowSpaces: [WindowSpace(windowID: window.id, spaceID: home.id, selectedEntryID: today.id)],
        settings: settings
    )
}
