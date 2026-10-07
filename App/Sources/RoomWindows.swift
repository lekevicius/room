import AppKit
import Chrome
import Engine
import Library
import Palette
import Sidebar
import Store
import Tabs
import UIKitCore

/// One browser window and everything that is per window (4.8a, PLAN §4
/// "Windows and incognito"): its controller and card, its sidebar (the shared
/// spaces, pinned entries and essentials, and its own Today tabs), its tab
/// controller (the pages it holds: one `RoomBrowser` per window and profile
/// on RoomCore), and the pieces 4.2–4.7b made for one window: the palette,
/// toasts, find, zoom, the status pill, Peek, the hidden sidebar, the ⌃Tab
/// switcher, the Library, the extension popups and key router, the
/// picture-in-picture panels and the reader controller.
@MainActor
final class WindowSession {
    /// The window's row in the store (`WindowState.id`); its Today tabs carry it.
    let id: UUID
    let controller: RoomWindowController
    let pageHost: PageHost
    var pageDelegate: PageUIDelegate!
    var sidebar: SidebarController!
    var tabs: TabController!
    var palette: PaletteController?
    var toasts: ToastCenter?
    var promptPresenter: PagePromptPresenter?
    var downloads: DownloadsUI?
    var find: FindController?
    var zoom: ZoomIndicator?
    var statusPill: StatusPill?
    var peek: PeekPresenter?
    var hiddenSidebar: HiddenSidebar?
    var switcher: TabSwitcher?
    var library: LibraryController?
    var extensionPopups: ExtensionPopups?
    var extensionKeys: ExtensionKeyRouter?
    var pictureInPicture: PictureInPicturePanels?
    var reader: ReaderController?
    var firstRunCard: FirstRunCardView?
    var fullscreen: PageFullscreen?
    /// The window's press and key monitor (Peek's gesture window, the idle clock).
    var inputMonitor: Any?
    /// The last press in the window: Peek's 2 s gesture window and where its open animation starts.
    var lastClick: (point: CGPoint, time: TimeInterval)?
    /// The selection was shown (loaded). At launch only the front window's
    /// loads (spec §H); another restored window loads its selection when it
    /// first becomes key.
    var selectionShown = false

    init(id: UUID, controller: RoomWindowController, pageHost: PageHost) {
        self.id = id
        self.controller = controller
        self.pageHost = pageHost
    }

    var window: NSWindow? { controller.window }

    /// The window closed: monitors, timers and panels stop (the session is dropped next).
    func tearDown() {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        tabs?.stopLifecycle()
        tabs?.ownership = nil
        pictureInPicture?.closeAll()
        switcher = nil
        extensionKeys = nil
        extensionPopups = nil
        downloads = nil
        palette = nil
        hiddenSidebar = nil
        reader = nil
    }
}

/// Every browser window (4.8a). The app's menu commands act on `active`: the
/// key browser window, else the main one, else the last key one (Settings or
/// a sheet may be key), else the first.
@MainActor
final class RoomWindows {
    private(set) var all: [WindowSession] = []
    private(set) var lastKey: WindowSession?
    private var keyObserver: Any?

    /// A page lives in one window: the controllers' coordinator (`PageOwnership`).
    private(set) lazy var owners = PageOwners { [weakSelf = MainActorWeak(self)] in
        weakSelf.value?.all.compactMap(\.tabs) ?? []
    }

    /// A window became key for the first time (the app loads its selection then).
    var onBecameKey: ((WindowSession) -> Void)?

    init() {
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                                             queue: .main) { [weakSelf = MainActorWeak(self)] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self = weakSelf.value, let session = self.session(for: window) else { return }
                self.lastKey = session
                self.onBecameKey?(session)
            }
        }
    }

    var active: WindowSession? {
        session(for: NSApp.keyWindow) ?? session(for: NSApp.mainWindow) ?? lastKey ?? all.first
    }

    func session(for window: NSWindow?) -> WindowSession? {
        guard let window else { return nil }
        return all.first { $0.window === window }
    }

    func session(id: UUID) -> WindowSession? { all.first { $0.id == id } }

    /// The session holding `contents` (an entry's page, its Peek or reader page).
    func session(holding contents: any WebContents) -> WindowSession? {
        all.first { $0.tabs?.entryID(for: contents) != nil || $0.tabs?.engineProfile(for: contents) != nil }
    }

    /// The window showing `space`: the active one if it does, else the first that does.
    func showing(space: UUID) -> WindowSession? {
        if let active, active.sidebar?.activeSpaceID == space { return active }
        return all.first { $0.sidebar?.activeSpaceID == space }
    }

    func add(_ session: WindowSession) {
        all.append(session)
        session.tabs?.ownership = owners
    }

    func remove(_ session: WindowSession) {
        all.removeAll { $0 === session }
        if lastKey === session { lastKey = nil }
    }

    /// Makes `session` key and front, and the active one at once (macOS may
    /// defer the key status while another app is frontmost).
    func focus(_ session: WindowSession) {
        lastKey = session
        session.controller.showWindow(nil)
        session.window?.makeKeyAndOrderFront(nil)
    }
}

/// The engine shows an extension's popup on the button of the window whose
/// page it is for (`ExtensionsCenter.popupPresenter` is one per app; 4.8a).
@MainActor
final class ExtensionPopupRouter: ExtensionPopupPresenting {
    private let windows: RoomWindows

    init(windows: RoomWindows) {
        self.windows = windows
    }

    private func presenter(for page: (any WebContents)?) -> ExtensionPopups? {
        let session = page.flatMap { windows.session(holding: $0) } ?? windows.active
        return session?.extensionPopups ?? windows.active?.extensionPopups
    }

    private func presenter(showing popup: any WebContents) -> ExtensionPopups? {
        windows.all.compactMap(\.extensionPopups).first { $0.popover?.popup === popup } ?? windows.active?.extensionPopups
    }

    func showPopup(_ popup: any WebContents, for id: InstalledExtension.ID, page: (any WebContents)?, size: CGSize) {
        presenter(for: page)?.showPopup(popup, for: id, page: page, size: size)
    }

    func resizePopup(_ popup: any WebContents, to size: CGSize) {
        presenter(showing: popup)?.resizePopup(popup, to: size)
    }

    func closePopup(_ popup: any WebContents) {
        presenter(showing: popup)?.closePopup(popup)
    }
}
