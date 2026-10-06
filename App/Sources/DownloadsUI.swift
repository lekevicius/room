import AppKit
import Chrome
import Design
import Engine
import Observation
import Sidebar
import Store
import UIKitCore

/// The window's downloads (ROADMAP 2.6 task 1, spec §F): `list` is every
/// engine profile's downloads delegate; the footer button mirrors it (ring,
/// bounce, badge); a click or ⇧⌘J opens the popover; a new download flies
/// in from the click that started it.
final class DownloadsUI {
    let list = DownloadList()
    let popover: DownloadsPopover
    private weak var button: DownloadsButton?
    private weak var rootView: BrowserWindowView?
    private weak var toasts: ToastPresenting?
    /// The button's menu ▸ Open Library: the Library at Downloads (4.1a).
    var onOpenLibrary: (() -> Void)?
    /// The current page's favicon: the flying icon (spec §F "the clicked link's favicon").
    var pageFavicon: () -> NSImage? = { nil }
    /// The last click in the window, in the root view's coordinates.
    private var lastClick: (point: NSPoint, time: Date)?
    private var clickMonitor: Any?

    init(button: DownloadsButton, rootView: BrowserWindowView, toasts: ToastPresenting?, settings: SettingsStore) {
        self.button = button
        self.rootView = rootView
        self.toasts = toasts
        popover = DownloadsPopover(list: list)
        list.folder = { [weak settings] in
            DownloadRules.folder(setting: settings?.settings.downloadDirectory,
                                 downloads: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
        }
        button.onClick = { [weak self] in self?.togglePopover() }
        button.menuProvider = { [weak self] in self?.buttonMenu() }
        list.onBegin = { [weak self] row in self?.flyIn(row) }
        list.onComplete = { [weak self] row in self?.completed(row) }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .otherMouseDown]) { [weak self] event in
            if let self, let rootView = self.rootView, event.window === rootView.window {
                self.lastClick = (rootView.convert(event.locationInWindow, from: nil), Date())
            }
            return event
        }
        observe()
    }

    isolated deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }

    /// The ring and the badge follow the list.
    private func observe() {
        let (progress, unseen) = withObservationTracking {
            (list.progress, list.unseenCompleted)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        button?.progress = progress
        button?.badgeCount = unseen
    }

    /// ⇧⌘J and the button. With the sidebar hidden it opens from the card's bottom-left corner.
    func togglePopover() {
        if let button, button.window != nil, !button.isHiddenOrHasHiddenAncestor {
            popover.toggle(relativeTo: button)
        } else if let rootView {
            if popover.isShown { return popover.close() }
            let card = rootView.currentLayout.card
            popover.show(relativeTo: rootView, rect: NSRect(x: card.minX + Spacing.l, y: card.maxY - 1, width: 1, height: 1))
        }
    }

    private func buttonMenu() -> NSMenu {
        let menu = NSMenu()
        let library = NSMenuItem(title: "Open Library", action: #selector(MenuTarget.perform(_:)), keyEquivalent: "")
        let libraryTarget = MenuTarget { [weak self] in self?.onOpenLibrary?() }
        library.target = libraryTarget
        library.representedObject = libraryTarget
        menu.addItem(library)
        let folder = NSMenuItem(title: "Show Downloads Folder", action: #selector(MenuTarget.perform(_:)), keyEquivalent: "")
        let target = MenuTarget { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.list.folder())
        }
        folder.target = target
        folder.representedObject = target
        menu.addItem(folder)
        return menu
    }

    private func flyIn(_ row: DownloadList.Row) {
        guard let rootView, let button, button.window != nil, !button.isHiddenOrHasHiddenAncestor else { return }
        let card = rootView.currentLayout.card
        let start: NSPoint
        if let click = lastClick, Date().timeIntervalSince(click.time) < DownloadsMetrics.clickMemory, card.contains(click.point) {
            start = click.point
        } else {
            start = NSPoint(x: card.midX, y: card.midY)
        }
        let image = pageFavicon() ?? NSWorkspace.shared.icon(for: .data)
        DownloadFlyIn.run(image: image, from: start, to: button.target(in: rootView), in: rootView) {}
    }

    private func completed(_ row: DownloadList.Row) {
        button?.bounce()
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        // With the sidebar hidden the button cannot be seen: a toast says so (spec §E, §F).
        guard let rootView, !rootView.isSidebarOpen else { return }
        let name = (row.item.destination ?? row.destination)?.lastPathComponent ?? row.item.suggestedFilename
        let id = row.id
        toasts?.show(Toast(id: "download-complete", symbol: .downloads, message: "Downloaded “\(name)”",
                           action: Toast.Action(title: "Show") { [weak self] in self?.list.reveal(id) }))
    }
}

/// A closure as a menu item's target (kept alive by `representedObject`).
final class MenuTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func perform(_ sender: Any?) { action() }
}
