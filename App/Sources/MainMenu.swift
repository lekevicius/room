import AppKit
import UIKitCore

/// The main menu, built from `MainMenuTable` (UIKitCore), the one table
/// `docs/shortcuts.md` is checked against (ROADMAP 2.8 task 1). Room's
/// commands target the app delegate, which validates every one of them.
enum MainMenu {
    static func make(target: AppDelegate) -> NSMenu {
        var debug: [MenuNode] = []
        #if DEBUG
        // The page lifecycle checks (2.3), results in the log.
        debug = [
            .item(MenuItemSpec("Simulate Memory Pressure", "simulateMemoryPressure:")),
            .item(MenuItemSpec("Discard Background Pages", "discardBackgroundPages:")),
        ]
        #endif
        let menu = MainMenuBuilder.make(MainMenuTable.menus(debug: debug), appTarget: target)
        NSApp.servicesMenu = menu.items.first?.submenu?.item(withTitle: "Services")?.submenu
        NSApp.windowsMenu = menu.item(withTitle: "Window")?.submenu
        NSApp.helpMenu = menu.item(withTitle: "Help")?.submenu
        return menu
    }
}
