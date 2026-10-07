import AppKit
import Engine
import Model
import Observation
import Sidebar
import Store

/// Where the selected entry's page is shown: the window's card.
public protocol PageDisplay: AnyObject {
    /// Shows `contents` in the card; `nil` shows the empty state
    /// ("Press ⌘T…", spec §A.7). In a split it is the focused pane's page.
    func show(_ contents: (any WebContents)?)
    /// The split the card shows from now on (`nil`: one page), called before
    /// `show` with the focused pane's page (spec §D).
    func showSplit(_ split: SplitPresentation?)
}

public extension PageDisplay {
    func showSplit(_ split: SplitPresentation?) {}
}

/// One pane of a split on screen.
public struct SplitPane: Equatable {
    public var entry: UUID
    /// `nil` while the pane has no page (a new split's empty pane, an entry waiting for its profile).
    public var contents: (any WebContents)?

    public static func == (lhs: SplitPane, rhs: SplitPane) -> Bool { lhs.entry == rhs.entry && lhs.contents === rhs.contents }
}

/// A split as the card shows it (spec §D): its panes in order, their sizes, the focused one.
public struct SplitPresentation: Equatable {
    public var group: UUID
    public var layout: SplitLayout
    public var ratios: [Double]
    public var panes: [SplitPane]
    public var focused: UUID
}

/// One loaded entry's page.
final class Page {
    let contents: any WebContents
    /// The model profile whose engine profile (cookie jar) made the page.
    let profileID: UUID
    /// Bumped when the page leaves an entry, so stale observations stop.
    var generation = 0
    /// When the page was last on screen (the idle clock of spec §H).
    var lastVisible: Date
    /// The page's last real favicon (FakeEngine's template globe excluded).
    var favicon: NSImage?
    /// The favicon last written to the cache, so each icon is stored once.
    weak var storedFavicon: NSImage?
    /// While the certificate interstitial shows, the row reads the host, not
    /// Chromium's title for the blocked navigation (2.6a carry-over).
    var interstitialHost: String?
    /// The link under the pointer or keyboard focus (the status text): Peek's
    /// rule tells a click on it from a navigation the page's script started.
    var hoveredLink: URL?
    /// The media session last logged.
    var loggedMediaSession: MediaSessionInfo?
    /// The media row's view of the page at its last pass (4.6): playing,
    /// with a session, and the media clock when it last started.
    var mediaWasPlaying = false
    var mediaHadSession = false
    var mediaStartedAt = 0

    init(contents: any WebContents, profileID: UUID, lastVisible: Date) {
        self.contents = contents
        self.profileID = profileID
        self.lastVisible = lastVisible
    }
}

/// One window's pages (Phase 2.3): a `WebContents` per loaded entry, created
/// on first selection; background pages stay alive as hidden views until
/// unloaded or discarded; the selected one is in the card. It is the
/// sidebar's `SidebarHost`, writes what the pages report (URL, title,
/// favicon) into the store, and is every page's UI and navigation delegate,
/// handing presentation it does not own (dialogs, menus, keys) to
/// `pageUIDelegate` until Phase 2.6.
///
/// Engine-agnostic: RoomCore in the app, FakeEngine in tests.
@Observable
public final class TabController: SidebarHost {
    @ObservationIgnored public let store: RoomStore
    @ObservationIgnored public weak var display: (any PageDisplay)?
    /// The window the pages are shown in: every page is created for it
    /// (`WebContentsConfiguration.hostWindow`; RoomCore binds the page to
    /// that window's Chrome `Browser`).
    @ObservationIgnored public weak var window: NSWindow?
    @ObservationIgnored public weak var sidebar: SidebarController?
    /// The window's id in the store (its Today tabs carry it, schema v9).
    public var windowID: UUID? { sidebar?.windowID }
    /// The other windows (4.8a): a page lives in one window and moves when
    /// its entry is selected elsewhere (`PageOwnership`).
    @ObservationIgnored public weak var ownership: (any PageOwnershipCoordinator)?
    /// Dialogs, permission prompts, context menus, file choosers, keys.
    @ObservationIgnored public weak var pageUIDelegate: (any WebContentsUIDelegate)?
    /// ⌘T and "New Tab" (the palette, Phase 2.4).
    @ObservationIgnored public var onNewTab: (() -> Void)?
    /// ⌘L (`docked` false) and a click on the header's address field
    /// (`docked` true: the palette edits in place, spec §C).
    @ObservationIgnored public var onEditAddress: ((_ docked: Bool) -> Void)?
    /// A tab opened behind the current one (⌥Enter, Open Link in New Tab, a
    /// background `target=_blank`): a toast says so while the sidebar is hidden (spec §E).
    @ObservationIgnored public var onBackgroundTabOpened: ((UUID) -> Void)?
    /// Routing between spaces (spec §B, 4.2): for a link a page in a space
    /// opens as a new tab (⌘-click, a popup, `target=_blank`, Open Link in New
    /// Tab), the space it belongs in (the app evaluates the rules and the
    /// "Route links between spaces" setting; the source space or `nil` keeps
    /// it). Peek and in-place navigations never ask.
    @ObservationIgnored public var routeLink: ((_ url: String, _ sourceSpace: UUID) -> UUID?)?
    /// A page opened a document picture-in-picture window (4.6, B-51): the
    /// new page, its opener's page and the opener's entry. The app floats it
    /// in a panel; without a handler it is a Today tab under the opener.
    @ObservationIgnored public var presentPictureInPicture: ((_ contents: any WebContents, _ opener: any WebContents, _ entry: UUID) -> Void)?
    /// A page opened off the record ("Open Link in Incognito Window", 4.8b):
    /// the new page (of the opener's profile's twin), its URL and the
    /// opener's model profile. The app moves it into its incognito window;
    /// without a handler it is closed.
    @ObservationIgnored public var openOffTheRecord: ((_ contents: any WebContents, _ url: URL?, _ profileID: UUID?) -> Void)?
    /// A link went to another space than its page's (the app's toast).
    @ObservationIgnored public var onLinkRouted: ((_ entry: UUID, _ space: UUID) -> Void)?
    /// Pages that close while it terminates are dropped without closing their entries.
    @ObservationIgnored public weak var engine: (any EngineApplication)?
    /// The idle clock (tests inject one).
    @ObservationIgnored public var now: () -> Date = Date.init

    /// The engine profile (cookie jar) of each model profile, by
    /// `Model.Profile.id`: an entry's page is made in its profile's (ROADMAP
    /// 2.5 task 4). The engine creates them asynchronously; until an entry's
    /// exists, its page waits and loads once `setEngineProfile` delivers it.
    @ObservationIgnored public private(set) var engineProfiles: [UUID: any Engine.Profile] = [:]
    /// Asked once per model profile whose engine profile a page needs and
    /// that has none yet; the app creates it and calls `setEngineProfile`.
    @ObservationIgnored public var requestEngineProfile: ((Model.Profile) -> Void)?
    /// Spikes only: every page the controller takes on, after it became the
    /// page's delegates (the 2.6b spike wraps them to record each callback).
    @ObservationIgnored public var debugDidAdopt: ((any WebContents) -> Void)?
    @ObservationIgnored private var requestedProfiles: Set<UUID> = []
    /// Background loads waiting for their entry's engine profile.
    @ObservationIgnored private var waitingLoads: [UUID] = []
    @ObservationIgnored private var storeToken: ObservationToken?

    /// Crash recovery (spec §H, 4.1b): after a crash every entry is restored
    /// unloaded, the selected one included. While set, the launch's own loads
    /// (`showSelection`, an engine profile arriving for the selection) leave
    /// the card on its empty state; the first activation once the entry's
    /// engine profile exists (a click on the row, a space switch) clears it.
    @ObservationIgnored public var holdsSelectionUnloaded = false

    /// Delivers a model profile's engine profile; the selection and background
    /// loads waiting for it load now.
    public func setEngineProfile(_ engineProfile: any Engine.Profile, for profileID: UUID) {
        engineProfiles[profileID] = engineProfile
        if !holdsSelectionUnloaded, let id = currentEntryID, pages[id] == nil, let entry = store.sidebar.entry(id),
           entry.profileID == profileID { activate(entry) }
        let waiting = waitingLoads
        waitingLoads = []
        for id in waiting {
            guard pages[id] == nil, let entry = store.sidebar.entry(id) else { continue }
            if entry.profileID == profileID {
                loadInBackground(entry)
                sidebar?.pageStateDidChange([id])
            } else {
                waitingLoads.append(id)
            }
        }
    }

    /// The first (default) profile's engine profile.
    public var profile: (any Engine.Profile)? {
        get { store.sidebar.profiles.first.flatMap { engineProfiles[$0.id] } }
        set {
            guard let newValue, let first = store.sidebar.profiles.first else { return }
            setEngineProfile(newValue, for: first.id)
        }
    }

    func requestEngineProfile(for id: UUID) { requestProfile(id) }

    private func requestProfile(_ id: UUID) {
        guard engineProfiles[id] == nil, requestedProfiles.insert(id).inserted,
              let profile = store.sidebar.profiles.first(where: { $0.id == id }) else { return }
        requestEngineProfile?(profile)
    }

    /// The engine profile name of a model profile: its id (4.4b, B-22), so a
    /// rename changes only the label; the engine keeps it at
    /// `<root>/Room Profile <id>`.
    public static func engineProfileName(for profile: Model.Profile) -> String {
        profile.id.uuidString
    }

    /// The name the engine profile had until 4.4b: the profile's name, with
    /// the characters a directory name cannot hold replaced (Phase 1.4);
    /// `EngineProfileDirectories` moves those directories once.
    public static func legacyEngineProfileName(for profile: Model.Profile) -> String {
        var name = String(profile.name.map { "/:\\".contains($0) ? "-" : $0 }).trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? profile.id.uuidString : String(name.prefix(64))
    }

    /// Forgets a model profile's engine profile (the profile is being
    /// deleted, 4.4b) and returns it; pages already closed.
    @discardableResult
    public func removeEngineProfile(for profileID: UUID) -> (any Engine.Profile)? {
        requestedProfiles.remove(profileID)
        waitingLoads.removeAll { id in store.sidebar.entry(id).map { $0.profileID == profileID } ?? true }
        return engineProfiles.removeValue(forKey: profileID)
    }

    /// The page in the card.
    public private(set) var current: (any WebContents)?
    /// The page that has the keyboard and the page commands (reload, find,
    /// zoom, back/forward): the Peek over the card if one shows, else the card's page.
    public var focusedPage: (any WebContents)? { peekContents ?? current }
    /// The selected entry's Peek on screen (observable through `focusedPage` and `shownPeek`).
    var peekContents: (any WebContents)?
    /// The entry whose page the card shows (or would, while it loads); in a split, the focused pane's.
    public private(set) var currentEntryID: UUID?
    /// The split on screen, if the selected entry is a pane of one (spec §D).
    @ObservationIgnored public private(set) var shownSplit: SplitPresentation?

    @ObservationIgnored var pages: [UUID: Page] = [:] {
        didSet { setNeedsMediaRowUpdate() }
    }
    /// The footer's media row (4.6, `MediaRows.swift`): what it shows, the
    /// clock that orders sessions, the × (hidden until a later start).
    @ObservationIgnored public internal(set) var mediaRow: MediaRowContent?
    @ObservationIgnored var mediaClock = 0
    @ObservationIgnored var mediaDismissedAt: Int?
    @ObservationIgnored var mediaRowUpdatePending = false
    @ObservationIgnored var mediaArtwork: (data: Data, image: NSImage)?
    /// Peek pages by the entry they opened over (spec §I.6).
    @ObservationIgnored var peeks: [UUID: Page] = [:]
    /// Reader pages by the entry whose page they read (4.7b, `TabController+Reader.swift`).
    @ObservationIgnored var readers: [UUID: ReaderPage] = [:]
    /// Reader mode ended for an entry (the app deletes the reader file and its history row).
    @ObservationIgnored public var onReaderEnded: ReaderEnded?
    /// The card's entry entered (`true`) or left reader mode: the app puts the keyboard in the page now shown.
    @ObservationIgnored public var onReaderToggled: ((_ entry: UUID, _ isReader: Bool) -> Void)?
    /// Peek pages Room closed, until the engine reports them gone.
    @ObservationIgnored var closingPeeks: Set<ObjectIdentifier> = []
    /// Where Peek shows (the app's overlay card).
    @ObservationIgnored public weak var peekDisplay: (any PeekDisplay)?
    /// Settings ▸ "Open links to other sites from pinned tabs in Peek" (spec §A.4).
    @ObservationIgnored public var isPeekEnabled: () -> Bool = { true }
    /// When the last mouse or key press in the window happened (`uptime`'s
    /// clock; the app's event monitor sets it): Peek's 2 s gesture window.
    @ObservationIgnored public var lastUserInput: TimeInterval?
    @ObservationIgnored public var uptime: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// Spikes only: every Peek decision on an entry's navigation.
    @ObservationIgnored public var debugPeekDecisions: ((NavigationAction, PeekDecision) -> Void)?
    /// Pages being closed by `unload`, until the engine reports them gone.
    @ObservationIgnored var closing: [ObjectIdentifier: (contents: any WebContents, entry: UUID)] = [:]
    /// ⌘W's question to a closing page (`closePage`): closed, or kept by its
    /// beforeunload "stay".
    @ObservationIgnored var pageClosers: [ObjectIdentifier: (Bool) -> Void] = [:]
    /// The last tab a page opened, while the user has not switched tabs (§A.7).
    @ObservationIgnored var relatedChain: (opener: UUID, last: UUID)?
    /// How the next page made for an entry starts (the palette's typed URL,
    /// search or keyword), consumed by `makePage`; history weighs it.
    @ObservationIgnored var pendingTransitions: [UUID: PageTransition] = [:]
    @ObservationIgnored private var faviconImages: [Int64: NSImage] = [:]
    @ObservationIgnored var sweepTimer: Timer?
    @ObservationIgnored var memoryPressureSource: (any DispatchSourceMemoryPressure)?
    /// Takes the next page while the pressure stays critical.
    @ObservationIgnored var pressureTimer: Timer?
    @ObservationIgnored var lifecycleStarted = false
    /// The last memory-pressure level reported (engine or system).
    @ObservationIgnored public internal(set) var memoryPressure = MemoryPressureLevel.none
    /// Spikes only: `false` leaves memory pressure to the engine alone (the
    /// check that RoomCore never discards a Room page by itself).
    @ObservationIgnored public var respondsToMemoryPressure = true
    /// Pages the last idle sweep left alone because the engine keeps them, with why.
    @ObservationIgnored public internal(set) var keptByEngine: [UUID: DiscardBlockers] = [:]
    /// Spikes only: every discard the policy made, with its reason.
    @ObservationIgnored public var debugDidDiscard: ((UUID, String) -> Void)?

    public init(store: RoomStore) {
        self.store = store
        storeToken = store.sidebar.observe { [weak self] change in self?.sidebarDidChange(change) }
    }

    /// An entry that moved to a space of another profile (a move, a drop, a
    /// space's profile changed) cannot keep its page: cookies belong to the
    /// engine profile that made it. Its page closes and the entry loads
    /// again at its URL in the new profile (spec §B), shown if it was.
    private func sidebarDidChange(_ change: SidebarChange) {
        defer { refreshSplitIfChanged() }
        // An entry another window removed (a pinned entry, a space) takes its page here with it (4.8a).
        for id in change.removedEntries where pages[id] != nil && store.sidebar.entry(id) == nil { unload(id) }
        for id in change.entries {
            guard let page = pages[id], let entry = store.sidebar.entry(id),
                  ProfileRules.needsNewPage(pageProfile: page.profileID, entry: entry) else { continue }
            let shown = currentEntryID == id
            unload(id)
            if shown {
                activate(entry)
            } else {
                loadInBackground(entry)
            }
            sidebar?.pageStateDidChange([id])
        }
    }

    isolated deinit {
        sweepTimer?.invalidate()
        pressureTimer?.invalidate()
        memoryPressureSource?.cancel()
    }

    // MARK: Queries

    /// The page of `entry`, if it has one (alive or discarded).
    public func contents(for entry: UUID) -> (any WebContents)? { pages[entry]?.contents }

    /// The engine profile (cookie jar, permissions) a page lives in: the site
    /// panel acts on it (ROADMAP 2.6).
    public func engineProfile(for contents: any WebContents) -> (any Engine.Profile)? {
        guard let page = page(for: contents) else { return nil }
        return engineProfiles[page.profileID]
    }

    /// An entry's page or a Peek page.
    func page(for contents: any WebContents) -> Page? {
        if let id = entryID(for: contents) { return pages[id] }
        return peekOpener(of: contents).flatMap { peeks[$0] }
    }

    /// Entries with a page, alive or discarded.
    public var loadedEntryIDs: [UUID] { Array(pages.keys) }

    /// The entry whose page `contents` is.
    public func entryID(for contents: any WebContents) -> UUID? {
        pages.first { $0.value.contents === contents }?.key
    }

    /// Launch and window restore: shows the window's selected entry (the
    /// only page that loads, spec §H; it waits for `profile`), or the empty state.
    public func showSelection() {
        guard let id = sidebar?.selectedEntryID, let entry = store.sidebar.entry(id) else { return deactivate() }
        guard !holdsSelectionUnloaded else {
            // Crash recovery: selected, not loaded (spec §H).
            currentEntryID = entry.id
            show(nil)
            return
        }
        activate(entry)
    }

    // MARK: SidebarHost

    /// A dictionary lookup per visible row (the sidebar calls it while drawing).
    public func pageState(for entry: UUID) -> EntryPageState {
        guard let page = pages[entry] else { return EntryPageState(favicon: storedFavicon(for: entry)) }
        let contents = page.contents
        let alive = contents.state == .alive
        let capture = alive ? contents.captureState : []
        let indicator: EntryPageState.Capture? = capture.isSharingScreen ? .screen
            : capture.contains(.camera) ? .camera : capture.contains(.microphone) ? .microphone : nil
        return EntryPageState(isLoaded: alive, isLoading: alive && contents.isLoading, isAudible: alive && contents.isAudible,
                              isMuted: contents.isMuted, favicon: page.favicon ?? storedFavicon(for: entry), capture: indicator,
                              isReader: readers[entry] != nil)
    }

    public func activate(_ entry: Entry) {
        if entry.id != currentEntryID {
            // Any tab switch ends the related-tab chain (Firefox).
            relatedChain = nil
            if let previous = currentEntryID { pages[previous]?.lastVisible = now() }
        }
        currentEntryID = entry.id
        if holdsSelectionUnloaded, engineProfiles[entry.profileID] != nil {
            // The first activation after a crash recovery's launch: from here on, as usual.
            holdsSelectionUnloaded = false
        }
        guard engineProfiles[entry.profileID] != nil || pages[entry.id] != nil else {
            // Its profile is still being created: the card waits, empty (it loads in `setEngineProfile`).
            requestProfile(entry.profileID)
            show(nil)
            return
        }
        let split = splitPresentation(focusing: entry)
        // A split's empty pane has no page until the palette gives it one (spec §D).
        guard let page = pages[entry.id] ?? (entry.currentURL == nil && split != nil ? nil : makePage(for: entry, hidden: false)) else {
            show(nil, split: split)
            return
        }
        page.lastVisible = now()
        // A discarded page comes back at its URL with its back/forward list (B-13).
        if page.contents.state == .discarded { page.contents.reload() }
        // In reader mode the card shows the reader page; the entry's page stays loaded behind it (4.7b).
        show(readers[entry.id]?.contents ?? page.contents, split: split)
        // Its Peek, if it had one, comes back with it.
        updatePeek(animated: false)
    }

    /// The split `entry` is a pane of, every pane with its page (made on
    /// first show, all visible: spec §D "every pane stays active").
    private func splitPresentation(focusing entry: Entry) -> SplitPresentation? {
        guard let group = store.sidebar.splitGroup(of: entry.id) else { return nil }
        var panes: [SplitPane] = []
        for member in store.sidebar.splitMembers(group.id) {
            var page = pages[member.id]
            if page == nil, member.id != entry.id, member.currentURL != nil, engineProfiles[member.profileID] != nil {
                page = makePage(for: member, hidden: false)
            } else if page == nil, member.id != entry.id, member.currentURL != nil {
                requestProfile(member.profileID)
            }
            if let page, member.id != entry.id {
                page.lastVisible = now()
                if page.contents.state == .discarded { page.contents.reload() }
            }
            // The focused pane's page is made by `activate` (after this).
            panes.append(SplitPane(entry: member.id, contents: member.id == entry.id ? nil : page?.contents))
        }
        return SplitPresentation(group: group.id, layout: group.layout,
                                 ratios: SplitRules.normalizedRatios(group.ratios, layout: group.layout, count: panes.count),
                                 panes: panes, focused: entry.id)
    }

    /// The selected entry's split changed (a pane joined or left, a new
    /// layout or sizes, it dissolved, it began): the card follows.
    private func refreshSplitIfChanged() {
        guard let id = currentEntryID, let entry = store.sidebar.entry(id) else { return }
        let group = store.sidebar.splitGroup(of: id)
        if let shown = shownSplit, let group {
            let members = shown.panes.map(\.entry)
            guard shown.group != group.id || members != group.members || shown.layout != group.layout
                || shown.ratios != SplitRules.normalizedRatios(group.ratios, layout: group.layout, count: group.members.count) else { return }
        } else if shownSplit == nil, group == nil {
            return
        }
        activate(entry)
    }

    /// Pages on screen: the split's panes, or the card's page (never discarded, spec §H).
    var visibleEntryIDs: Set<UUID> {
        if let shownSplit { return Set(shownSplit.panes.map(\.entry)) }
        return currentEntryID.map { [$0] } ?? []
    }

    public func deactivate() {
        if let previous = currentEntryID { pages[previous]?.lastVisible = now() }
        currentEntryID = nil
        relatedChain = nil
        show(nil, split: nil)
        updatePeek(animated: false)
    }

    /// Idempotent; the store is not touched (the sidebar resets or removes the entry).
    public func unload(_ entry: UUID) {
        // Its Peek closes first (spec §A.3), and its reader page (4.7b).
        closePeek(over: entry, recordForReopen: false, animated: true)
        closeReader(of: entry)
        guard let page = removePage(entry) else { return }
        guard page.contents.state != .closed else { return }
        // Its history as it is now (a change in this turn has not been
        // reported yet): an unloaded entry goes Back where it was (spec §A.3).
        saveNavigationState(of: page.contents, entry: entry)
        closing[ObjectIdentifier(page.contents)] = (page.contents, entry)
        page.contents.close()
    }

    /// ⌘W on a Today tab: the page closes (its beforeunload may keep it,
    /// then the entry stays and is selected again, spec §A.3).
    public func closePage(_ entry: UUID, completion: @escaping (Bool) -> Void) {
        guard let page = pages[entry], page.contents.state != .closed else {
            unload(entry)
            return completion(true)
        }
        pageClosers[ObjectIdentifier(page.contents)] = completion
        unload(entry)
    }

    public func reset(_ entry: Entry) {
        guard let page = pages[entry.id], let url = entry.storedURL.flatMap(URL.init(string:)) else { return }
        page.contents.load(url, transition: .bookmark, fromAddressBar: false)
    }

    public func separate(_ entry: UUID, into newEntry: Entry) {
        if let reader = readers.removeValue(forKey: entry) { readers[newEntry.id] = reader }
        guard let page = pages.removeValue(forKey: entry) else { return }
        page.generation += 1
        pages[newEntry.id] = page
        if currentEntryID == entry { currentEntryID = newEntry.id }
        observe(page, entry: newEntry.id)
        saveNavigationState(of: page.contents, entry: newEntry.id)
    }

    public func reload(_ entry: UUID) { pages[entry]?.contents.reload() }

    public func setMuted(_ muted: Bool, entry: UUID) { pages[entry]?.contents.isMuted = muted }

    public func newTab() { onNewTab?() }

    /// The header's address field was clicked.
    public func editAddress() { onEditAddress?(true) }

    /// ⌘L.
    public func openLocation() { onEditAddress?(false) }

    // MARK: Opening URLs (the palette, Phase 2.4)

    /// A new Today tab at the end of the active space's Today list, selected.
    /// `transition`: how the palette produced the URL (history weighs it).
    @discardableResult
    public func openNewTab(url: String, transition: PageTransition = .typed) -> UUID? {
        guard let sidebar, let entry = try? store.sidebar.addEntry(.today, url: url, space: sidebar.activeSpaceID, window: windowID) else { return nil }
        pendingTransitions[entry.id] = transition
        sidebar.select(entry.id)
        return entry.id
    }

    /// A new Today tab in `space` (a link from another app routed there,
    /// spec §B): in the shown space it is `openNewTab`; in another one it is
    /// added at the end of that space's Today list, loads behind the card and
    /// becomes that space's remembered selection, so the space shows it when
    /// it is switched to.
    @discardableResult
    public func openNewTab(url: String, inSpace space: UUID, transition: PageTransition = .typed) -> UUID? {
        guard let sidebar else { return nil }
        guard space != sidebar.activeSpaceID else { return openNewTab(url: url, transition: transition) }
        guard let entry = try? store.sidebar.addEntry(.today, url: url, space: space, window: windowID) else { return nil }
        pendingTransitions[entry.id] = transition
        sidebar.selectInBackground(entry.id, space: space)
        loadInBackground(store.sidebar.entry(entry.id) ?? entry)
        return entry.id
    }

    /// A page made elsewhere (4.8b: an off-the-record page moved into the
    /// incognito window) as a new Today tab at the top of the active space's
    /// list, selected; its window must be this controller's already.
    @discardableResult
    public func adoptNewTab(_ contents: any WebContents, url: URL?) -> UUID? {
        let target = (url ?? contents.url)?.absoluteString
        guard let sidebar,
              let entry = try? store.sidebar.addEntry(.today, url: target, title: contents.title, space: sidebar.activeSpaceID, window: windowID, at: 0) else {
            return nil
        }
        adopt(contents, entry: entry.id)
        sidebar.select(entry.id)
        return entry.id
    }

    /// A new Today tab at the end of the active space's Today list, loading
    /// behind the current one (the palette's ⌥Enter, spec §C).
    @discardableResult
    public func openBackgroundTab(url: String, transition: PageTransition = .typed) -> UUID? {
        guard let sidebar, let entry = try? store.sidebar.addEntry(.today, url: url, space: sidebar.activeSpaceID, window: windowID) else { return nil }
        pendingTransitions[entry.id] = transition
        loadInBackground(entry)
        sidebar.pageStateDidChange([entry.id])
        onBackgroundTabOpened?(entry.id)
        return entry.id
    }

    /// A link opened from Room's own UI for a page (its context menu's Open
    /// Link in New Tab): a Today tab under the opener, loading behind it as a
    /// ⌘-click would (spec §A.7). Without a known opener it goes to the end.
    @discardableResult
    public func openLink(_ url: URL, from contents: any WebContents) -> UUID? {
        guard let sidebar, let openerID = entryID(for: contents), let opener = store.sidebar.entry(openerID) else {
            return openBackgroundTab(url: url.absoluteString, transition: .link)
        }
        let space = opener.spaceID ?? sidebar.activeSpaceID
        if let routed = routedSpace(for: url.absoluteString, from: space) {
            return openRouted(url: url.absoluteString, contents: nil, profileID: opener.profileID, in: routed)
        }
        let lastRelated = relatedChain?.opener == openerID ? relatedChain?.last : nil
        let index = NavigationRules.relatedTabIndex(opener: opener, lastRelated: lastRelated, today: store.sidebar.today(space: space, window: windowID))
        guard let entry = try? store.sidebar.addEntry(.today, url: url.absoluteString, space: space, window: windowID, at: index) else { return nil }
        pendingTransitions[entry.id] = .link
        loadInBackground(entry)
        sidebar.pageStateDidChange([entry.id])
        relatedChain = (openerID, entry.id)
        onBackgroundTabOpened?(entry.id)
        return entry.id
    }

    /// Navigates the selected entry's page to `url` (typed), loading the entry if it has no page.
    public func navigateSelected(to url: String, transition: PageTransition = .typed) {
        guard let id = currentEntryID, let target = URL(string: url) else {
            openNewTab(url: url, transition: transition)
            return
        }
        if let page = pages[id] {
            page.contents.load(target, transition: transition, fromAddressBar: true)
        } else if let entry = store.sidebar.entry(id) {
            try? store.sidebar.setLivePage(id, url: url, title: nil)
            pendingTransitions[id] = transition
            activate(store.sidebar.entry(id) ?? entry)
        }
    }

    /// Loads `entry`'s page without showing it (fixtures, spikes, background links).
    @discardableResult
    public func loadInBackground(_ entry: Entry) -> (any WebContents)? {
        if let page = pages[entry.id] { return page.contents }
        if engineProfiles[entry.profileID] == nil {
            requestProfile(entry.profileID)
            if !waitingLoads.contains(entry.id) { waitingLoads.append(entry.id) }
            return nil
        }
        return makePage(for: entry, hidden: true)?.contents
    }

    /// Takes `entry`'s page out of this window's pages and card (its
    /// observations stop); the page itself is not touched.
    private func removePage(_ entry: UUID) -> Page? {
        guard let page = pages.removeValue(forKey: entry) else { return nil }
        page.generation += 1
        if currentEntryID == entry {
            show(nil, split: shownSplit)
        } else if let split = shownSplit, let index = split.panes.firstIndex(where: { $0.entry == entry }) {
            // A pane's page went (the pane stays, empty, until the split changes).
            var panes = split.panes
            panes[index].contents = nil
            shownSplit?.panes = panes
            display?.showSplit(shownSplit)
        }
        return page
    }

    /// Another window takes `entry`'s page (4.8b): it leaves this window as
    /// it is, renderer, history and state, for the claiming window to move
    /// into its own (`WebContents.move(toHostWindow:)`). Its Peek closes and
    /// reader mode for it ends (the reader page closes rather than moving
    /// with it: one page to move, and the entry's page is the one the
    /// history belongs to). When it was on screen the selection falls to
    /// this window's most recent other entry, or the empty state, on the
    /// next turn. Returns the page, or nil when this window held none.
    func handOverPage(_ entry: UUID) -> (any WebContents)? {
        guard pages[entry] != nil else { return nil }
        let wasShown = visibleEntryIDs.contains(entry)
        closePeek(over: entry, recordForReopen: false, animated: false)
        closeReader(of: entry)
        guard let page = removePage(entry), page.contents.state != .closed else { return nil }
        // The entry keeps the history as it is now (the claimer reads it if the move fails).
        saveNavigationState(of: page.contents, entry: entry)
        sidebar?.pageStateDidChange([entry])
        if wasShown { fallBack(losing: entry) }
        return page.contents
    }

    /// The selection leaves `entry` (its page went to another window) for
    /// this window's most recent other entry not on screen elsewhere, on the
    /// next turn: the claiming window finishes taking its page first.
    func fallBack(losing entry: UUID) {
        guard let sidebar, sidebar.selectedEntryID == entry || currentEntryID == entry else { return }
        let elsewhere = ownership?.entriesVisible(besides: self) ?? []
        let next = PageOwnership.fallback(mru: store.sidebar.mruOrder(space: sidebar.activeSpaceID, window: windowID),
                                          losing: entry, visibleElsewhere: elsewhere.union([entry]))
        DispatchQueue.main.async { [weak self, weak sidebar] in
            guard let self, let sidebar, sidebar.selectedEntryID == entry || self.currentEntryID == entry else { return }
            sidebar.select(next)
        }
    }

    // MARK: Pages

    private func show(_ contents: (any WebContents)?, split: SplitPresentation? = nil) {
        let switching = contents !== current
        var split = split
        if let index = split?.panes.firstIndex(where: { $0.entry == split?.focused }) { split?.panes[index].contents = contents }
        // Panes that leave the card are seen for the last time now (the idle clock, spec §H).
        for id in visibleEntryIDs where !(split?.panes.contains { $0.entry == id } ?? (id == currentEntryID)) { pages[id]?.lastVisible = now() }
        shownSplit = split
        current = contents
        display?.showSplit(split)
        display?.show(contents)
        // The row never shows the page on screen.
        setNeedsMediaRowUpdate()
        // After the card took its page: a Peek page becoming the card's (Open as Tab) never leaves the
        // window on the way, and Chromium keeps a page's fullscreen only while its view stays (B-35).
        if switching { updatePeekBeforeSwitch() }
    }

    /// Another page goes into the card: the old entry's Peek leaves with it.
    private func updatePeekBeforeSwitch() {
        guard peekContents != nil else { return }
        peekContents = nil
        peekDisplay?.showPeek(nil, animated: false)
    }

    private func makePage(for entry: Entry, hidden: Bool) -> Page? {
        guard let profile = engineProfiles[entry.profileID] else {
            requestProfile(entry.profileID)
            return nil
        }
        // A page lives in one window (4.8a): a window holding this entry's
        // page hands it over, and the engine moves it into this window with
        // its renderer and back/forward list (4.8b). Without a window to move
        // it to (tests), or when the move fails, the page closes with its
        // history saved into the entry and a new one is made from it below
        // (4.8a's path).
        if let handed = ownership?.tabController(self, willMakePageFor: entry.id) {
            if let window {
                do {
                    try handed.move(toHostWindow: window)
                    return adopt(handed, entry: entry.id)
                } catch {
                    NSLog("Room: the page of entry \(entry.id) did not move (\(error)); it loads again from its history")
                }
            }
            handed.close()
        }
        let entry = store.sidebar.entry(entry.id) ?? entry
        let contents: any WebContents
        do {
            // The entry's saved back/forward list (3.7b): a relaunch, a crash
            // recovery, ⌘W's unload and ⇧⌘T bring the page back with it.
            contents = try profile.createWebContents(WebContentsConfiguration(initiallyHidden: hidden, hostWindow: window,
                                                                              restoredNavigationState: entry.navigationState))
        } catch {
            NSLog("Room: no page for entry \(entry.id): \(error)")
            return nil
        }
        let page = adopt(contents, entry: entry.id)
        // An unloaded pinned entry opens like a bookmark; any other page
        // coming back (restored, unloaded) is a reload, not a new visit.
        let restored: PageTransition = entry.kind.isPermanent && entry.liveURL == nil ? .bookmark : .reload
        let transition = pendingTransitions.removeValue(forKey: entry.id) ?? restored
        if let url = entry.currentURL.flatMap(URL.init(string:)) {
            switch NavigationRestore.firstLoad(entryURL: url, restoredURL: contents.url, hadState: entry.navigationState != nil) {
            case .loadRestored:
                // The restored current entry is the entry's page: load it with its history behind it.
                contents.reload()
            case .navigate(let unreadable):
                // A new page, a page reset to its stored URL (the old history
                // stays behind it), or a state this engine could not read.
                if unreadable { NSLog("Room: the saved history of \(url.host() ?? "an entry") was not restored; loading its URL") }
                contents.load(url, transition: transition, fromAddressBar: false)
            }
        }
        return page
    }

    /// Writes the page's current back/forward list into its entry (the store
    /// persists it with the next debounced write). Engines without one
    /// leave the entry's as it was.
    func saveNavigationState(of contents: any WebContents, entry: UUID) {
        guard let state = contents.navigationState else { return }
        try? store.sidebar.setNavigationState(entry, state)
    }

    /// The owner of a page whose entry and store have no profile at all (never
    /// in practice: the store seeds one).
    static let noProfile = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// Makes `contents` the page of `entry`.
    @discardableResult
    func adopt(_ contents: any WebContents, entry: UUID) -> Page {
        contents.uiDelegate = self
        contents.navigationDelegate = self
        let profileID = store.sidebar.entry(entry)?.profileID ?? store.sidebar.profiles.first?.id ?? Self.noProfile
        let page = Page(contents: contents, profileID: profileID, lastVisible: now())
        pages[entry] = page
        observe(page, entry: entry)
        debugDidAdopt?(contents)
        return page
    }

    /// A page `opener` opened (link with a new-tab disposition, `window.open`):
    /// a new Today tab placed per §A.7, selected unless it opened in the background.
    func adoptOpenedPage(_ contents: any WebContents, url: URL?, openedBy openerID: UUID, select: Bool, routable: Bool = true) {
        let target = (url ?? contents.url)?.absoluteString
        if routable, let target, let opener = store.sidebar.entry(openerID), let sidebar,
           let routed = routedSpace(for: target, from: opener.spaceID ?? sidebar.activeSpaceID) {
            openRouted(url: target, contents: contents, profileID: pages[openerID]?.profileID ?? opener.profileID, in: routed)
            return
        }
        guard let sidebar, let entry = insertRelatedToday(url: target, openedBy: openerID) else {
            contents.close()
            return
        }
        adopt(contents, entry: entry.id)
        if select {
            sidebar.select(entry.id)
        } else {
            sidebar.pageStateDidChange([entry.id])
            onBackgroundTabOpened?(entry.id)
        }
        relatedChain = (openerID, entry.id)
    }

    // MARK: Routing links between spaces (spec §B, 4.2)

    /// The space a rule sends a link from a page in `space` to, when it is
    /// another one (the app's `routeLink` decides: rules, the setting).
    private func routedSpace(for url: String, from space: UUID) -> UUID? {
        guard let routed = routeLink?(url, space), routed != space, store.sidebar.space(routed) != nil else { return nil }
        return routed
    }

    /// A link a page opened, moved to `space` by a rule: a Today tab at the
    /// end of that space's list, its remembered selection. The engine's new
    /// page is kept when the space uses the opener's profile; another
    /// profile's space gets the URL loaded in its own (the page cannot change
    /// cookie jars), and the engine's page is closed.
    @discardableResult
    private func openRouted(url: String, contents: (any WebContents)?, profileID: UUID, in space: UUID) -> UUID? {
        guard let sidebar, let target = store.sidebar.space(space),
              let entry = try? store.sidebar.addEntry(.today, url: url, space: space, window: windowID) else {
            contents?.close()
            return nil
        }
        pendingTransitions[entry.id] = .link
        if let contents, target.profileID == profileID {
            adopt(contents, entry: entry.id)
        } else {
            contents?.close()
            loadInBackground(store.sidebar.entry(entry.id) ?? entry)
        }
        sidebar.selectInBackground(entry.id, space: space)
        sidebar.pageStateDidChange([entry.id])
        onLinkRouted?(entry.id, space)
        return entry.id
    }

    // MARK: Page state into the store

    func observe(_ page: Page, entry: UUID) {
        page.generation += 1
        track(page, entry: entry, generation: page.generation)
    }

    /// Mirrors the page into the store (URL, title, favicon) and the sidebar
    /// row (loading, audible, muted) until it closes or moves to another entry.
    private func track(_ page: Page, entry: UUID, generation: Int) {
        guard pages[entry] === page, page.generation == generation else { return }
        let contents = page.contents
        let (url, title, favicon) = withObservationTracking {
            _ = (contents.isLoading, contents.isAudible, contents.isMuted, contents.state, contents.captureState)
            logMediaSession(page, contents.mediaSession, entry: entry)
            return (contents.url, contents.title, contents.favicon)
        } onChange: { [weak self, weak page] in
            // Fires before the new value is stored; read it on the next turn.
            Task { @MainActor in
                guard let self, let page else { return }
                self.track(page, entry: entry, generation: generation)
            }
        }
        noteMediaState(page)
        if let url, let stored = store.sidebar.entry(entry) {
            let live = url.absoluteString
            // Keep the old title while a new load of the same page has none yet (no flicker).
            let liveTitle = page.interstitialHost ?? title ?? (stored.liveURL == live ? stored.liveTitle : nil)
            if stored.liveURL != live || stored.liveTitle != liveTitle {
                try? store.sidebar.setLivePage(entry, url: live, title: liveTitle)
            }
        }
        if let favicon, !favicon.isTemplate {
            page.favicon = favicon
            if page.storedFavicon !== favicon, let host = url?.host() {
                page.storedFavicon = favicon
                cacheFavicon(favicon, host: host, entry: entry)
            }
        }
        sidebar?.pageStateDidChange([entry])
    }

    // MARK: Favicon cache (spec §I.2)

    private func cacheFavicon(_ image: NSImage, host: String, entry: UUID) {
        guard let png = Self.png(image), let id = store.favicons.save(png: png, host: host) else { return }
        faviconImages[id] = image
        if store.sidebar.entry(entry)?.faviconID != id { try? store.sidebar.setFavicon(entry, id) }
    }

    /// A site's cached icon by its page URL's host, with or without "www."
    /// (history rows in the palette).
    public func favicon(forURL url: String) -> NSImage? {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return nil }
        let other = host.hasPrefix("www.") ? String(host.dropFirst(4)) : "www." + host
        guard let id = store.favicons.id(forHost: host) ?? store.favicons.id(forHost: other) else { return nil }
        return image(forFavicon: id)
    }

    /// The cached icon of an entry without a live one (unloaded, restored, discarded).
    private func storedFavicon(for entry: UUID) -> NSImage? {
        guard let id = store.sidebar.entry(entry)?.faviconID else { return nil }
        return image(forFavicon: id)
    }

    private func image(forFavicon id: Int64) -> NSImage? {
        if let image = faviconImages[id] { return image }
        guard let png = store.favicons.png(id), let image = NSImage(data: png) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        faviconImages[id] = image
        return image
    }

    static func png(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
