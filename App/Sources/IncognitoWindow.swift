import AppKit
import Chrome
import Design
import Engine
import Model
import Sidebar
import Store
import Tabs
import UIKitCore

/// The incognito window's own pieces (4.8b, PLAN §4 "Windows and
/// incognito"): the active profile's off-the-record twin, the ephemeral store
/// its sidebar and tab controller work on (nothing reaches the database or a
/// file), and a temporary folder for its reader files.
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
    /// ⇧⌘N (spec §J): the incognito window of the active space's profile;
    /// one per profile, so pressed again it comes forward.
    @objc func newIncognitoWindow(_ sender: Any?) {
        openIncognitoWindow(profileID: nil)
    }

    /// The incognito window of `profileID` (nil: the active regular window's
    /// space's profile), opened on the profile's off-the-record twin, or the
    /// open one brought forward. Nil without a state, before the profile's
    /// engine profile exists, or while the previous twin is still closing
    /// (a toast says so).
    @discardableResult
    func openIncognitoWindow(profileID requested: UUID?) -> WindowSession? {
        guard let store else { return nil }
        let source = windows.activeRegular
        let profileID = requested ?? source?.sidebar.flatMap { store.sidebar.space($0.activeSpaceID)?.profileID } ?? store.sidebar.profiles.first?.id
        guard let profileID, let model = store.sidebar.profiles.first(where: { $0.id == profileID }) else { return nil }
        if let open = windows.all.first(where: { $0.incognito?.profileID == profileID }) {
            windows.focus(open)
            NSApp.activate()
            return open
        }
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
        let sidebarWidth = source.flatMap { store.windows.window($0.id) }?.sidebarWidth ?? Double(SidebarMetrics.defaultWidth)
        let ephemeral = RoomStore.incognito(profile: model, settings: store.settings.settings, sidebarWidth: sidebarWidth,
                                            themeColors: [Palette.incognitoTintHex])
        guard let row = ephemeral.windows.windows.first else { return nil }
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Room-Incognito-Reader-\(row.id.uuidString)", directoryHint: .isDirectory)
        let controller = RoomWindowController()
        let pageHost = PageHost(controller: controller)
        let session = WindowSession(id: row.id, controller: controller, pageHost: pageHost)
        session.incognito = IncognitoContext(profileID: profileID, regular: regular, twin: twin, store: ephemeral, readerFolder: folder)
        controller.applyIncognitoLook()
        controller.sidebarWidth = CGFloat(sidebarWidth)
        controller.spaceTitle = "Incognito"
        if let base = source?.window?.frame {
            controller.restoreFrame(DragOutRule.cascaded(from: base, screen: source?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero))
        }
        // Its frame and sidebar are not stored; its close ends its pages and the twin.
        controller.onWillClose = { [weakSelf = MainActorWeak(self), weakSession = MainActorWeak(session)] in
            guard let session = weakSession.value else { return }
            weakSelf.value?.incognitoWindowWillClose(session)
        }
        installSidebar(session, store: ephemeral, launch: .new)
        windows.add(session)
        showSelection(of: session)
        windows.focus(session)
        NSApp.activate()
        NSLog("Room: incognito window opened (%ld window(s))", windows.all.count)
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

    /// The incognito window closed: its pages close (nothing is saved), the
    /// twin ends with its cookies and site data, its reader folder goes.
    func incognitoWindowWillClose(_ session: WindowSession) {
        guard let incognito = session.incognito, windows.all.contains(where: { $0 === session }) else { return }
        if let tabs = session.tabs {
            for id in tabs.loadedEntryIDs { tabs.unload(id) }
            tabs.deactivate()
        }
        session.tearDown()
        windows.remove(session)
        incognito.twin.downloadsDelegate = nil
        incognito.regular.closeOffTheRecord()
        try? FileManager.default.removeItem(at: incognito.readerFolder)
        NSLog("Room: incognito window closed: its pages and the off-the-record profile end (%ld window(s) open)", windows.all.count)
    }

    /// "Open Link in Incognito Window" from a page (B-50): the page Chrome
    /// opened in the twin moves into the profile's incognito window (opened
    /// or brought forward) as a new Today tab there.
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
