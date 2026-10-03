import AppKit
import Engine
import Model
import Observation
import Sidebar
import Store

/// Where the selected entry's page is shown: the window's card.
public protocol PageDisplay: AnyObject {
    /// Shows `contents` in the card; `nil` shows the empty state
    /// ("Press ⌘T…", spec §A.7).
    func show(_ contents: (any WebContents)?)
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
    /// The (URL, title) last given to history, so each title is written once.
    var historyTitle: (url: URL, title: String)?
    /// The favicon last written to the cache, so each icon is stored once.
    weak var storedFavicon: NSImage?
    /// While the certificate interstitial shows, the row reads the host, not
    /// Chromium's title for the blocked navigation (2.6a carry-over).
    var interstitialHost: String?

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
/// Engine-agnostic: CEF in the app, FakeEngine in tests.
@Observable
public final class TabController: SidebarHost {
    @ObservationIgnored public let store: RoomStore
    @ObservationIgnored public weak var display: (any PageDisplay)?
    @ObservationIgnored public weak var sidebar: SidebarController?
    /// Dialogs, permission prompts, context menus, file choosers, keys.
    @ObservationIgnored public weak var pageUIDelegate: (any WebContentsUIDelegate)?
    /// ⌘T and "New Tab" (the palette, Phase 2.4).
    @ObservationIgnored public var onNewTab: (() -> Void)?
    /// ⌘L (`docked` false) and a click on the header's address field
    /// (`docked` true: the palette edits in place, spec §C).
    @ObservationIgnored public var onEditAddress: ((_ docked: Bool) -> Void)?
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

    /// Delivers a model profile's engine profile; the selection and background
    /// loads waiting for it load now.
    public func setEngineProfile(_ engineProfile: any Engine.Profile, for profileID: UUID) {
        engineProfiles[profileID] = engineProfile
        if let id = currentEntryID, pages[id] == nil, let entry = store.sidebar.entry(id), entry.profileID == profileID { activate(entry) }
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

    private func requestProfile(_ id: UUID) {
        guard engineProfiles[id] == nil, requestedProfiles.insert(id).inserted,
              let profile = store.sidebar.profiles.first(where: { $0.id == id }) else { return }
        requestEngineProfile?(profile)
    }

    /// The engine profile name of a model profile: its name, with the
    /// characters a directory name cannot hold replaced (the engine keeps it
    /// at `<root>/Room Profile <name>`, a direct child of its root, Phase 1.4).
    public static func engineProfileName(for profile: Model.Profile) -> String {
        var name = String(profile.name.map { "/:\\".contains($0) ? "-" : $0 }).trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? profile.id.uuidString : String(name.prefix(64))
    }

    /// The page in the card.
    public private(set) var current: (any WebContents)?
    /// The entry whose page the card shows (or would, while it loads).
    public private(set) var currentEntryID: UUID?

    @ObservationIgnored var pages: [UUID: Page] = [:]
    /// Pages being closed by `unload`, until the engine reports them gone.
    @ObservationIgnored var closing: [ObjectIdentifier: (contents: any WebContents, entry: UUID)] = [:]
    /// The last tab a page opened, while the user has not switched tabs (§A.7).
    @ObservationIgnored var relatedChain: (opener: UUID, last: UUID)?
    /// How the next page made for an entry starts (the palette's typed URL,
    /// search or keyword), consumed by `makePage`; history weighs it.
    @ObservationIgnored var pendingTransitions: [UUID: PageTransition] = [:]
    @ObservationIgnored private var faviconImages: [Int64: NSImage] = [:]
    @ObservationIgnored var sweepTimer: Timer?
    @ObservationIgnored var memoryPressureSource: (any DispatchSourceMemoryPressure)?

    public init(store: RoomStore) {
        self.store = store
        storeToken = store.sidebar.observe { [weak self] change in self?.sidebarDidChange(change) }
    }

    /// An entry that moved to a space of another profile (a move, a drop, a
    /// space's profile changed) cannot keep its page: cookies belong to the
    /// engine profile that made it. Its page closes and the entry loads
    /// again at its URL in the new profile (spec §B), shown if it was.
    private func sidebarDidChange(_ change: SidebarChange) {
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
        memoryPressureSource?.cancel()
    }

    // MARK: Queries

    /// The page of `entry`, if it has one (alive or discarded).
    public func contents(for entry: UUID) -> (any WebContents)? { pages[entry]?.contents }

    /// The engine profile (cookie jar, permissions) a page lives in: the site
    /// panel acts on it (ROADMAP 2.6).
    public func engineProfile(for contents: any WebContents) -> (any Engine.Profile)? {
        guard let id = entryID(for: contents), let page = pages[id] else { return nil }
        return engineProfiles[page.profileID]
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
        if let id = sidebar?.selectedEntryID, let entry = store.sidebar.entry(id) { activate(entry) } else { deactivate() }
    }

    // MARK: SidebarHost

    /// A dictionary lookup per visible row (the sidebar calls it while drawing).
    public func pageState(for entry: UUID) -> EntryPageState {
        guard let page = pages[entry] else { return EntryPageState(favicon: storedFavicon(for: entry)) }
        let contents = page.contents
        let alive = contents.state == .alive
        return EntryPageState(isLoaded: alive, isLoading: alive && contents.isLoading, isAudible: alive && contents.isAudible,
                              isMuted: contents.isMuted, favicon: page.favicon ?? storedFavicon(for: entry))
    }

    public func activate(_ entry: Entry) {
        if entry.id != currentEntryID {
            // Any tab switch ends the related-tab chain (Firefox).
            relatedChain = nil
            if let previous = currentEntryID { pages[previous]?.lastVisible = now() }
        }
        currentEntryID = entry.id
        guard engineProfiles[entry.profileID] != nil || pages[entry.id] != nil else {
            // Its profile is still being created: the card waits, empty (it loads in `setEngineProfile`).
            requestProfile(entry.profileID)
            show(nil)
            return
        }
        guard let page = pages[entry.id] ?? makePage(for: entry, hidden: false) else {
            show(nil)
            return
        }
        page.lastVisible = now()
        // A discarded page comes back at its URL (back/forward is lost on CEF, B-13).
        if page.contents.state == .discarded { page.contents.reload() }
        show(page.contents)
    }

    public func deactivate() {
        if let previous = currentEntryID { pages[previous]?.lastVisible = now() }
        currentEntryID = nil
        relatedChain = nil
        show(nil)
    }

    /// Idempotent; the store is not touched (the sidebar resets or removes the entry).
    public func unload(_ entry: UUID) {
        guard let page = pages.removeValue(forKey: entry) else { return }
        page.generation += 1
        if currentEntryID == entry { show(nil) }
        guard page.contents.state != .closed else { return }
        closing[ObjectIdentifier(page.contents)] = (page.contents, entry)
        page.contents.close()
    }

    public func reset(_ entry: Entry) {
        guard let page = pages[entry.id], let url = entry.storedURL.flatMap(URL.init(string:)) else { return }
        page.contents.load(url, transition: .bookmark, fromAddressBar: false)
    }

    public func separate(_ entry: UUID, into newEntry: Entry) {
        guard let page = pages.removeValue(forKey: entry) else { return }
        page.generation += 1
        pages[newEntry.id] = page
        if currentEntryID == entry { currentEntryID = newEntry.id }
        observe(page, entry: newEntry.id)
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
        guard let sidebar, let entry = try? store.sidebar.addEntry(.today, url: url, space: sidebar.activeSpaceID) else { return nil }
        pendingTransitions[entry.id] = transition
        sidebar.select(entry.id)
        return entry.id
    }

    /// A new Today tab at the end of the active space's Today list, loading
    /// behind the current one (the palette's ⌥Enter, spec §C).
    @discardableResult
    public func openBackgroundTab(url: String, transition: PageTransition = .typed) -> UUID? {
        guard let sidebar, let entry = try? store.sidebar.addEntry(.today, url: url, space: sidebar.activeSpaceID) else { return nil }
        pendingTransitions[entry.id] = transition
        loadInBackground(entry)
        sidebar.pageStateDidChange([entry.id])
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
        let lastRelated = relatedChain?.opener == openerID ? relatedChain?.last : nil
        let index = NavigationRules.relatedTabIndex(opener: opener, lastRelated: lastRelated, today: store.sidebar.today(space: space))
        guard let entry = try? store.sidebar.addEntry(.today, url: url.absoluteString, space: space, at: index) else { return nil }
        pendingTransitions[entry.id] = .link
        loadInBackground(entry)
        sidebar.pageStateDidChange([entry.id])
        relatedChain = (openerID, entry.id)
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

    // MARK: Pages

    private func show(_ contents: (any WebContents)?) {
        current = contents
        display?.show(contents)
    }

    private func makePage(for entry: Entry, hidden: Bool) -> Page? {
        guard let profile = engineProfiles[entry.profileID] else {
            requestProfile(entry.profileID)
            return nil
        }
        let contents: any WebContents
        do {
            contents = try profile.createWebContents(WebContentsConfiguration(initiallyHidden: hidden))
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
            contents.load(url, transition: transition, fromAddressBar: false)
        }
        return page
    }

    /// Makes `contents` the page of `entry`.
    @discardableResult
    func adopt(_ contents: any WebContents, entry: UUID) -> Page {
        contents.uiDelegate = self
        contents.navigationDelegate = self
        let profileID = store.sidebar.entry(entry)?.profileID ?? store.sidebar.profiles.first?.id ?? History.orphanProfile
        let page = Page(contents: contents, profileID: profileID, lastVisible: now())
        pages[entry] = page
        observe(page, entry: entry)
        debugDidAdopt?(contents)
        return page
    }

    /// A page `opener` opened (link with a new-tab disposition, `window.open`):
    /// a new Today tab placed per §A.7, selected unless it opened in the background.
    func adoptOpenedPage(_ contents: any WebContents, url: URL?, openedBy openerID: UUID, select: Bool) {
        guard let sidebar, let opener = store.sidebar.entry(openerID) else {
            contents.close()
            return
        }
        let space = opener.spaceID ?? sidebar.activeSpaceID
        let lastRelated = relatedChain?.opener == openerID ? relatedChain?.last : nil
        let index = NavigationRules.relatedTabIndex(opener: opener, lastRelated: lastRelated, today: store.sidebar.today(space: space))
        guard let entry = try? store.sidebar.addEntry(.today, url: (url ?? contents.url)?.absoluteString, space: space, at: index) else {
            contents.close()
            return
        }
        adopt(contents, entry: entry.id)
        if select {
            sidebar.select(entry.id)
        } else {
            sidebar.pageStateDidChange([entry.id])
        }
        relatedChain = (openerID, entry.id)
    }

    // MARK: Page state into the store

    private func observe(_ page: Page, entry: UUID) {
        page.generation += 1
        track(page, entry: entry, generation: page.generation)
    }

    /// Mirrors the page into the store (URL, title, favicon) and the sidebar
    /// row (loading, audible, muted) until it closes or moves to another entry.
    private func track(_ page: Page, entry: UUID, generation: Int) {
        guard pages[entry] === page, page.generation == generation else { return }
        let contents = page.contents
        let (url, title, favicon) = withObservationTracking {
            _ = (contents.isLoading, contents.isAudible, contents.isMuted, contents.state)
            return (contents.url, contents.title, contents.favicon)
        } onChange: { [weak self, weak page] in
            // Fires before the new value is stored; read it on the next turn.
            Task { @MainActor in
                guard let self, let page else { return }
                self.track(page, entry: entry, generation: generation)
            }
        }
        if let url, let stored = store.sidebar.entry(entry) {
            let live = url.absoluteString
            // Keep the old title while a new load of the same page has none yet (no flicker).
            let liveTitle = page.interstitialHost ?? title ?? (stored.liveURL == live ? stored.liveTitle : nil)
            if stored.liveURL != live || stored.liveTitle != liveTitle {
                try? store.sidebar.setLivePage(entry, url: live, title: liveTitle)
            }
            // The title arrives after the commit that recorded the visit; written
            // once loading ends, so a page's previous title never lands on its new URL.
            if !contents.isLoading, let title, !title.isEmpty, page.historyTitle?.url != url || page.historyTitle?.title != title {
                page.historyTitle = (url, title)
                store.history.setTitle(title, for: live, profile: page.profileID)
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

    /// Writes the page's title for its URL if it is not loading (after a commit's visit).
    func refreshHistoryTitle(_ page: Page) {
        let contents = page.contents
        guard !contents.isLoading, let url = contents.url, let title = contents.title, !title.isEmpty else { return }
        page.historyTitle = (url, title)
        store.history.setTitle(title, for: url.absoluteString, profile: page.profileID)
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
