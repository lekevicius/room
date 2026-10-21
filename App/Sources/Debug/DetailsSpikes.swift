#if DEBUG
import AppKit
import Card
import Chrome
import Engine
import Model
import Sidebar
import Store
import UIKitCore

/// Phase 5.6a spike `details` (`scripts/details-check.sh`): spec §I's small
/// things on a throwaway state, the pages on the test server :8766. Sections
/// (`-RoomSpikeOnly` picks):
/// - `empty` (§I.15): a fresh state's rows, the empty grid and its drop slot,
///   the empty card's line under New Tab's default, remapped and removed key;
/// - `titles` (§I.3): a page titled "(3) Inbox" (the row says "Inbox" with the
///   unread dot), pinned, then moved away (the stored label stays, the live
///   title is the hover sublabel);
/// - `icons`: Change Icon… from the row's menu (the picker, an emoji pressed
///   through accessibility), a folder's and an Essential's icon, None;
/// - `clear` (B-118): Clear as the pointer leaves and enters the sidebar;
/// - `dialogs` (B-116): the first alert without the checkbox, the second with
///   it, checked: the third answered unseen; a reload ends it;
/// - `folders` (B-117): New Folder with Tab inside a folder, New Subfolder to
///   depth 5 (then disabled), the folder-onto-folder drop's feedback;
/// - `folderdrag`: two folders for a real drag by computer use (stays
///   running with `-RoomSpikeKeepRunning YES`; the rows' window points recorded);
/// - `nowindow`: the last window closed, nothing opens (§I.15), last.
/// `-RoomSpikeCaptureDirectory` keeps in-process captures named
/// `phase-5.6-<section>-<appearance>.png`.
extension SpikeRunner.Context {
    func detailsChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false }
        NSApp.appearance = NSAppearance(named: detailsAppearance == "dark" ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 1200, height: 780))
        controller.sidebarWidth = 280
        controller.activityOverride = true
        await activate()
        SpikeRunner.record("conditions", "load=\(SpikeRunner.loadAverage()) appearance=\(detailsAppearance) app=\(Bundle.main.bundlePath)")
        if runs("empty") { await detailsEmpty() }
        if runs("titles") { await detailsTitles() }
        if runs("icons") { await detailsIcons() }
        if runs("clear") { await detailsClear() }
        if runs("dialogs") { await detailsDialogs() }
        if runs("folders") { await detailsFolders() }
        if only.contains("folderdrag") { await detailsFolderDragSetup() }
        if only.contains("nowindow") { await detailsNoWindow() }
    }

    private var detailsAppearance: String { UserDefaults.standard.string(forKey: "RoomSpikeAppearance") == "dark" ? "dark" : "light" }
    private static let detailsBase = "http://127.0.0.1:8766/"

    /// The window (with `others` over it, a popover) as the window server draws it, kept for the review sheet.
    private func detailsCapture(_ name: String, others: [NSWindow] = []) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory") else { return }
        window.displayIfNeeded()
        let url = URL(fileURLWithPath: directory).appending(path: "phase-5.6-\(name)-\(detailsAppearance).png")
        guard let image = others.isEmpty ? WindowSnapshot.capture(window) : WindowSnapshot.capture(window, with: others),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else { return SpikeRunner.record("capture_\(name)", "failed") }
        SpikeRunner.record("capture_\(name)", "\(url.lastPathComponent) \(image.width)x\(image.height) px")
    }

    private var space: UUID { sidebar.activeSpaceID }

    private func view(_ identifier: String, in root: NSView?) -> NSView? {
        guard let root else { return nil }
        if root.accessibilityIdentifier() == identifier { return root }
        for child in root.subviews { if let found = view(identifier, in: child) { return found } }
        return nil
    }

    // MARK: empty (§I.15)

    func detailsEmpty() async {
        let today = store.today(space: space, window: sidebar.windowID)
        SpikeRunner.record("empty_today", "today=\(today.count) rows=\(sidebar.debugRowKinds.joined(separator: ","))")
        SpikeRunner.record("empty_essentials", "essentials=\(sidebar.debugEssentialIDs.count) grid_shown=\(sidebar.debugEssentialsShown)")
        sidebar.select(nil)
        try? await Task.sleep(for: .milliseconds(400))
        let card = { (AppDelegate.current?.pageHostContainer?.pageView as? CardEmptyStateView)?.message ?? "no empty card" }
        detailsCapture("empty-card")
        sidebar.debugShowDropSlot(true)
        try? await Task.sleep(for: .milliseconds(300))
        detailsCapture("empty-dropslot")
        sidebar.debugShowDropSlot(false)
        let defaultLine = card()
        let settings = sidebar.store.settings
        settings.update { $0.shortcutOverrides["newPage:"] = "⌥⌘N" }
        _ = await waitUntil(3) { card() != defaultLine }
        let remapped = card()
        settings.update { $0.shortcutOverrides["newPage:"] = "" }
        _ = await waitUntil(3) { card() != remapped }
        let removed = card()
        settings.update { $0.shortcutOverrides["newPage:"] = nil }
        _ = await waitUntil(3) { card() == defaultLine }
        SpikeRunner.record("empty_card", "default=\"\(defaultLine)\" remapped=\"\(remapped)\" removed=\"\(removed)\" restored=\"\(card())\"")
    }

    // MARK: titles (§I.3)

    func detailsTitles() async {
        guard let page = await open(URL(string: Self.detailsBase + "find.html?inbox")!), let id = tabs.entryID(for: page) else {
            return SpikeRunner.record("error", "titles: no page")
        }
        _ = await js(page, "document.title = '(3) Inbox'; 0")
        _ = await waitUntil(5) { self.store.entry(id)?.liveTitle == "(3) Inbox" }
        try? await Task.sleep(for: .milliseconds(300))
        SpikeRunner.record("titles_today", "live=\"\(store.entry(id)?.liveTitle ?? "nil")\" row=\"\(sidebar.debugRowTitle(for: id) ?? "nil")\" \(sidebar.debugRowBadges(id))")
        detailsCapture("titles-unread")
        // Pinned: at its stored URL the label is the current title; away from it, the stored label stays.
        try? store.move(id, to: .pinned(space: space, folder: nil), at: 0)
        try? await Task.sleep(for: .milliseconds(300))
        _ = await js(page, "document.title = '(4) Inbox'; 0")
        _ = await waitUntil(5) { self.store.entry(id)?.liveTitle == "(4) Inbox" }
        SpikeRunner.record("titles_pinned", "stored=\"\(store.entry(id)?.storedTitle ?? "nil")\" \(sidebar.debugRowBadges(id))")
        page.load(URL(string: Self.detailsBase + "find.html?thread")!)
        await waitLoaded(page)
        _ = await js(page, "document.title = 'Re: lunch on Friday'; 0")
        _ = await waitUntil(5) { self.store.entry(id)?.liveTitle == "Re: lunch on Friday" }
        try? await Task.sleep(for: .milliseconds(300))
        sidebar.debugHover(id)
        try? await Task.sleep(for: .milliseconds(400))
        SpikeRunner.record("titles_changed", "changed=\(store.isChanged(id)) \(sidebar.debugRowBadges(id))")
        detailsCapture("titles-changed-hover")
        sidebar.debugHover(nil)
    }

    // MARK: icons (Change Icon…)

    func detailsIcons() async {
        guard let page = await open(URL(string: Self.detailsBase + "find.html?icon")!), let id = tabs.entryID(for: page) else {
            return SpikeRunner.record("error", "icons: no page")
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard let menu = sidebar.debugContextMenu(for: id), let index = menu.items.firstIndex(where: { $0.title == "Change Icon…" }) else {
            return SpikeRunner.record("icons_menu", "no Change Icon… item")
        }
        let item = menu.items[index]
        SpikeRunner.record("icons_menu", "item=\"\(item.title)\" enabled=\(item.isEnabled) tooltip=\(item.toolTip ?? "none")")
        menu.performActionForItem(at: index)
        _ = await waitUntil(3) { self.sidebar.debugIconPopoverWindow != nil }
        try? await Task.sleep(for: .milliseconds(400))
        guard let popover = sidebar.debugIconPopoverWindow else { return SpikeRunner.record("icons_popover", "not shown") }
        SpikeRunner.record("icons_popover", "shown size=\(Int(popover.frame.width))x\(Int(popover.frame.height))")
        detailsCapture("icons-picker", others: [popover])
        // The pick typed into the picker's emoji field, as the keyboard would (its text view's insertText:);
        // `-RoomDetailsWaitForClick YES` waits 180 s for a click in the grid instead (computer use).
        let byClick = UserDefaults.standard.bool(forKey: "RoomDetailsWaitForClick")
        var how = "click"
        if byClick {
            SpikeRunner.record("icons_waiting", "click an emoji in the picker (popover frame \(popover.frame))")
            _ = await waitUntil(180) { self.store.entry(id)?.customIcon != nil }
        } else if let field = firstField(in: sidebar.debugIconPopoverView), popover.makeFirstResponder(field), let editor = field.currentEditor() {
            editor.insertText("🍕")
            how = "typed"
            _ = await waitUntil(3) { self.store.entry(id)?.customIcon != nil }
        } else {
            how = "no field"
        }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("icons_pick", "by=\(how) icon=\(store.entry(id)?.customIcon ?? "nil") "
                           + "popover_closed=\(sidebar.debugIconPopoverWindow?.isVisible != true) row_shows=\(sidebar.debugRowBadges(id))")
        detailsCapture("icons-picked")
        // A folder's and an Essential's icon, a symbol and an emoji.
        guard let folder = try? store.addFolder(name: "Projects", space: space) else { return }
        _ = try? store.addEntry(.pinned, url: Self.detailsBase + "find.html?inside", title: "Inside", space: space, folder: folder.id)
        try? store.setCustomIcon(folder.id, "hammer")
        if let essential = try? store.addEntry(.essential, url: Self.detailsBase + "find.html?essential", title: "Essential", space: space) {
            try? store.setCustomIcon(essential.id, "🎨")
        }
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("icons_rows", "folder=\(store.entry(folder.id)?.customIcon ?? "nil") rows=\(sidebar.debugRowKinds.joined(separator: ","))")
        detailsCapture("icons-rows")
        try? store.setCustomIcon(id, nil)
        try? await Task.sleep(for: .milliseconds(200))
        SpikeRunner.record("icons_none", "icon=\(store.entry(id)?.customIcon ?? "nil")")
    }

    private func firstField(in root: NSView?) -> NSTextField? {
        guard let root else { return nil }
        if let field = root as? NSTextField, field.isEditable { return field }
        for child in root.subviews { if let found = firstField(in: child) { return found } }
        return nil
    }

    // MARK: clear (B-118)

    func detailsClear() async {
        if store.today(space: space, window: sidebar.windowID).isEmpty {
            _ = await open(URL(string: Self.detailsBase + "find.html?clear")!)
        }
        try? await Task.sleep(for: .milliseconds(300))
        sidebar.debugPointerInside(false)
        try? await Task.sleep(for: .milliseconds(400))
        let away = sidebar.debugClear
        detailsCapture("clear-away")
        sidebar.debugPointerInside(true)
        try? await Task.sleep(for: .milliseconds(400))
        let over = sidebar.debugClear
        detailsCapture("clear-hover")
        sidebar.debugPointerInside(nil)
        try? await Task.sleep(for: .milliseconds(400))
        let real = sidebar.debugClear
        let mouse = NSEvent.mouseLocation
        SpikeRunner.record("clear", "away: present=\(away.present) shown=\(away.shown) alpha=\(away.alpha); over: shown=\(over.shown) alpha=\(over.alpha); "
                           + "real pointer at \(Int(mouse.x)),\(Int(mouse.y)) window=\(Int(window.frame.minX)),\(Int(window.frame.minY)) "
                           + "inside=\(real.pointerInside) shown=\(real.shown)")
    }

    // MARK: dialogs (B-116)

    func detailsDialogs() async {
        guard let page = await open(URL(string: Self.detailsBase + "dialogs.html")!) else { return SpikeRunner.record("error", "dialogs: no page") }
        try? await Task.sleep(for: .milliseconds(400))
        let prompts = session.pageDelegate.chrome.prompts
        func checkbox() -> NSButton? { view("dialog-suppress", in: window.contentView) as? NSButton }
        func alert() async -> Bool {
            Task { await self.click(page, "#alert") }
            return await waitUntil(8) { prompts.visibleDialog != nil }
        }
        let first = await alert()
        try? await Task.sleep(for: .milliseconds(300))
        let firstLine = "shown=\(first) offers=\(prompts.visibleDialog?.offersSuppression == true) checkbox=\(checkbox() != nil)"
        pressReturn()
        _ = await waitUntil(5) { prompts.visibleDialog == nil }
        let second = await alert()
        try? await Task.sleep(for: .milliseconds(300))
        let box = checkbox()
        let secondLine = "shown=\(second) offers=\(prompts.visibleDialog?.offersSuppression == true) checkbox=\"\(box?.title ?? "none")\""
        detailsCapture("dialog-second")
        box?.performClick(nil)
        let checked = box?.state == .on
        pressReturn()
        _ = await waitUntil(5) { prompts.visibleDialog == nil }
        let before = prompts.suppressedCount
        Task { await self.click(page, "#alert") }
        try? await Task.sleep(for: .milliseconds(1500))
        let third = "shown=\(prompts.visibleDialog != nil) answered_unseen=\(prompts.suppressedCount - before) "
            + "log=\(await js(page, "document.getElementById('log').textContent"))"
        page.reload()
        await waitLoaded(page)
        try? await Task.sleep(for: .milliseconds(400))
        let suppressedBefore = prompts.suppressedCount
        let afterReload = await alert()
        try? await Task.sleep(for: .milliseconds(300))
        let reloadLine = "shown=\(afterReload) offers=\(prompts.visibleDialog?.offersSuppression == true) "
            + "still_suppressed=\(prompts.suppressedPages.contains(ObjectIdentifier(page))) answered_unseen=\(prompts.suppressedCount - suppressedBefore)"
        pressReturn()
        _ = await waitUntil(5) { prompts.visibleDialog == nil }
        SpikeRunner.record("dialogs", "first: \(firstLine); second: \(secondLine) checked=\(checked); third: \(third); after reload: \(reloadLine)")
    }

    // MARK: folders (B-117)

    func detailsFolders() async {
        guard let outer = try? store.addFolder(name: "Outer", space: space),
              let child = try? store.addEntry(.pinned, url: Self.detailsBase + "find.html?child", title: "Child page", space: space, folder: outer.id),
              let other = try? store.addFolder(name: "Other", space: space) else { return SpikeRunner.record("error", "folders: fixture") }
        try? await Task.sleep(for: .milliseconds(400))
        // New Folder with Tab on a pinned entry inside a folder: a subfolder there.
        guard let menu = sidebar.debugContextMenu(for: child.id),
              let index = menu.items.firstIndex(where: { $0.title == "New Folder with Tab" }) else {
            return SpikeRunner.record("folders_menu", "no New Folder with Tab on a pinned entry")
        }
        let enabled = menu.items[index].isEnabled
        menu.performActionForItem(at: index)
        try? await Task.sleep(for: .milliseconds(400))
        guard let sub = store.entry(child.id)?.folderID else { return SpikeRunner.record("folders_menu", "no folder made") }
        sidebar.debugRenameEnded(sub, label: "Sub")
        let depth = FolderRules.depth(of: sub, in: store.entries) ?? -1
        SpikeRunner.record("folders_new_with_tab", "enabled=\(enabled) label=\(store.entry(sub)?.customLabel ?? "?") parent=\(store.entry(sub)?.folderID == outer.id ? "Outer" : "?") depth=\(depth)")
        // New Subfolder down to depth 5, then disabled.
        var deepest = sub
        var subfolderStates: [String] = []
        for _ in 0..<4 {
            guard let folderMenu = sidebar.debugContextMenu(for: deepest),
                  let item = folderMenu.items.firstIndex(where: { $0.title == "New Subfolder" }) else { break }
            subfolderStates.append("d\(FolderRules.depth(of: deepest, in: store.entries) ?? -1):\(folderMenu.items[item].isEnabled)")
            guard folderMenu.items[item].isEnabled else { break }
            let before = Set(store.entries.keys)
            folderMenu.performActionForItem(at: item)
            try? await Task.sleep(for: .milliseconds(300))
            guard let made = Set(store.entries.keys).subtracting(before).first else { break }
            sidebar.debugRenameEnded(made, label: "Level \((FolderRules.depth(of: made, in: store.entries) ?? 0))")
            deepest = made
        }
        if let folderMenu = sidebar.debugContextMenu(for: deepest), let item = folderMenu.items.firstIndex(where: { $0.title == "New Subfolder" }) {
            subfolderStates.append("d\(FolderRules.depth(of: deepest, in: store.entries) ?? -1):\(folderMenu.items[item].isEnabled)")
        }
        SpikeRunner.record("folders_subfolders", subfolderStates.joined(separator: " "))
        detailsCapture("folders-nested")
        // The drop of a folder onto a folder after the hold: its feedback (the real drag is `folderdrag`).
        sidebar.debugShowDrag([other.id], over: outer.id, fraction: 0.5, held: true)
        try? await Task.sleep(for: .milliseconds(300))
        detailsCapture("folders-drop-onto")
        sidebar.debugShowDrag(nil)
        let canDrop = (try? store.canMove([other.id], to: .pinned(space: space, folder: outer.id)).get()) != nil
        SpikeRunner.record("folders_drop_rule", "folder onto folder: allowed=\(canDrop)")
    }

    /// Two top-level folders, Target (expanded, with a child) and Mover, for a computer-use drag;
    /// their rows' points in the window (top-left origin, points) for the drag.
    func detailsFolderDragSetup() async {
        guard let target = try? store.addFolder(name: "Target", space: space),
              (try? store.addEntry(.pinned, url: Self.detailsBase + "find.html?target-child", title: "Target child", space: space, folder: target.id)) != nil,
              let mover = try? store.addFolder(name: "Mover", space: space) else { return SpikeRunner.record("error", "folderdrag: fixture") }
        try? await Task.sleep(for: .milliseconds(600))
        guard let contentView = window.contentView else { return }
        func point(_ id: UUID) -> String {
            guard let row = sidebar.debugRowView(for: id) else { return "none" }
            let frame = row.convert(row.bounds, to: contentView)
            let height = contentView.bounds.height
            return "x=\(Int(frame.midX)) y=\(Int(height - frame.maxY)) h=\(Int(frame.height))"
        }
        SpikeRunner.record("folderdrag_rows", "target=\(target.id.uuidString) \(point(target.id)); mover=\(mover.id.uuidString) \(point(mover.id)); "
                           + "window=\(Int(window.frame.width))x\(Int(window.frame.height))")
        SpikeRunner.record("folderdrag_ready", "drag Mover onto Target's middle and rest 1 s; the spike reads the store every second for 300 s")
        for _ in 0..<300 {
            try? await Task.sleep(for: .seconds(1))
            if store.entry(mover.id)?.folderID == target.id { break }
        }
        SpikeRunner.record("folderdrag_result", "mover_parent=\(store.entry(mover.id)?.folderID == target.id ? "Target" : "root") "
                           + "rows=\(sidebar.debugRowKinds.joined(separator: ","))")
        detailsCapture("folders-dragged")
    }

    // MARK: nowindow (§I.15)

    func detailsNoWindow() async {
        window.performClose(nil)
        try? await Task.sleep(for: .seconds(2))
        let visible = NSApp.windows.filter { $0.isVisible && $0 is RoomWindow }
        SpikeRunner.record("nowindow", "room_windows_visible=\(visible.count) app_running=true")
    }
}
#endif
