import AppKit
import Design
import Omnibox
import Sidebar

/// The palette's commands (spec §C list, `CommandRegistry`): which can run
/// now and what each does. Commands of later phases (screenshot, archive,
/// private window, routing) are not offered until
/// their phase gives them something to do.
extension AppDelegate {
    func paletteCommands() -> [OmniboxCommand] {
        guard let sidebar, let tabs else { return [] }
        var commands: [OmniboxCommand] = []
        func add(_ command: OmniboxCommand, _ symbol: Symbol, title: String? = nil, when available: Bool = true) {
            if available { commands.append(command.with(title: title, symbol: symbol.name, shortcut: paletteShortcut(for: command.id))) }
        }
        add(CommandRegistry.addToEssentials, .essential, title: sidebar.essentialsCommandTitle, when: sidebar.essentialsCommandTitle != nil)
        add(CommandRegistry.closeTab, .closeTab, when: sidebar.canCloseCommandTargets)
        add(CommandRegistry.copyURL, .copyURL, when: sidebar.selectedHasURL)
        add(CommandRegistry.copyMarkdown, .copyMarkdown, when: sidebar.selectedHasURL)
        add(CommandRegistry.duplicateTab, .duplicate, when: sidebar.selectedHasURL)
        add(CommandRegistry.findInPage, .find, when: tabs.current != nil)
        add(CommandRegistry.importFromBrowser, .importData)
        add(CommandRegistry.print, .print, when: tabs.current != nil)
        add(CommandRegistry.newFolder, .newFolder)
        add(CommandRegistry.newSplitView, .newSplit, when: sidebar.selectedEntryID != nil)
        add(CommandRegistry.unsplit, .newSplit, when: sidebar.selectedSplit != nil)
        add(CommandRegistry.pinTab, .pin, title: sidebar.pinCommandTitle, when: sidebar.pinCommandTitle != nil)
        add(CommandRegistry.reload, .reload, when: tabs.current != nil)
        add(CommandRegistry.reloadWithoutCache, .reload, when: tabs.current != nil)
        add(CommandRegistry.reopenClosedTab, .restore, when: sidebar.canReopenClosedTab)
        add(CommandRegistry.resetPinnedTab, .resetPinned, when: sidebar.canResetSelected)
        add(CommandRegistry.settings, .settings)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        add(CommandRegistry.lightAppearance, .appearance, when: NSApp.appearance == nil || dark)
        add(CommandRegistry.darkAppearance, .appearance, when: NSApp.appearance == nil || !dark)
        add(CommandRegistry.autoAppearance, .appearance, when: NSApp.appearance != nil)
        add(CommandRegistry.toggleSidebar, .toggleSidebar)
        add(CommandRegistry.unloadTab, .unload, when: sidebar.selectedHasPage)
        add(CommandRegistry.newSpace, .newSpace)
        add(CommandRegistry.nextSpace, .space, when: sidebar.otherSpaces.count > 0)
        add(CommandRegistry.previousSpace, .space, when: sidebar.otherSpaces.count > 0)
        for space in sidebar.otherSpaces {
            add(CommandRegistry.focus(space: space.id, name: space.name), .space)
            add(CommandRegistry.move(toSpace: space.id, name: space.name), .moveTo, when: sidebar.canMoveSelected)
        }
        return commands.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func runPaletteCommand(_ id: String) {
        guard let sidebar, let tabs else { return }
        if let target = CommandRegistry.space(in: id) {
            if target.focus { sidebar.showSpace(target.space) } else { sidebar.moveSelected(toSpace: target.space) }
            return
        }
        switch id {
        case CommandRegistry.addToEssentials.id: sidebar.toggleEssentials()
        case CommandRegistry.closeTab.id: sidebar.closeCommandTargets()
        case CommandRegistry.copyURL.id: sidebar.copySelectedURL(markdown: false)
        case CommandRegistry.copyMarkdown.id: sidebar.copySelectedURL(markdown: true)
        case CommandRegistry.duplicateTab.id: sidebar.duplicateSelected()
        case CommandRegistry.findInPage.id: find?.showFindBar()
        // After the palette has closed: the sheet attaches to the window.
        case CommandRegistry.importFromBrowser.id: DispatchQueue.main.async { self.showImportSheet(nil) }
        case CommandRegistry.print.id: tabs.current?.print()
        case CommandRegistry.newFolder.id: sidebar.newFolderCommand()
        // After the palette has closed: the new pane opens it again on itself.
        case CommandRegistry.newSplitView.id: DispatchQueue.main.async { sidebar.newSplitPane() }
        case CommandRegistry.unsplit.id: sidebar.unsplit()
        case CommandRegistry.pinTab.id: sidebar.togglePin()
        case CommandRegistry.reload.id: tabs.current?.reload()
        case CommandRegistry.reloadWithoutCache.id: tabs.current?.reloadIgnoringCache()
        case CommandRegistry.reopenClosedTab.id: sidebar.reopenClosedTab()
        case CommandRegistry.resetPinnedTab.id: sidebar.resetSelected()
        case CommandRegistry.settings.id: showSettings(nil)
        case CommandRegistry.lightAppearance.id: NSApp.appearance = NSAppearance(named: .aqua)
        case CommandRegistry.darkAppearance.id: NSApp.appearance = NSAppearance(named: .darkAqua)
        case CommandRegistry.autoAppearance.id: NSApp.appearance = nil
        case CommandRegistry.toggleSidebar.id: windowController?.toggleSidebarVisibility(nil)
        case CommandRegistry.unloadTab.id: sidebar.unloadSelected()
        case CommandRegistry.newSpace.id: newSpace(nil)
        case CommandRegistry.nextSpace.id: sidebar.showAdjacentSpace(1)
        case CommandRegistry.previousSpace.id: sidebar.showAdjacentSpace(-1)
        default: NSLog("Room: palette command \(id) has no action")
        }
    }
}
