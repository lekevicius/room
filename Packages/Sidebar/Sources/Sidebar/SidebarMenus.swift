import AppKit
import Chrome
import Design
import Model
import Omnibox
import Store

/// Context menus (spec §A.8 entries, §A.6 folders) and the footer's "+"
/// menu. Commands that need a later phase are present and disabled, with
/// the phase in their tooltip.
extension SidebarController {
    /// A right-click on `id`: the group's menu when it is part of a
    /// multi-selection of two or more (spec §A.9), else its own.
    func menu(forClicked id: UUID) -> NSMenu? {
        let ids = commandTargets(id)
        return ids.count >= 2 ? groupMenu(ids) : menu(for: id)
    }

    func menu(for id: UUID) -> NSMenu? {
        guard let entry = sidebar.entry(id) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch entry.kind {
        case .today: buildTodayMenu(menu, entry)
        case .pinned: buildPinnedMenu(menu, entry)
        case .essential: buildEssentialMenu(menu, entry)
        case .folder: buildFolderMenu(menu, entry)
        }
        addSplitItems(menu, entry)
        return menu
    }

    func makePlusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(action(CommandName.newTab, symbol: .newTab, key: "t") { [weak self] in self?.host?.newTab() })
        menu.addItem(action(CommandName.newFolder, symbol: .newFolder) { [weak self] in self?.newFolder(parent: nil) })
        menu.addItem(action(CommandName.newSplit, symbol: .newSplit, key: "+", enabled: selectedEntryID != nil) { [weak self] in
            self?.newSplitPane()
        })
        menu.addItem(action(CommandName.newSpace, symbol: .newSpace) { [weak self] in self?.newSpace() })
        return menu
    }

    /// Commands on a multi-selection (one section, two or more entries).
    func groupMenu(_ ids: [UUID]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let entries = ids.compactMap(sidebar.entry)
        let count = entries.count
        let kind = entries.first?.kind ?? .today
        let essentialsRoom = EntryRules.essentialsCap - essentialsCount
        switch kind {
        case .today, .pinned:
            let title = kind == .today ? CommandName.pinTabs(count) : CommandName.unpinTabs(count)
            menu.addItem(action(title, symbol: kind == .today ? .pin : .unpin, key: "d") { [weak self] in self?.togglePin() })
            menu.addItem(action(CommandName.addTabsToEssentials(count), symbol: .essential, key: "d", modifiers: [.command, .shift],
                                enabled: count <= essentialsRoom) { [weak self] in self?.toggleEssentials() })
            let moveItem = NSMenuItem(title: CommandName.moveTo, action: nil, keyEquivalent: "")
            moveItem.image = Symbol.moveTo.image()
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            let others = sidebar.spaces.filter { $0.id != tree.spaceID }
            for space in others {
                submenu.addItem(action(space.name) { [weak self] in for id in ids { self?.move(id, toSpace: space.id) } })
            }
            if others.isEmpty {
                let none = NSMenuItem(title: "No Other Spaces", action: nil, keyEquivalent: "")
                none.isEnabled = false
                submenu.addItem(none)
            }
            moveItem.submenu = submenu
            menu.addItem(moveItem)
            menu.addItem(action(CommandName.newFolderWithTabs(count), symbol: .newFolder) { [weak self] in self?.newFolder(with: ids) })
            menu.addItem(action(CommandName.joinTabs(count), symbol: .newSplit, enabled: count <= SplitRules.maxPanes) { [weak self] in
                self?.joinSelection(ids)
            })
        case .essential:
            menu.addItem(action(CommandName.removeTabsFromEssentials(count), symbol: .removeEssential, key: "d",
                                modifiers: [.command, .shift]) { [weak self] in self?.toggleEssentials() })
        case .folder:
            break
        }
        menu.addItem(.separator())
        let urls = entries.compactMap(\.currentURL)
        menu.addItem(action(CommandName.copyURLs(urls.count), symbol: .copyURL, enabled: !urls.isEmpty) { [weak self] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.joined(separator: "\n"), forType: .string)
            self?.toasts?.show(Toast(id: "copy-url", symbol: .copyURL, message: urls.count == 1 ? "Copied 1 link" : "Copied \(urls.count) links"))
        })
        let loaded = ids.filter { pageState($0).isLoaded }
        menu.addItem(action(CommandName.unloadTabs(loaded.count), symbol: .unload, enabled: !loaded.isEmpty) { [weak self] in
            for id in loaded { self?.unload(id) }
        })
        if kind == .today || kind == .pinned {
            menu.addItem(.separator())
            if kind == .today {
                menu.addItem(action(CommandName.archiveTabs(count), symbol: .archive) { [weak self] in
                    guard let self else { return }
                    clearMultiSelection()
                    archiveToday(ids, keeping: nil)
                })
                menu.addItem(action(CommandName.closeTabs(count), symbol: .closeTab, key: "w") { [weak self] in
                    guard let self else { return }
                    clearMultiSelection()
                    closeToday(ids, keeping: nil)
                })
            } else {
                menu.addItem(action(CommandName.removeTabs(count), symbol: .closeTab) { [weak self] in
                    guard let self else { return }
                    clearMultiSelection()
                    for id in ids { removeEntry(id, undoable: true) }
                })
            }
        }
        return menu
    }

    /// "New Folder with N Tabs" (spec §A.6): a folder where the first entry
    /// was (end of the pinned root for Today tabs) holding the entries.
    func newFolder(with ids: [UUID]) {
        guard let first = ids.first.flatMap(sidebar.entry) else { return }
        let parent = first.kind == .pinned ? first.folderID : nil
        let index = first.kind == .pinned ? first.position : nil
        guard let folder = try? sidebar.addFolder(name: CommandName.newFolder, space: tree.spaceID, parent: parent, at: index) else { return }
        do throws(SidebarError) {
            try sidebar.move(ids, to: .pinned(space: tree.spaceID, folder: folder.id), insertingAt: 0)
        } catch {
            _ = try? sidebar.remove(folder.id)
            showRefusal(error)
            return
        }
        clearMultiSelection()
        if tree.space?.pinnedCollapsed == true { togglePinnedCollapsed() }
        beginRename(folder.id)
    }

    // MARK: Per kind

    private func buildTodayMenu(_ menu: NSMenu, _ entry: Entry) {
        let id = entry.id
        menu.addItem(action(CommandName.pinTab, symbol: .pin, key: "d") { [weak self] in self?.pin(id) })
        menu.addItem(addToEssentialsItem(entry))
        menu.addItem(moveToSpaceItem(entry))
        menu.addItem(action(CommandName.newFolderWithTab, symbol: .newFolder) { [weak self] in self?.newFolderWithTab(id) })
        menu.addItem(splitWithItem(entry))
        menu.addItem(.separator())
        addCommonItems(menu, entry)
        menu.addItem(.separator())
        addPageItems(menu, entry)
        menu.addItem(.separator())
        let today = sidebar.today(space: tree.spaceID, window: windowID)
        let index = today.firstIndex { $0.id == id } ?? 0
        menu.addItem(action(CommandName.archiveTab, symbol: .archive) { [weak self] in self?.archiveToday([id], keeping: nil) })
        menu.addItem(action(CommandName.archiveBelow, symbol: .archive, enabled: index < today.count - 1) { [weak self] in
            self?.archiveToday(Array(today[(index + 1)...]).map(\.id), keeping: id)
        })
        menu.addItem(action(CommandName.closeTabsBelow, enabled: index < today.count - 1) { [weak self] in
            self?.closeToday(Array(today[(index + 1)...]).map(\.id), keeping: id)
        })
        menu.addItem(action(CommandName.closeOtherTabs, enabled: today.count > 1) { [weak self] in
            self?.closeToday(today.filter { $0.id != id }.map(\.id), keeping: id)
        })
        menu.addItem(action(CommandName.closeTab, symbol: .closeTab, key: "w") { [weak self] in self?.close(id) })
    }

    private func buildPinnedMenu(_ menu: NSMenu, _ entry: Entry) {
        let id = entry.id
        menu.addItem(action(CommandName.unpinTab, symbol: .unpin, key: "d") { [weak self] in self?.unpin(id) })
        menu.addItem(addToEssentialsItem(entry))
        menu.addItem(moveToSpaceItem(entry))
        menu.addItem(moveToFolderItem(entry))
        menu.addItem(pinnedURLItem(entry))
        menu.addItem(splitWithItem(entry))
        menu.addItem(.separator())
        addCommonItems(menu, entry)
        menu.addItem(.separator())
        addPageItems(menu, entry)
        menu.addItem(.separator())
        menu.addItem(action(CommandName.remove, symbol: .closeTab) { [weak self] in self?.removeEntry(id, undoable: true) })
    }

    private func buildEssentialMenu(_ menu: NSMenu, _ entry: Entry) {
        let id = entry.id
        menu.addItem(action(CommandName.removeFromEssentials, symbol: .removeEssential, key: "d", modifiers: [.command, .shift]) {
            [weak self] in self?.removeFromEssentials(id)
        })
        menu.addItem(pinnedURLItem(entry))
        addOpenInNewWindow(menu, entry)
        menu.addItem(.separator())
        menu.addItem(action(CommandName.rename, symbol: .rename) { [weak self] in self?.renameWithPopover(id) })
        menu.addItem(later(CommandName.changeIcon, symbol: .changeIcon, phase: "5.6"))
        menu.addItem(action(CommandName.copyURL, symbol: .copyURL, key: "c", modifiers: [.command, .shift], enabled: entry.currentURL != nil) {
            [weak self] in self?.copyURL(of: id, markdown: false)
        })
        menu.addItem(.separator())
        addPageItems(menu, entry)
    }

    private func buildFolderMenu(_ menu: NSMenu, _ folder: Entry) {
        let id = folder.id
        let children = descendants(of: id)
        menu.addItem(action(CommandName.rename, symbol: .rename) { [weak self] in self?.beginRename(id) })
        menu.addItem(later(CommandName.changeIcon, symbol: .changeIcon, phase: "5.6"))
        let canNest = (try? FolderRules.validateNewFolder(in: id, in: sidebar.entries)) != nil
        menu.addItem(action(CommandName.newSubfolder, symbol: .newFolder, enabled: canNest) { [weak self] in self?.newFolder(parent: id) })
        menu.addItem(.separator())
        let loaded = children.filter { pageState($0.id).isLoaded }
        menu.addItem(action(CommandName.unloadAllTabs, symbol: .unload, enabled: !loaded.isEmpty) { [weak self] in
            for entry in loaded { self?.unload(entry.id) }
        })
        let urls = children.compactMap(\.currentURL)
        menu.addItem(action(CommandName.copyAllLinks, symbol: .copyURL, enabled: !urls.isEmpty) { [weak self] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.joined(separator: "\n"), forType: .string)
            self?.toasts?.show(Toast(id: "copy-url", symbol: .copyURL, message: urls.count == 1 ? "Copied 1 link" : "Copied \(urls.count) links"))
        })
        let pasted = NSPasteboard.general.string(forType: .string).flatMap(URLFixup.url(from:))
        menu.addItem(action(CommandName.pasteURLAsNewTab, symbol: .paste, enabled: pasted != nil) { [weak self] in
            guard let self, let pasted else { return }
            _ = try? sidebar.addEntry(.pinned, url: pasted, space: tree.spaceID, folder: id)
            if sidebar.entry(id)?.isCollapsed == true { try? sidebar.setFolderCollapsed(id, false) }
        })
        menu.addItem(.separator())
        menu.addItem(later(CommandName.convertToSpace, symbol: .newSpace, phase: "2.5"))
        menu.addItem(moveToSpaceItem(folder, title: CommandName.moveToSpace))
        menu.addItem(action(CommandName.unpack, symbol: .folderOpen, enabled: !sidebar.pinned(space: tree.spaceID, folder: id).isEmpty) {
            [weak self] in self?.removeEntry(id, undoable: false)
        })
        menu.addItem(action(CommandName.deleteFolder, symbol: .deleteSpace) { [weak self] in self?.deleteFolder(id) })
    }

    /// "Open in New Window" (4.8a): the entry selected in a new window
    /// cascaded from this one (a Today tab moves there, a shared entry's page
    /// moves when it loads there).
    private func addOpenInNewWindow(_ menu: NSMenu, _ entry: Entry) {
        guard let onOpenInNewWindow else { return }
        let id = entry.id
        menu.addItem(action(CommandName.openInNewWindow, symbol: .newWindow, enabled: entry.currentURL != nil) {
            onOpenInNewWindow(id, nil)
        })
    }

    /// Rename, Change Icon, Duplicate, Copy URL / Markdown (Today and pinned).
    private func addCommonItems(_ menu: NSMenu, _ entry: Entry) {
        let id = entry.id
        let hasURL = entry.currentURL != nil
        menu.addItem(action(CommandName.duplicateTab, symbol: .duplicate, enabled: hasURL) { [weak self] in self?.duplicate(id) })
        addOpenInNewWindow(menu, entry)
        menu.addItem(action(CommandName.rename, symbol: .rename) { [weak self] in self?.beginRename(id) })
        menu.addItem(later(CommandName.changeIcon, symbol: .changeIcon, phase: "5.6"))
        menu.addItem(action(CommandName.copyURL, symbol: .copyURL, key: "c", modifiers: [.command, .shift], enabled: hasURL) {
            [weak self] in self?.copyURL(of: id, markdown: false)
        })
        menu.addItem(action(CommandName.copyMarkdown, symbol: .copyMarkdown, key: "c", modifiers: [.command, .shift, .option],
                            enabled: hasURL) { [weak self] in self?.copyURL(of: id, markdown: true) })
        // Spec §B: a `contains` rule for the page's host, targeting this space, in the routing sheet.
        let host = entry.currentURL.flatMap { URL(string: $0) }.flatMap { url in
            ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? url.host(percentEncoded: false) : nil
        }
        let space = entry.spaceID ?? tree.spaceID
        menu.addItem(action(CommandName.addRouteForDomain, symbol: .routing, enabled: host != nil && onRoutingSettings != nil) {
            [weak self] in
            guard let host else { return }
            self?.onRoutingSettings?((host.hasPrefix("www.") ? String(host.dropFirst(4)) : host, space))
        })
    }

    /// Reload, Mute, Unload: need a loaded page.
    private func addPageItems(_ menu: NSMenu, _ entry: Entry) {
        let id = entry.id
        let page = pageState(id)
        menu.addItem(action(CommandName.reload, symbol: .reload, key: "r", enabled: page.isLoaded) { [weak self] in self?.host?.reload(id) })
        menu.addItem(action(page.isMuted ? CommandName.unmuteTab : CommandName.muteTab, symbol: page.isMuted ? .audible : .muted,
                            key: "m", modifiers: [.command, .shift], enabled: page.isLoaded) { [weak self] in
            self?.audioButtonClicked(id)
        })
        menu.addItem(action(CommandName.unloadTab, symbol: .unload, enabled: page.isLoaded) { [weak self] in self?.unload(id) })
    }

    private func addToEssentialsItem(_ entry: Entry) -> NSMenuItem {
        let count = tree.space.map { sidebar.essentials(profile: $0.profileID).count } ?? 0
        let full = !EntryRules.canAddEssential(currentCount: count)
        let hasURL = entry.currentURL != nil
        return action("\(CommandName.addToEssentials) (\(count)/\(EntryRules.essentialsCap))", symbol: .essential, key: "d",
                      modifiers: [.command, .shift], enabled: !full && hasURL) { [weak self] in self?.addToEssentials(entry.id) }
    }

    private func moveToSpaceItem(_ entry: Entry, title: String = CommandName.moveTo) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = Symbol.moveTo.image()
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let others = sidebar.spaces.filter { $0.id != tree.spaceID }
        for space in others {
            submenu.addItem(action(space.name) { [weak self] in self?.move(entry.id, toSpace: space.id) })
        }
        if others.isEmpty {
            let none = NSMenuItem(title: "No Other Spaces", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        }
        if entry.kind != .folder {
            submenu.addItem(.separator())
            submenu.addItem(addToEssentialsItem(entry).retitled("Essentials"))
        }
        item.submenu = submenu
        return item
    }

    private func moveToFolderItem(_ entry: Entry) -> NSMenuItem {
        let item = NSMenuItem(title: CommandName.moveToFolder, action: nil, keyEquivalent: "")
        item.image = Symbol.folder.image()
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if entry.folderID != nil {
            submenu.addItem(action("Pinned (top level)") { [weak self] in self?.moveToFolder(entry.id, folder: nil) })
            submenu.addItem(.separator())
        }
        func add(_ folder: UUID?, level: Int) {
            for child in sidebar.pinned(space: tree.spaceID, folder: folder) where child.kind == .folder {
                let target = action(EntryLabel.title(child), symbol: .folder, enabled: child.id != entry.folderID) { [weak self] in
                    self?.moveToFolder(entry.id, folder: child.id)
                }
                target.indentationLevel = level
                submenu.addItem(target)
                add(child.id, level: level + 1)
            }
        }
        add(nil, level: 0)
        if submenu.items.contains(where: { $0.indentationLevel >= 0 && !$0.isSeparatorItem && $0.title != "Pinned (top level)" }) {
            submenu.addItem(.separator())
        }
        submenu.addItem(action("\(CommandName.newFolder)…", symbol: .newFolder) { [weak self] in self?.newFolderWithTab(entry.id) })
        item.submenu = submenu
        return item
    }

    private func pinnedURLItem(_ entry: Entry) -> NSMenuItem {
        let id = entry.id
        let changed = isChanged(entry)
        let item = NSMenuItem(title: CommandName.pinnedURL, action: nil, keyEquivalent: "")
        item.image = Symbol.resetPinned.image()
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(action(CommandName.resetPinnedTab, symbol: .resetPinned, enabled: changed) { [weak self] in self?.reset(id) })
        submenu.addItem(action(CommandName.replacePinnedURL, enabled: changed) { [weak self] in
            guard let self else { return }
            try? sidebar.replaceStoredURLWithCurrent(id)
            pageStateDidChange([id])
            toasts?.show(Toast(id: "pinned-url", symbol: .success, message: "Pinned URL updated"))
        })
        submenu.addItem(action(CommandName.editPinnedURL) { [weak self] in self?.editPinnedURL(id) })
        item.submenu = submenu
        return item
    }

    // MARK: Item helpers

    /// The main menu's action each default key below names (`docs/shortcuts.md`):
    /// the item shows that action's current key (`shortcutKey`, 4.4a).
    static let shortcutIDs: [String: String] = [
        "t|\(NSEvent.ModifierFlags.command.rawValue)": "newPage:",
        "+|\(NSEvent.ModifierFlags.command.rawValue)": "newSplitPane:",
        "d|\(NSEvent.ModifierFlags.command.rawValue)": "togglePin:",
        "d|\(NSEvent.ModifierFlags([.command, .shift]).rawValue)": "toggleEssentials:",
        "w|\(NSEvent.ModifierFlags.command.rawValue)": "closeTab:",
        "c|\(NSEvent.ModifierFlags([.command, .shift]).rawValue)": "copyPageURL:",
        "c|\(NSEvent.ModifierFlags([.command, .shift, .option]).rawValue)": "copyPageURL:#1",
        "r|\(NSEvent.ModifierFlags.command.rawValue)": "reloadPage:",
        "m|\(NSEvent.ModifierFlags([.command, .shift]).rawValue)": "toggleMute:",
        "-|\(NSEvent.ModifierFlags([.control, .shift]).rawValue)": "removeSplitPane:",
        "u|\(NSEvent.ModifierFlags([.command, .option]).rawValue)": "unsplit:",
    ]

    /// The key an item shows: its action's current key when the app supplies the table, else the default.
    func shownKey(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        guard !key.isEmpty, let shortcutKey, let id = Self.shortcutIDs["\(key)|\(modifiers.rawValue)"] else {
            return (key, key.isEmpty ? [] : modifiers)
        }
        return shortcutKey(id)
    }

    func action(_ title: String, symbol: Symbol? = nil, key: String = "", modifiers: NSEvent.ModifierFlags = [.command],
                enabled: Bool = true, _ handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let target = MenuAction(handler)
        let shown = shownKey(key, modifiers)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: shown.key)
        item.keyEquivalentModifierMask = shown.modifiers
        item.target = target
        item.representedObject = target
        item.image = symbol?.image()
        item.isEnabled = enabled
        return item
    }

    /// A command that a later phase implements: shown, disabled, phase in the tooltip.
    func later(_ title: String, symbol: Symbol? = nil, phase: String, key: String = "",
               modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let shown = shownKey(key, modifiers)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: shown.key)
        item.keyEquivalentModifierMask = shown.modifiers
        item.image = symbol?.image()
        item.isEnabled = false
        item.toolTip = "Arrives in Phase \(phase)"
        return item
    }

    // MARK: Commands

    func pin(_ id: UUID) {
        try? sidebar.move(id, to: .pinned(space: tree.spaceID, folder: nil), at: sidebar.pinned(space: tree.spaceID).count)
    }

    func unpin(_ id: UUID) {
        try? sidebar.move(id, to: .today(space: tree.spaceID, window: windowID), at: 0)
    }

    func addToEssentials(_ id: UUID) {
        guard let space = tree.space else { return }
        do {
            try sidebar.move(id, to: .essentials(profile: space.profileID), at: sidebar.essentials(profile: space.profileID).count)
        } catch {
            toasts?.show(Toast(id: "essentials-full", symbol: .info, message: "Essentials are full (\(EntryRules.essentialsCap)/\(EntryRules.essentialsCap))"))
        }
    }

    func removeFromEssentials(_ id: UUID) {
        try? sidebar.move(id, to: .today(space: tree.spaceID, window: windowID), at: 0)
    }

    func move(_ id: UUID, toSpace space: UUID) {
        moveEntries([id], toSpace: space)
    }

    func moveToFolder(_ id: UUID, folder: UUID?) {
        let count = sidebar.pinned(space: tree.spaceID, folder: folder).count
        do {
            try sidebar.move(id, to: .pinned(space: tree.spaceID, folder: folder), at: count)
            if let folder, sidebar.entry(folder)?.isCollapsed == true { try? sidebar.setFolderCollapsed(folder, false) }
        } catch .folder(.tooDeep(let max)) {
            toasts?.show(Toast(id: "folder-depth", symbol: .info, message: "Folders nest at most \(max) deep"))
        } catch {}
    }

    /// A new folder (named "New Folder", renamed inline right away).
    func newFolder(parent: UUID?) {
        guard let folder = try? sidebar.addFolder(name: CommandName.newFolder, space: tree.spaceID, parent: parent) else { return }
        if let parent, sidebar.entry(parent)?.isCollapsed == true { try? sidebar.setFolderCollapsed(parent, false) }
        if tree.space?.pinnedCollapsed == true { togglePinnedCollapsed() }
        beginRename(folder.id)
    }

    /// "New Folder with Tab": the entry becomes pinned inside a new folder.
    func newFolderWithTab(_ id: UUID) {
        guard let entry = sidebar.entry(id) else { return }
        let parent = entry.kind == .pinned ? entry.folderID : nil
        let index = entry.kind == .pinned ? entry.position : nil
        guard let folder = try? sidebar.addFolder(name: CommandName.newFolder, space: tree.spaceID, parent: parent, at: index) else { return }
        try? sidebar.move(id, to: .pinned(space: tree.spaceID, folder: folder.id), at: 0)
        if tree.space?.pinnedCollapsed == true { togglePinnedCollapsed() }
        beginRename(folder.id)
    }

    /// A Today tab with the entry's current page, at the top of Today (or
    /// right below a Today original), selected.
    func duplicate(_ id: UUID) {
        guard let entry = sidebar.entry(id), let url = entry.currentURL else { return }
        let index = entry.kind == .today ? entry.position + 1 : 0
        let title = entry.kind == .today ? entry.liveTitle : (entry.liveTitle ?? entry.storedTitle)
        guard let copy = try? sidebar.addEntry(.today, url: url, title: title, space: tree.spaceID, window: windowID, at: index) else { return }
        select(copy.id)
    }

    /// Close Tabs Below / Close Other Tabs / a group's Close: removes Today
    /// tabs, Undo toast. The selection moves to `kept`, or the MRU fallback.
    func closeToday(_ ids: [UUID], keeping kept: UUID?) {
        guard !ids.isEmpty else { return }
        if let selected = selectedEntryID, ids.contains(selected) {
            if let kept {
                select(kept)
            } else {
                let next = sidebar.mruOrder(space: tree.spaceID, window: windowID).first { !ids.contains($0.id) && $0.kind != .folder && $0.lastActiveAt != nil }
                select(next?.id)
            }
        }
        var removed: [RemovedEntry] = []
        for id in ids {
            host?.unload(id)
            if let item = try? sidebar.remove(id) { removed.append(item) }
        }
        closedTabs.push(.removed(removed))
        toasts?.show(Toast(id: "tabs-closed", symbol: .clearToday,
                           message: removed.count == 1 ? "1 tab closed" : "\(removed.count) tabs closed",
                           action: .init(title: "Undo") { [weak self] in self?.sidebar.restore(removed) },
                           duration: Timing.undoToast))
    }

    /// "Archive Tab", "Archive Tabs Below", "Archive N Tabs" (spec §A.8):
    /// the tabs go to the Archive (reason `manual`) with an Undo toast; the
    /// selection moves as `closeToday`'s does.
    func archiveToday(_ ids: [UUID], keeping kept: UUID?) {
        guard !ids.isEmpty else { return }
        if let selected = selectedEntryID, ids.contains(selected) {
            if let kept {
                select(kept)
            } else {
                let next = sidebar.mruOrder(space: tree.spaceID, window: windowID).first { !ids.contains($0.id) && $0.kind != .folder && $0.lastActiveAt != nil }
                select(next?.id)
            }
        }
        for id in ids { host?.unload(id) }
        let removed = sidebar.archive(ids, reason: .manual)
        guard !removed.isEmpty else { return }
        closedTabs.push(.removed(removed))
        toasts?.show(Toast(id: "tabs-archived", symbol: .archive,
                           message: removed.count == 1 ? "1 tab archived" : "\(removed.count) tabs archived",
                           action: .init(title: "Undo") { [weak self] in self?.sidebar.restore(removed) },
                           duration: Timing.undoToast))
    }

    func deleteFolder(_ id: UUID) {
        guard let folder = sidebar.entry(id) else { return }
        let children = sidebar.pinned(space: tree.spaceID, folder: id)
        guard !children.isEmpty, let window = outline.window else {
            removeEntry(id, undoable: true)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete “\(EntryLabel.title(folder))”?"
        alert.informativeText = children.count == 1
            ? "Its tab moves out of the folder."
            : "Its \(children.count) items move out of the folder."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.removeEntry(id, undoable: true)
        }
    }

    /// Every non-folder entry under a folder.
    func descendants(of folder: UUID) -> [Entry] {
        sidebar.pinned(space: tree.spaceID, folder: folder).flatMap { child in
            child.kind == .folder ? descendants(of: child.id) : [child]
        }
    }

    // MARK: Popovers (Edit Pinned URL…, renaming an Essential)

    func editPinnedURL(_ id: UUID) {
        guard let entry = sidebar.entry(id), let (view, rect) = anchor(for: id) else { return }
        TextEntryPopover.show(title: CommandName.editPinnedURL.replacingOccurrences(of: "…", with: ""), text: entry.storedURL ?? "",
                              relativeTo: rect, of: view) { [weak self] text in
            guard let self else { return nil }
            guard let url = URLFixup.url(from: text) else { return "That doesn’t look like a valid URL." }
            try? sidebar.setStoredURL(id, url)
            pageStateDidChange([id])
            toasts?.show(Toast(id: "pinned-url", symbol: .success, message: "Pinned URL updated"))
            return nil
        }
    }

    func renameWithPopover(_ id: UUID) {
        guard let entry = sidebar.entry(id), let (view, rect) = anchor(for: id) else { return }
        TextEntryPopover.show(title: "Rename", text: EntryLabel.title(entry), relativeTo: rect, of: view) { [weak self] text in
            self?.renameEnded(id, label: text.trimmingCharacters(in: .whitespacesAndNewlines), committed: true)
            return nil
        }
    }

    /// Where a popover for an entry points: its tile or its row.
    private func anchor(for id: UUID) -> (NSView, NSRect)? {
        if let tile = grid.tile(for: id) { return (tile, tile.bounds) }
        guard let node = tree.displayedNode(for: id) else { return nil }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return nil }
        return (outline, SidebarRowView.pillRect(in: outline.rect(ofRow: row)))
    }
}

/// Keeps a closure alive as a menu item's target.
final class MenuAction: NSObject {
    let handler: @MainActor () -> Void
    init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

private extension NSMenuItem {
    func retitled(_ title: String) -> NSMenuItem {
        self.title = title
        keyEquivalent = ""
        return self
    }
}

/// A one-field popover: Enter validates (`commit` returns an error message
/// to show inline, or `nil` to close), Esc cancels.
final class TextEntryPopover: NSViewController, NSTextFieldDelegate {
    private let field = NSTextField()
    private let errorLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private var commit: (String) -> String? = { _ in nil }
    private weak var popover: NSPopover?

    static func show(title: String, text: String, relativeTo rect: NSRect, of view: NSView,
                     commit: @escaping (String) -> String?) {
        let controller = TextEntryPopover()
        controller.commit = commit
        controller.titleLabel.stringValue = title
        controller.field.stringValue = text
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        controller.popover = popover
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
        controller.view.window?.makeFirstResponder(controller.field)
        controller.field.currentEditor()?.selectAll(nil)
    }

    override func loadView() {
        titleLabel.font = Typography.spaceTitle
        field.font = Typography.row
        field.delegate = self
        field.setAccessibilityIdentifier("popover-field")
        errorLabel.font = Typography.secondary
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        let stack = NSStackView(views: [titleLabel, field, errorLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Spacing.s
        stack.edgeInsets = NSEdgeInsets(top: Spacing.m, left: Spacing.m, bottom: Spacing.m, right: Spacing.m)
        field.widthAnchor.constraint(equalToConstant: SidebarMetrics.popoverFieldWidth).isActive = true
        view = stack
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            if let error = commit(field.stringValue) {
                errorLabel.stringValue = error
                errorLabel.isHidden = false
            } else {
                popover?.close()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            popover?.close()
            return true
        default:
            return false
        }
    }
}
