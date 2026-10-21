import AppKit
import Chrome
import Design
import Engine
import Model
import Sidebar
import Store
import Tabs
import UIKitCore

/// The incognito windows' shared pieces (4.8b, PLAN §4 "Windows and
/// incognito"; several windows per profile since 5.6b, B-98): the profile's
/// off-the-record twin, the ephemeral store their sidebars and tab
/// controllers work on (one window row each; nothing reaches the database or
/// a file), and a temporary folder for their reader files. The last of the
/// profile's incognito windows to close ends them.
@MainActor
final class IncognitoContext {
    /// The model profile whose twin this is (the ephemeral store's one profile has its id).
    let profileID: UUID
    let regular: any Engine.Profile
    let twin: any Engine.Profile
    let store: RoomStore
    /// Reader files of its entries (removed at Exit and when the window closes).
    let readerFolder: URL

    init(profileID: UUID, regular: any Engine.Profile, twin: any Engine.Profile, store: RoomStore, readerFolder: URL) {
        self.profileID = profileID
        self.regular = regular
        self.twin = twin
        self.store = store
        self.readerFolder = readerFolder
    }
}

extension AppDelegate {
    /// ⇧⌘N (spec §J): a new incognito window of the active space's profile;
    /// several share the profile's off-the-record twin, as Chrome's (B-98).
    @objc func newIncognitoWindow(_ sender: Any?) {
        openIncognitoWindow(profileID: nil, reuse: false)
    }

    /// An incognito window of `profileID` (nil: the active regular window's
    /// space's profile). `reuse` (a link opened in incognito) brings the
    /// profile's most recent incognito window forward when one is open;
    /// otherwise a new window opens on the twin the profile's open incognito
    /// windows share, or on a new twin. Nil without a state, before the
    /// profile's engine profile exists, or while the previous twin is still
    /// closing (a toast says so).
    @discardableResult
    func openIncognitoWindow(profileID requested: UUID?, reuse: Bool = true) -> WindowSession? {
        guard let store else { return nil }
        let source = windows.activeRegular
        let profileID = requested ?? source?.sidebar.flatMap { store.sidebar.space($0.activeSpaceID)?.profileID } ?? store.sidebar.profiles.first?.id
        guard let profileID, let model = store.sidebar.profiles.first(where: { $0.id == profileID }) else { return nil }
        let open = windows.all.filter { $0.incognito?.profileID == profileID }
        if reuse, let recent = windows.lastKey.flatMap({ last in open.first { $0 === last } }) ?? open.last {
            windows.focus(recent)
            NSApp.activate()
            return recent
        }
        let base = (windows.active ?? source)?.window
        let sidebarWidth = source.flatMap { store.windows.window($0.id) }?.sidebarWidth ?? Double(SidebarMetrics.defaultWidth)
        let context: IncognitoContext
        let windowID: UUID
        if let shared = open.first?.incognito {
            // Another window on the same twin and store: a row of its own, its own Today list.
            context = shared
            windowID = shared.store.windows.createWindow(frame: nil, sidebarWidth: sidebarWidth,
                                                         space: shared.store.sidebar.spaces.first?.id).id
        } else {
            guard let regular = engineProfiles[profileID] else {
                NSSound.beep()
                NSLog("Room: no incognito window yet: the profile's engine profile is not ready")
                return nil
            }
            let twin: any Engine.Profile
            do {
                twin = try regular.offTheRecord()
            } catch {
                NSLog("Room: no incognito window: \(error)")
                toastCenter?.show(Toast(id: "incognito-closing", symbol: .info, message: "The last incognito window is still closing. Try again in a moment."))
                return nil
            }
            // Downloads go to the same list and folder as the profile's (spec §J).
            twin.downloadsDelegate = downloadList
            applyIncognitoExtensions(profileID: profileID, regular: regular)
            observeIncognitoExtensions()
            let ephemeral = RoomStore.incognito(profile: model, settings: store.settings.settings, sidebarWidth: sidebarWidth,
                                                themeColors: [Palette.incognitoTintHex])
            guard let row = ephemeral.windows.windows.first else { return nil }
            let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Room-Incognito-Reader-\(row.id.uuidString)", directoryHint: .isDirectory)
            context = IncognitoContext(profileID: profileID, regular: regular, twin: twin, store: ephemeral, readerFolder: folder)
            // A Today list asked for without a window (a link from another app) is the most recent incognito window's.
            ephemeral.sidebar.defaultWindow = { [weakSelf = MainActorWeak(self), weakContext = MainActorWeak(context), weak ephemeral] in
                let mine = weakSelf.value?.windows.all.filter { $0.incognito === weakContext.value } ?? []
                return (weakSelf.value?.windows.lastKey.flatMap { last in mine.first { $0 === last } } ?? mine.last)?.id
                    ?? ephemeral?.windows.windows.first?.id
            }
            windowID = row.id
        }
        let controller = RoomWindowController()
        let pageHost = PageHost(controller: controller)
        let session = WindowSession(id: windowID, controller: controller, pageHost: pageHost)
        session.incognito = context
        controller.applyIncognitoLook()
        controller.sidebarWidth = CGFloat(sidebarWidth)
        controller.spaceTitle = "Incognito"
        if let frame = base?.frame {
            controller.restoreFrame(DragOutRule.cascaded(from: frame, screen: base?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero))
        }
        // Its frame and sidebar are not stored; its close ends its pages (and, the last one, the twin).
        controller.onWillClose = { [weakSelf = MainActorWeak(self), weakSession = MainActorWeak(session)] in
            guard let session = weakSession.value else { return }
            weakSelf.value?.incognitoWindowWillClose(session)
        }
        installSidebar(session, store: context.store, launch: .new)
        windows.add(session)
        showSelection(of: session)
        windows.focus(session)
        NSApp.activate()
        NSLog("Room: incognito window opened (%ld of the profile, %ld window(s))", open.count + 1, windows.all.count)
        return session
    }

    /// What `installSidebar` does differently for the incognito window.
    func installIncognitoParts(_ session: WindowSession, incognito: IncognitoContext) {
        guard let tabs = session.tabs else { return }
        let profileID = incognito.profileID
        // The omnibox and ⌘Y read the regular profile's history, as Chrome's
        // incognito omnibox does (HistoryService redirects off-the-record to
        // the original profile); the incognito pages add nothing to it.
        session.palette?.makeAutocomplete = { [weakSelf = MainActorWeak(self)] id in weakSelf.value?.engineProfiles[id]?.makeAutocompleteController() }
        session.palette?.engineHistory = { [weakSelf = MainActorWeak(self)] id in weakSelf.value?.engineProfiles[id]?.history }
        // The Library keeps no history of its own here.
        session.library?.history = { nil }
        // Only the extensions allowed in incognito (4.5's setting).
        let settings = store?.settings
        session.extensionPopups?.allows = { [weak settings] id in
            settings?.settings.allowsInIncognito(id, profile: profileID) ?? false
        }
        tabs.openOffTheRecord = nil
    }

    /// An incognito window closed: its pages close and its Today tabs and row
    /// leave the shared store (nothing is saved). The last of the profile's
    /// incognito windows ends the twin with its cookies and site data, and
    /// the reader folder goes (B-98).
    func incognitoWindowWillClose(_ session: WindowSession) {
        guard let incognito = session.incognito, windows.all.contains(where: { $0 === session }) else { return }
        if let tabs = session.tabs {
            for id in tabs.loadedEntryIDs { tabs.unload(id) }
            tabs.deactivate()
        }
        for entry in incognito.store.sidebar.todayEntries(window: session.id) { _ = try? incognito.store.sidebar.remove(entry.id) }
        session.tearDown()
        windows.remove(session)
        let others = windows.all.filter { $0.incognito === incognito }.count
        guard others == 0 else {
            incognito.store.windows.removeWindow(session.id)
            NSLog("Room: incognito window closed: its pages end; %ld incognito window(s) of the profile still open", others)
            return
        }
        incognito.twin.downloadsDelegate = nil
        incognito.regular.closeOffTheRecord()
        try? FileManager.default.removeItem(at: incognito.readerFolder)
        NSLog("Room: incognito window closed: its pages and the off-the-record profile end (%ld window(s) open)", windows.all.count)
    }

    /// "Open Link in Incognito Window" from a page (B-50): the page Chrome
    /// opened in the twin moves into the profile's most recent incognito
    /// window (opened or brought forward) as a new Today tab there.
    func adoptOffTheRecordPage(_ contents: any WebContents, url: URL?, profileID: UUID?) {
        guard let session = openIncognitoWindow(profileID: profileID), let tabs = session.tabs, let window = session.window else {
            contents.close()
            return
        }
        do {
            try contents.move(toHostWindow: window)
        } catch {
            NSLog("Room: the off-the-record page did not move: \(error)")
            contents.close()
            return
        }
        if tabs.adoptNewTab(contents, url: url) == nil { contents.close() }
    }

    /// `Settings.extensionsInIncognito` onto the engine (4.5's setting,
    /// 4.8b's member): every installed extension of the profile allowed or not.
    func applyIncognitoExtensions(profileID: UUID, regular: any Engine.Profile) {
        guard let store, let engineExtensions = regular.extensions else { return }
        for item in engineExtensions.installed {
            engineExtensions.setAllowedInIncognito(store.settings.settings.allowsInIncognito(item.id, profile: profileID), extension: item.id)
        }
    }

    /// Settings ▸ Extensions' "Allow in incognito" reaches the engine when it changes.
    func observeIncognitoExtensions() {
        guard !incognitoExtensionsObserved, let settings = store?.settings else { return }
        incognitoExtensionsObserved = true
        observeIncognitoExtensions(settings)
    }

    private func observeIncognitoExtensions(_ settings: SettingsStore) {
        withObservationTracking {
            _ = settings.settings.extensionsInIncognito
        } onChange: { [weakSelf = MainActorWeak(self), weakSettings = MainActorWeak(settings)] in
            Task { @MainActor in
                guard let self = weakSelf.value, let settings = weakSettings.value else { return }
                for (id, profile) in self.engineProfiles { self.applyIncognitoExtensions(profileID: id, regular: profile) }
                self.observeIncognitoExtensions(settings)
            }
        }
    }
}
