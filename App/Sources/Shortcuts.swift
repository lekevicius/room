import AppKit
import Card
import Omnibox
import Store
import UIKitCore

/// Shortcut remapping (ROADMAP 4.4a task 1): the user's `ShortcutTable` from
/// `Settings.shortcutOverrides`, applied to the menu bar in place, the key
/// router's reserved set, the sidebar's context menus and the palette's
/// command hints; again whenever the overrides change.
extension AppDelegate {
    /// The palette's commands and the menu actions whose keys their rows show.
    static let paletteCommandActions: [String: String] = [
        CommandRegistry.addToEssentials.id: "toggleEssentials:",
        CommandRegistry.closeTab.id: "closeTab:",
        CommandRegistry.copyURL.id: "copyPageURL:",
        CommandRegistry.copyMarkdown.id: "copyPageURL:#1",
        CommandRegistry.duplicateTab.id: "duplicateSelected:",
        CommandRegistry.findInPage.id: "showFindBar:",
        CommandRegistry.print.id: "printPage:",
        CommandRegistry.readerMode.id: "readerMode:",
        CommandRegistry.captureScreenshot.id: "captureScreenshot:",
        CommandRegistry.savePage.id: "savePageAs:",
        CommandRegistry.viewSource.id: "viewPageSource:",
        CommandRegistry.newSplitView.id: "newSplitPane:",
        CommandRegistry.unsplit.id: "unsplit:",
        CommandRegistry.pinTab.id: "togglePin:",
        CommandRegistry.reload.id: "reloadPage:",
        CommandRegistry.reloadWithoutCache.id: "reloadIgnoringCache:",
        CommandRegistry.reopenClosedTab.id: "reopenClosedTab:",
        CommandRegistry.resetPinnedTab.id: "resetSelected:",
        CommandRegistry.settings.id: "showSettings:",
        CommandRegistry.toggleSidebar.id: "hideOrShowSidebar:",
        CommandRegistry.unloadTab.id: "unloadSelected:",
        CommandRegistry.newSpace.id: "newSpace:",
        CommandRegistry.nextSpace.id: "selectAdjacentSpace:#1",
        CommandRegistry.previousSpace.id: "selectAdjacentSpace:#-1",
    ].merging(SettingsWindowController.Section.allCases.indices.map { index in
        (CommandRegistry.settingsSection(index, title: "").id, "showSettingsSection:#\(index + 1)")
    }, uniquingKeysWith: { first, _ in first })

    /// A palette command's key as the menu shows it, or nil.
    func paletteShortcut(for commandID: String) -> String? {
        guard let action = Self.paletteCommandActions[commandID], let key = shortcutTable.key(for: action) else { return nil }
        return key.description
    }

    /// Applies the table now and again when the overrides change (`MainActorWeak`: the
    /// `@Sendable` onChange must not capture self, AGENTS.md).
    func observeShortcuts() {
        guard let settings = store?.settings else { return }
        let overrides = withObservationTracking {
            settings.settings.shortcutOverrides
        } onChange: { [weakSelf = MainActorWeak(self)] in
            Task { @MainActor in weakSelf.value?.observeShortcuts() }
        }
        applyShortcuts(ShortcutTable(overrides: overrides))
    }

    private func applyShortcuts(_ table: ShortcutTable) {
        let start = ContinuousClock.now
        shortcutTable = table
        if let menu = NSApp.mainMenu {
            let changed = MainMenuBuilder.apply(table, to: menu)
            if changed > 0 { NSLog("Room: shortcuts: %ld menu keys changed, %ld overrides", changed, table.overrides.count) }
        }
        let elapsed = ContinuousClock.now - start
        lastShortcutsApplyMilliseconds = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        for session in windows.all { applyShortcutKeys(to: session) }
        // The empty card names New Tab's key as it is now (5.6a).
        CardEmptyStateView.newTabKey = table.key(for: "newPage:")?.description
    }

    /// One window's share of the table (4.8a: each window's key router and sidebar menus).
    func applyShortcutKeys(to session: WindowSession) {
        session.pageDelegate?.reservedKeys = shortcutTable.reservedKeys
        session.sidebar?.shortcutKey = { [weakSelf = MainActorWeak(self)] id in
            guard let key = weakSelf.value?.shortcutTable.key(for: id) else { return ("", []) }
            // Context menus only draw the key (B-37's glyphs).
            return MenuKey.display(for: key)
        }
    }
}
