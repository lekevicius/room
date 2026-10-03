import AppKit
import Sidebar
import UIKitCore

/// The main menu, built in code. Phase 2.8 replaces this with the full command set.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Room", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Room", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        // No ⌥⌘H: docs/shortcuts.md gives it to the split layout (Zen); it matched here first (2.7b spike).
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Room", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu: appMenu, title: "Room")

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(AppDelegate.newPage(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Open Location…", action: #selector(AppDelegate.openLocation(_:)), keyEquivalent: "l")
        fileMenu.addItem(withTitle: CommandName.newSpace, action: #selector(AppDelegate.newSpace(_:)), keyEquivalent: "")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: CommandName.closeTab, action: #selector(AppDelegate.closeTab(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: CommandName.reopenClosedTab, action: #selector(AppDelegate.reopenClosedTab(_:)),
                         keyEquivalent: "T")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "W")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Print…", action: #selector(AppDelegate.printPage(_:)), keyEquivalent: "p")
        main.addItem(submenu: fileMenu, title: "File")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        // Copy URL / as Markdown (spec §G; shifted keys name the shifted character, see the Tab menu).
        editMenu.addItem(withTitle: CommandName.copyURL, action: #selector(AppDelegate.copyPageURL(_:)), keyEquivalent: "C")
        let markdown = editMenu.addItem(withTitle: CommandName.copyMarkdown, action: #selector(AppDelegate.copyPageURL(_:)),
                                        keyEquivalent: "C")
        markdown.keyEquivalentModifierMask = [.command, .shift, .option]
        markdown.tag = 1
        editMenu.addItem(.separator())
        let findMenu = NSMenu(title: "Find")
        findMenu.addItem(withTitle: "Find…", action: #selector(AppDelegate.showFindBar(_:)), keyEquivalent: "f")
        findMenu.addItem(withTitle: "Find Next", action: #selector(AppDelegate.findNext(_:)), keyEquivalent: "g").tag = 1
        findMenu.addItem(withTitle: "Find Previous", action: #selector(AppDelegate.findNext(_:)), keyEquivalent: "G").tag = -1
        editMenu.addItem(submenu: findMenu, title: "Find")
        main.addItem(submenu: editMenu, title: "Edit")

        let viewMenu = NSMenu(title: "View")
        // Through the app delegate to the window's controller, like every other item: in the responder
        // chain RoomWindow answers `toggleSidebar:` itself (AppKit's sidebar action) and disables it (2.7b).
        viewMenu.addItem(withTitle: "Hide Sidebar", action: #selector(AppDelegate.hideOrShowSidebar(_:)), keyEquivalent: "s")
        // Pins the hidden sidebar's overlay open (spec §E; docs/shortcuts.md "Pin overlay sidebar open").
        let pin = viewMenu.addItem(withTitle: "Keep Sidebar Open", action: #selector(AppDelegate.keepSidebarOpen(_:)), keyEquivalent: "s")
        pin.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(withTitle: "Show Toolbar", action: #selector(AppDelegate.toggleToolbar(_:)), keyEquivalent: "")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(AppDelegate.zoomPage(_:)), keyEquivalent: "0").tag = 0
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(AppDelegate.zoomPage(_:)), keyEquivalent: "=").tag = 1
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(AppDelegate.zoomPage(_:)), keyEquivalent: "-").tag = -1
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Reload Page", action: #selector(AppDelegate.reloadPage(_:)), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Back", action: #selector(AppDelegate.goBack(_:)), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "Forward", action: #selector(AppDelegate.goForward(_:)), keyEquivalent: "]")
        viewMenu.addItem(withTitle: "Show History", action: #selector(AppDelegate.showHistory(_:)), keyEquivalent: "y")
        viewMenu.addItem(withTitle: "Downloads", action: #selector(AppDelegate.showDownloads(_:)), keyEquivalent: "J")
        viewMenu.addItem(.separator())
        let devTools = viewMenu.addItem(withTitle: "Developer Tools", action: #selector(AppDelegate.toggleDevTools(_:)), keyEquivalent: "i")
        devTools.keyEquivalentModifierMask = [.command, .option]
        let console = viewMenu.addItem(withTitle: "JavaScript Console", action: #selector(AppDelegate.showJavaScriptConsole(_:)),
                                       keyEquivalent: "j")
        console.keyEquivalentModifierMask = [.command, .option]
        let inspect = viewMenu.addItem(withTitle: "Inspect Elements", action: #selector(AppDelegate.inspectElements(_:)), keyEquivalent: "c")
        inspect.keyEquivalentModifierMask = [.command, .option]
        main.addItem(submenu: viewMenu, title: "View")

        // Sidebar and tab commands (Phases 2.2, 2.3); Phase 2.8 builds the full menu set.
        let tabMenu = NSMenu(title: "Tab")
        // Shifted shortcuts name the shifted character (⇧⌘] is "}", ⇧⌘T is "T"): AppKit matches the
        // event's characters, so "t" with a Shift mask never matches a real ⇧⌘T (checked in 2.3).
        let next = tabMenu.addItem(withTitle: CommandName.nextTab, action: #selector(AppDelegate.selectAdjacentTab(_:)), keyEquivalent: "}")
        next.tag = 1
        let previous = tabMenu.addItem(withTitle: CommandName.previousTab, action: #selector(AppDelegate.selectAdjacentTab(_:)),
                                       keyEquivalent: "{")
        previous.tag = -1
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!), up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        let nextInSidebar = tabMenu.addItem(withTitle: "Next Tab in Sidebar", action: #selector(AppDelegate.selectAdjacentTab(_:)),
                                            keyEquivalent: down)
        nextInSidebar.keyEquivalentModifierMask = [.command, .option]
        nextInSidebar.tag = 1
        let previousInSidebar = tabMenu.addItem(withTitle: "Previous Tab in Sidebar", action: #selector(AppDelegate.selectAdjacentTab(_:)),
                                                keyEquivalent: up)
        previousInSidebar.keyEquivalentModifierMask = [.command, .option]
        previousInSidebar.tag = -1
        tabMenu.addItem(.separator())
        for digit in 1...9 {
            let item = tabMenu.addItem(withTitle: digit == 9 ? "Last Tab" : "Tab \(digit)", action: #selector(AppDelegate.selectTabByNumber(_:)),
                                       keyEquivalent: "\(digit)")
            item.tag = digit
        }
        tabMenu.addItem(.separator())
        tabMenu.addItem(withTitle: CommandName.muteTab, action: #selector(AppDelegate.toggleMute(_:)), keyEquivalent: "M")
        tabMenu.addItem(.separator())
        tabMenu.addItem(withTitle: "Pin Tab", action: #selector(AppDelegate.togglePin(_:)), keyEquivalent: "d")
        tabMenu.addItem(withTitle: "Add to Essentials", action: #selector(AppDelegate.toggleEssentials(_:)), keyEquivalent: "D")
        tabMenu.addItem(.separator())
        tabMenu.addItem(withTitle: "Clear Today Tabs", action: #selector(AppDelegate.clearTodayTabs(_:)), keyEquivalent: "K")
        tabMenu.addItem(.separator())
        // Peek (spec §I.6; docs/shortcuts.md: ⌘O, ⇧⌘O; Open File stays menu-only).
        tabMenu.addItem(withTitle: "Open Peek as Tab", action: #selector(AppDelegate.expandPeek(_:)), keyEquivalent: "o")
        tabMenu.addItem(withTitle: "Open Peek in Split View", action: #selector(AppDelegate.splitPeek(_:)), keyEquivalent: "O")
        main.addItem(submenu: tabMenu, title: "Tab")

        // Split view (spec §D, docs/shortcuts.md). Page-first keys; shifted keys name the shifted character.
        let splitMenu = NSMenu(title: "Split")
        splitMenu.addItem(withTitle: CommandName.newSplit, action: #selector(AppDelegate.newSplitPane(_:)), keyEquivalent: "+")
        let alias = splitMenu.addItem(withTitle: "New Split View (⌃⇧=)", action: #selector(AppDelegate.newSplitPane(_:)), keyEquivalent: "+")
        alias.keyEquivalentModifierMask = [.control]
        alias.isHidden = true
        alias.allowsKeyEquivalentWhenHidden = true
        let removePane = splitMenu.addItem(withTitle: "Remove Split Pane", action: #selector(AppDelegate.removeSplitPane(_:)), keyEquivalent: "_")
        removePane.keyEquivalentModifierMask = [.control]
        splitMenu.addItem(.separator())
        for (title, key, tag) in [(CommandName.layoutGrid, "g", 0), (CommandName.layoutSideBySide, "v", 1), (CommandName.layoutStacked, "h", 2)] {
            let item = splitMenu.addItem(withTitle: title, action: #selector(AppDelegate.setSplitLayout(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command, .option]
            item.tag = tag
        }
        let unsplit = splitMenu.addItem(withTitle: "Unsplit", action: #selector(AppDelegate.unsplit(_:)), keyEquivalent: "u")
        unsplit.keyEquivalentModifierMask = [.command, .option]
        splitMenu.addItem(.separator())
        // ⌃⇧1…4 arrive as "!", "@", "#", "$" on the US layout (Shift is in the characters).
        for (number, key) in zip(1...4, ["!", "@", "#", "$"]) {
            let item = splitMenu.addItem(withTitle: "Focus Pane \(number)", action: #selector(AppDelegate.focusSplitPane(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = [.control]
            item.tag = number
        }
        let nextPane = splitMenu.addItem(withTitle: "Next Pane", action: #selector(AppDelegate.focusAdjacentPane(_:)), keyEquivalent: "}")
        nextPane.keyEquivalentModifierMask = [.control]
        nextPane.tag = 1
        let previousPane = splitMenu.addItem(withTitle: "Previous Pane", action: #selector(AppDelegate.focusAdjacentPane(_:)), keyEquivalent: "{")
        previousPane.keyEquivalentModifierMask = [.control]
        previousPane.tag = -1
        main.addItem(submenu: splitMenu, title: "Split")

        // Spaces (Phase 2.5, spec §B): ⌃1…⌃9 and ⌃0, ⌥⌘→ / ⌥⌘← wrapping.
        let spacesMenu = NSMenu(title: "Spaces")
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!), left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let nextSpace = spacesMenu.addItem(withTitle: SpaceCommandName.nextSpace, action: #selector(AppDelegate.selectAdjacentSpace(_:)),
                                           keyEquivalent: right)
        nextSpace.keyEquivalentModifierMask = [.command, .option]
        nextSpace.tag = 1
        let previousSpace = spacesMenu.addItem(withTitle: SpaceCommandName.previousSpace,
                                               action: #selector(AppDelegate.selectAdjacentSpace(_:)), keyEquivalent: left)
        previousSpace.keyEquivalentModifierMask = [.command, .option]
        previousSpace.tag = -1
        spacesMenu.addItem(.separator())
        for digit in [1, 2, 3, 4, 5, 6, 7, 8, 9, 0] {
            let item = spacesMenu.addItem(withTitle: "Space \(digit == 0 ? 10 : digit)", action: #selector(AppDelegate.selectSpaceByNumber(_:)),
                                          keyEquivalent: "\(digit)")
            item.keyEquivalentModifierMask = [.control]
            item.tag = digit
        }
        spacesMenu.addItem(.separator())
        spacesMenu.addItem(withTitle: CommandName.newSpace, action: #selector(AppDelegate.newSpace(_:)), keyEquivalent: "")
        main.addItem(submenu: spacesMenu, title: "Spaces")

        #if DEBUG
        // The page lifecycle checks (2.3). The Chapter 1 debug toolbar is gone: the palette opens URLs (2.4).
        let debugMenu = NSMenu(title: "Debug")
        debugMenu.addItem(withTitle: "Simulate Memory Pressure", action: #selector(AppDelegate.simulateMemoryPressure(_:)), keyEquivalent: "")
        debugMenu.addItem(withTitle: "Discard Background Pages", action: #selector(AppDelegate.discardBackgroundPages(_:)), keyEquivalent: "")
        main.addItem(submenu: debugMenu, title: "Debug")
        #endif

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(submenu: windowMenu, title: "Window")
        NSApp.windowsMenu = windowMenu

        return main
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
