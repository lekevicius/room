import AppKit
import Engine
import FakeEngine
import Model
import Observation
import Sidebar
import Store

/// Phase 2.2's stand-in for the Phase 2.3 tab controller: one FakeEngine
/// page per loaded entry, the selected one in the card. Page title and URL
/// flow into the store (`setLivePage`), so "changed" and labels behave as
/// they will with real pages. Written against the `Engine` protocols; 2.3
/// replaces it with real pages on CEF.
final class SidebarPages: SidebarHost {
    private let profile: any Engine.Profile
    private let pageHost: PageHost
    private let store: RoomStore
    weak var sidebar: SidebarController?
    private var pages: [UUID: any WebContents] = [:]
    /// Bumped per page so a stale observation callback stops re-arming.
    private var generations: [UUID: Int] = [:]

    init(profile: any Engine.Profile, pageHost: PageHost, store: RoomStore) {
        self.profile = profile
        self.pageHost = pageHost
        self.store = store
    }

    func page(_ id: UUID) -> (any WebContents)? { pages[id] }

    // MARK: SidebarHost

    func pageState(for entry: UUID) -> EntryPageState {
        guard let page = pages[entry] else { return .unloaded }
        // FakeEngine's favicon is a template globe; letter tiles read better.
        let favicon = page.favicon.flatMap { $0.isTemplate ? nil : $0 }
        return EntryPageState(isLoaded: true, isLoading: page.isLoading, isAudible: page.isAudible, isMuted: page.isMuted,
                              favicon: favicon)
    }

    func activate(_ entry: Entry) {
        let page = pages[entry.id] ?? makePage(for: entry)
        pageHost.show(page)
    }

    func deactivate() {
        pageHost.show(nil)
    }

    func unload(_ entry: UUID) {
        guard let page = pages.removeValue(forKey: entry) else { return }
        generations[entry, default: 0] += 1
        if pageHost.contents === page { pageHost.show(nil) }
        page.close()
    }

    func reset(_ entry: Entry) {
        guard let url = entry.storedURL.flatMap(URL.init(string:)) else { return }
        pages[entry.id]?.load(url)
    }

    func separate(_ entry: UUID, into newEntry: Entry) {
        guard let page = pages.removeValue(forKey: entry) else { return }
        generations[entry, default: 0] += 1
        pages[newEntry.id] = page
        observe(page, entry: newEntry.id)
    }

    func reload(_ entry: UUID) { pages[entry]?.reload() }

    func setMuted(_ muted: Bool, entry: UUID) { pages[entry]?.isMuted = muted }

    func newTab() {
        guard let text = Self.prompt(title: "New Tab", message: "Search or enter a URL (the palette arrives in Phase 2.4).", text: ""),
              let url = DebugSession.url(from: text), let sidebar,
              let entry = try? store.sidebar.addEntry(.today, url: url.absoluteString, space: sidebar.activeSpaceID) else { return }
        sidebar.select(entry.id)
    }

    func editAddress() {
        guard let sidebar, let id = sidebar.selectedEntryID, let entry = store.sidebar.entry(id) else {
            newTab()
            return
        }
        guard let text = Self.prompt(title: "Open Location", message: "Navigate the selected tab (the palette arrives in Phase 2.4).",
                                     text: entry.currentURL ?? ""),
              let url = DebugSession.url(from: text) else { return }
        if let page = pages[id] { page.load(url) } else {
            try? store.sidebar.setLivePage(id, url: url.absoluteString, title: nil)
            activate(store.sidebar.entry(id) ?? entry)
        }
    }

    // MARK: Pages

    private func makePage(for entry: Entry) -> any WebContents {
        let page: any WebContents
        do {
            page = try profile.createWebContents(WebContentsConfiguration())
        } catch {
            fatalError("FakeEngine page: \(error)")
        }
        pages[entry.id] = page
        observe(page, entry: entry.id)
        if let url = entry.currentURL.flatMap(URL.init(string:)) { page.load(url) }
        return page
    }

    /// Mirrors the page into the store and the sidebar row until it closes or moves.
    private func observe(_ page: any WebContents, entry: UUID) {
        generations[entry, default: 0] += 1
        track(page, entry: entry, generation: generations[entry]!)
    }

    private func track(_ page: any WebContents, entry: UUID, generation: Int) {
        guard generations[entry] == generation, pages[entry] === page else { return }
        let (url, title) = withObservationTracking {
            _ = (page.isLoading, page.isAudible, page.isMuted, page.favicon)
            return (page.url, page.title)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let page = self.pages[entry] else { return }
                self.track(page, entry: entry, generation: generation)
            }
        }
        if let url, store.sidebar.entry(entry)?.liveURL != url.absoluteString || store.sidebar.entry(entry)?.liveTitle != title {
            try? store.sidebar.setLivePage(entry, url: url.absoluteString, title: title)
        }
        sidebar?.pageStateDidChange([entry])
    }

    // MARK: Debug actions (Debug menu, snapshot runner)

    /// Loads an entry's page without showing it; `stalled` leaves it loading.
    func debugLoad(_ id: UUID, stalled: Bool = false) {
        guard pages[id] == nil, let entry = store.sidebar.entry(id) else { return }
        let page = profile.makeWebContentsForDebug()
        (page as? FakeWebContents)?.loadsSynchronously = !stalled
        pages[id] = page
        observe(page, entry: id)
        if let url = entry.currentURL.flatMap(URL.init(string:)) { page.load(url) }
    }

    /// A same-site link click in the selected page (makes a pinned entry "changed").
    func navigateSelected() {
        guard let id = sidebar?.selectedEntryID, let page = pages[id] as? FakeWebContents, let url = page.url else { return }
        let next = url.appending(path: "page-\(Int.random(in: 1...999))")
        page.simulateLinkClick(to: next)
    }

    func toggleAudioInSelected() {
        guard let id = sidebar?.selectedEntryID, let page = pages[id] as? FakeWebContents else { return }
        page.simulateAudio(!page.isAudible)
    }

    // MARK: Prompt (throwaway until the palette, Phase 2.4)

    private static func prompt(title: String, message: String, text: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: text)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Engine.Profile {
    func makeWebContentsForDebug() -> any WebContents {
        do { return try createWebContents(WebContentsConfiguration(initiallyHidden: true)) } catch { fatalError("\(error)") }
    }
}
