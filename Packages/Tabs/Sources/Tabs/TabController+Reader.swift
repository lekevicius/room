import AppKit
import Engine
import Model

/// One entry's reader page (4.7b): a second page of the entry's profile
/// showing Room's reader HTML (a `file://` page the app wrote), shown in the
/// card in place of the entry's page, which stays loaded, hidden and
/// untouched behind it (as a Peek keeps its entry's page): its back/forward
/// list and scroll position are there when reader mode ends.
final class ReaderPage {
    let contents: any WebContents
    /// The reader HTML the page loaded.
    let fileURL: URL
    /// The entry's page URL when reader mode began (Exit Reader and the byline link point there).
    let original: URL?

    init(contents: any WebContents, fileURL: URL, original: URL?) {
        self.contents = contents
        self.fileURL = fileURL
        self.original = original
    }
}

/// Reader mode's sessions. The app distills the entry's page and writes the
/// reader HTML; the controller makes the reader page, swaps it into the card,
/// and ends reader mode on Esc, ⌥⇧⌘R (the app), a link, Unload and ⌘W. Back
/// and Forward act on the reader page (which has no history) while it shows,
/// so the entry's page moves only after Exit.
extension TabController {
    /// The reader page of `entry`, if it is in reader mode.
    public func readerContents(for entry: UUID) -> (any WebContents)? { readers[entry]?.contents }

    /// The reader HTML of `entry`'s reader page.
    public func readerFile(for entry: UUID) -> URL? { readers[entry]?.fileURL }

    /// Entries in reader mode.
    public var readerEntryIDs: [UUID] { Array(readers.keys) }

    /// The entry a reader page reads.
    public func readerEntry(of contents: any WebContents) -> UUID? {
        readers.first { $0.value.contents === contents }?.key
    }

    /// The card's entry is in reader mode.
    public var isReaderShown: Bool { currentEntryID.map { readers[$0] != nil } ?? false }

    /// Reader mode ended for an entry (Esc, a link, ⌥⇧⌘R, unload): the app
    /// deletes the reader file and its history row.
    public typealias ReaderEnded = (_ entry: UUID, _ fileURL: URL, _ original: URL?) -> Void

    /// Shows `fileURL` (the reader HTML of `entry`'s page) in a new page of
    /// the entry's profile, in the card in place of the entry's page; a reader
    /// page it had closes first. Returns the reader page, or nil (no page, no profile).
    @discardableResult
    public func openReader(_ fileURL: URL, for entry: UUID) -> (any WebContents)? {
        guard let page = pages[entry], let profile = engineProfiles[page.profileID] else { return nil }
        closeReader(of: entry)
        let contents: any WebContents
        do {
            contents = try profile.createWebContents(WebContentsConfiguration(initiallyHidden: entry != currentEntryID, hostWindow: window))
        } catch {
            NSLog("Room: no reader page: \(error)")
            return nil
        }
        contents.uiDelegate = self
        contents.navigationDelegate = self
        contents.zoomFactor = page.contents.zoomFactor
        readers[entry] = ReaderPage(contents: contents, fileURL: fileURL, original: page.contents.url)
        debugDidAdopt?(contents)
        contents.load(fileURL, transition: .bookmark, fromAddressBar: false)
        if entry == currentEntryID, let stored = store.sidebar.entry(entry) {
            activate(stored)
            onReaderToggled?(entry, true)
        }
        sidebar?.pageStateDidChange([entry])
        return contents
    }

    /// Ends reader mode for `entry`: the reader page closes and the card
    /// shows the entry's page again, as it was.
    public func exitReader(_ entry: UUID) {
        guard readers[entry] != nil else { return }
        closeReader(of: entry)
        if entry == currentEntryID, let stored = store.sidebar.entry(entry) {
            activate(stored)
            onReaderToggled?(entry, false)
        }
        sidebar?.pageStateDidChange([entry])
    }

    /// Closes the reader page without touching the card (unload, a new reader page).
    func closeReader(of entry: UUID) {
        guard let reader = readers.removeValue(forKey: entry) else { return }
        if reader.contents.state != .closed { reader.contents.close() }
        onReaderEnded?(entry, reader.fileURL, reader.original)
    }

    /// The reader page's renderer went away by itself: reader mode ends.
    func readerPageClosed(_ entry: UUID) {
        guard let reader = readers.removeValue(forKey: entry) else { return }
        onReaderEnded?(entry, reader.fileURL, reader.original)
        if entry == currentEntryID, let stored = store.sidebar.entry(entry) {
            activate(stored)
            onReaderToggled?(entry, false)
        }
        sidebar?.pageStateDidChange([entry])
    }

    /// A navigation in the reader page: its own load (and a fragment) stays;
    /// the original page's URL only exits; another link exits and loads in
    /// the entry's page (its history grows as for any link). A new-tab
    /// disposition (⌘-click) goes on as a Today tab under the entry.
    func readerPolicy(for action: NavigationAction, entry: UUID) -> Disposition {
        guard let reader = readers[entry] else { return action.disposition }
        let outcome = ReaderNavigation.outcome(of: action.url, readerPage: reader.fileURL, original: reader.original)
        if outcome != .stay { NSLog("Room: reader page navigation (%@, %@) → %@", "\(action.kind)", "\(action.disposition)", "\(outcome)") }
        guard action.disposition == .currentTab else { return action.disposition }
        switch outcome {
        case .stay:
            return action.disposition
        case .exit:
            Task { @MainActor in self.exitReader(entry) }
            return .ignore
        case .exitAndLoad(let url):
            Task { @MainActor in
                self.exitReader(entry)
                self.pages[entry]?.contents.load(url, transition: .link, fromAddressBar: false)
            }
            return .ignore
        }
    }
}

/// Where a navigation in the reader page leads (pure; `TabController.readerPolicy`).
nonisolated public enum ReaderNavigation {
    public enum Outcome: Equatable, Sendable {
        case stay, exit, exitAndLoad(URL)
    }

    /// The reader page itself (a fragment included) stays; the original
    /// page's URL exits; anything else exits and loads.
    public static func outcome(of url: URL, readerPage: URL, original: URL?) -> Outcome {
        if sameDocument(url, readerPage) { return .stay }
        if let original, sameDocument(url, original) { return .exit }
        return .exitAndLoad(url)
    }

    static func sameDocument(_ a: URL, _ b: URL) -> Bool {
        var left = URLComponents(url: a, resolvingAgainstBaseURL: false)
        var right = URLComponents(url: b, resolvingAgainstBaseURL: false)
        left?.fragment = nil
        right?.fragment = nil
        return left?.url?.absoluteString == right?.url?.absoluteString
    }
}
