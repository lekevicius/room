import Foundation
import GRDB
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
    var window = WindowState(sidebarWidth: 260, sidebarVisible: false, activeSpaceID: home.id)
    let today = Entry(id: todayID, kind: .today, spaceID: home.id, profileID: profile.id, splitGroupID: group.id,
                      createdAt: Timestamp(milliseconds: 4_000), liveURL: "https://news.example.com", liveTitle: "News",
                      navigationState: Data("opaque engine state".utf8), windowID: window.id)
    window.frame = CGRect(x: 10, y: 20, width: 1200, height: 800)
    var settings = Settings()
    settings.permanentCloseBehavior = .unloadSwitch
    // Settings v0 (2.8a), every field away from its default.
    settings.searchEngine = "kagi"
    settings.searchSuggestions = false
    settings.downloadDirectory = "/tmp/Room Downloads"
    settings.peekOffSiteLinks = false
    settings.appearance = .dark
    // 2.8b: the first run and the two opt-ins.
    settings.firstRunDone = true
    settings.crashReports = true
    settings.automaticUpdateChecks = true
    // 4.2: routing between spaces and the external default.
    settings.routeLinksBetweenSpaces = true
    settings.externalLinksSpaceID = home.id
    // 4.4a: a remapped key and a removed one.
    settings.shortcutOverrides = ["togglePin:": "⌥⌘P", "toggleMute:": ""]
    // 4.4a: the engines list, a profile's default, the downloads switches.
    settings.searchEngines = [SearchEngineSetting(id: "custom-1", name: "Example", keyword: "ex",
                                                  searchURL: "https://example.com/?q={searchTerms}", suggestURL: nil)]
    settings.searchEngineByProfile = [profile.id.uuidString: "custom-1"]
    settings.askWhereToSave = true
    settings.pdfsOpenInRoom = false
    // 4.7b: the reader page's text size.
    settings.readerTextSize = .large
    // 4.5: an extension allowed in the profile's incognito window (for 4.8b).
    settings.setAllowsInIncognito(true, "dibedkfpfkdkkcbjmblmfdbjdhdnlgkp", profile: profile.id)
    let rules = [
        RoutingRule(match: .contains, pattern: "github", targetSpaceID: work.id, position: 0),
        RoutingRule(match: .regex, pattern: #"^https://news\."#, targetSpaceID: home.id, position: 1, enabled: false),
    ]
    return RoomState(
        profiles: [profile], spaces: [work, home], entries: [essential, folder, pinned, today], splitGroups: [group],
        windows: [window], windowSpaces: [WindowSpace(windowID: window.id, spaceID: home.id, selectedEntryID: today.id)],
        settings: settings, routingRules: rules
    )
}

/// What a JSON snapshot keeps of `state` (B-73): the entries without their
/// navigation states, no Archive.
func snapshotted(_ state: RoomState) -> RoomState {
    var state = state.canonical()
    state.archive = []
    for index in state.entries.indices { state.entries[index].navigationState = nil }
    return state
}

/// Inserts `entry` into a database migrated to before v9 (no `windowID`).
func insertBeforeV9(_ entry: Entry, _ db: GRDB.Database) throws {
    try db.execute(sql: """
        INSERT INTO entry (id, kind, spaceID, profileID, folderID, splitGroupID, position, storedURL, storedTitle, customLabel,
                           customIcon, faviconID, isCollapsed, createdAt, lastActiveAt, liveURL, liveTitle, navigationState)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [entry.id, entry.kind, entry.spaceID, entry.profileID, entry.folderID, entry.splitGroupID, entry.position,
                         entry.storedURL, entry.storedTitle, entry.customLabel, entry.customIcon, entry.faviconID, entry.isCollapsed,
                         entry.createdAt, entry.lastActiveAt, entry.liveURL, entry.liveTitle, entry.navigationState])
}
