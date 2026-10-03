import AppKit
import Engine
import Model

/// Where Peek's page is shown: an overlay card over the card (the app's).
public protocol PeekDisplay: AnyObject {
    /// Shows `contents` in Peek over the card, or closes it (`nil`).
    /// `animated`: it just opened (or closed), rather than coming back with
    /// its entry or leaving with it.
    func showPeek(_ contents: (any WebContents)?, animated: Bool)
}

/// Peek (spec §A.4, §I.6): off-site links from permanent entries and
/// ⇧-click open a page over the entry's page. A Peek belongs to the entry it
/// opened over (at most one each): it hides when another entry is selected
/// and comes back with its entry; it is a page of the opener's profile and
/// no sidebar entry until Open as Tab (⌘O) makes it a Today tab under the
/// opener. Closing it (Esc, ⌘W, a click outside) leaves it for ⇧⌘T.
extension TabController {
    /// The Peek over the selected entry's page, if it has one.
    public var shownPeek: (any WebContents)? { peekContents }

    /// Opens `url` in Peek over the page of the entry `contents` belongs to
    /// (a Peek's own page loads it instead). Context menu "Open Link in Peek".
    public func openPeek(_ url: URL, from contents: any WebContents) {
        if let opener = peekOpener(of: contents) {
            peeks[opener]?.contents.load(url, transition: .link, fromAddressBar: false)
            return
        }
        guard let id = entryID(for: contents) else { return }
        openPeek(url, over: id)
    }

    /// A new Peek of `url` over `entry`'s page; one it had closes first.
    func openPeek(_ url: URL, over entry: UUID) {
        guard let stored = store.sidebar.entry(entry) else { return }
        let profileID = pages[entry]?.profileID ?? stored.profileID
        guard let profile = engineProfiles[profileID] else { return requestEngineProfile(for: profileID) }
        closePeek(over: entry, recordForReopen: true, animated: false)
        let contents: any WebContents
        do {
            contents = try profile.createWebContents(WebContentsConfiguration(initiallyHidden: entry != currentEntryID))
        } catch {
            NSLog("Room: no Peek page: \(error)")
            return
        }
        contents.uiDelegate = self
        contents.navigationDelegate = self
        let page = Page(contents: contents, profileID: profileID, lastVisible: now())
        peeks[entry] = page
        debugDidAdopt?(contents)
        contents.load(url, transition: .link, fromAddressBar: false)
        if entry == currentEntryID { updatePeek(animated: true) }
    }

    /// Esc, ⌘W, a click outside, ×: closes the selected entry's Peek. Returns whether there was one.
    @discardableResult
    public func closeShownPeek() -> Bool {
        guard let id = currentEntryID, peeks[id] != nil else { return false }
        closePeek(over: id, recordForReopen: true, animated: true)
        return true
    }

    func closePeek(over entry: UUID, recordForReopen: Bool, animated: Bool) {
        guard let page = peeks.removeValue(forKey: entry) else { return }
        if entry == currentEntryID { updatePeek(animated: animated) }
        if recordForReopen, let url = page.contents.url ?? page.hoveredLink {
            sidebar?.recordClosedPeek(url: url.absoluteString, opener: entry)
        }
        guard page.contents.state != .closed else { return }
        closingPeeks.insert(ObjectIdentifier(page.contents))
        page.contents.close()
    }

    /// ⌘O, Open as Tab: the Peek becomes a Today tab right under its entry
    /// (spec §I.6), selected, keeping its page and history.
    public func expandShownPeek() {
        guard let opener = currentEntryID, let page = peeks[opener], let sidebar,
              let entry = insertRelatedToday(url: page.contents.url?.absoluteString, openedBy: opener) else { return }
        peeks.removeValue(forKey: opener)
        updatePeek(animated: false)
        pages[entry.id] = page
        observe(page, entry: entry.id)
        relatedChain = (opener, entry.id)
        sidebar.select(entry.id)
    }

    /// ⇧⌘O, Split (spec §I.6, Zen `cmd_zenGlanceSplit`): the Peek becomes a
    /// Today tab under its entry, as Open as Tab, and the pane beside its
    /// entry (in the entry's split if it has one), focused. A full split refuses.
    public func splitShownPeek() {
        guard let opener = currentEntryID, let page = peeks[opener], let sidebar else { return }
        if let group = store.sidebar.splitGroup(of: opener), !SplitRules.canAdd(toCount: group.members.count) {
            return sidebar.showSplitFullToast()
        }
        guard let entry = insertRelatedToday(url: page.contents.url?.absoluteString, openedBy: opener) else { return }
        peeks.removeValue(forKey: opener)
        updatePeek(animated: false)
        pages[entry.id] = page
        observe(page, entry: entry.id)
        relatedChain = (opener, entry.id)
        sidebar.joinIntoSplit(entry.id, with: opener)
    }

    /// ⇧⌘T on a closed Peek (the sidebar selected its entry first).
    public func reopenPeek(url: String, over entry: UUID) {
        guard let url = URL(string: url) else { return }
        openPeek(url, over: entry)
    }

    /// Space on a focused permanent row (spec §I.13): its stored URL in Peek
    /// over the selected page (or the row itself is selected when nothing is).
    public func peek(_ entry: Entry) {
        guard let url = entry.storedURL.flatMap(URL.init(string:)) else { return }
        guard let current = currentEntryID, current != entry.id else { return sidebar?.select(entry.id) ?? () }
        openPeek(url, over: current)
    }

    /// The entry a Peek page opened over, if `contents` is one.
    func peekOpener(of contents: any WebContents) -> UUID? {
        peeks.first { $0.value.contents === contents }?.key
    }

    /// The selected entry's Peek on screen (or none), and the focus with it.
    func updatePeek(animated: Bool) {
        let contents = currentEntryID.flatMap { peeks[$0]?.contents }
        guard contents !== peekContents || animated else { return }
        peekContents = contents
        if let page = currentEntryID.flatMap({ peeks[$0] }) { page.lastVisible = now() }
        peekDisplay?.showPeek(contents, animated: animated)
    }

    /// The Peek's decision for a navigation of an entry's page (`nil`: not one of its pages).
    func peekDecision(for action: NavigationAction, in contents: any WebContents) -> PeekDecision {
        guard let id = entryID(for: contents), let page = pages[id], let entry = store.sidebar.entry(id) else { return .asRequested }
        let since = lastUserInput.map { uptime() - $0 }
        let context = PeekRules.Context(isPermanentEntry: entry.kind.isPermanent, isEnabled: isPeekEnabled(),
                                        currentURL: contents.url ?? entry.currentURL.flatMap(URL.init(string:)),
                                        hoveredLink: page.hoveredLink, secondsSinceUserInput: since)
        let decision = PeekRules.decision(for: action, context: context)
        debugPeekDecisions?(action, decision)
        return decision
    }

    /// A Today tab placed per §A.7 under `openerID` (links, popups, Open as Tab).
    func insertRelatedToday(url: String?, openedBy openerID: UUID) -> Entry? {
        guard let sidebar, let opener = store.sidebar.entry(openerID) else { return nil }
        let space = opener.spaceID ?? sidebar.activeSpaceID
        let lastRelated = relatedChain?.opener == openerID ? relatedChain?.last : nil
        let index = NavigationRules.relatedTabIndex(opener: opener, lastRelated: lastRelated, today: store.sidebar.today(space: space))
        return try? store.sidebar.addEntry(.today, url: url, space: space, at: index)
    }
}
