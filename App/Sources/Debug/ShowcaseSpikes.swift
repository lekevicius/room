#if DEBUG
import AppKit
import Engine
import Model
import Store

/// The website's captures (`Website/capture/capture.sh`): `-RoomSidebarFixture showcase`
/// seeds four themed spaces of good-looking pages, and `-RoomSpike showcase` stages each
/// scene the site shows, light and dark, asking the script for a window-server capture
/// (`capture: <scene>-<appearance>`, the handshake of `requestCapture`).
///
/// - `-RoomShowcaseOnly hero,palette` limits the scenes.
/// - `-RoomShowcaseSize 1440x900` sets the window's content size (default 1440×900).
/// - `-RoomShowcaseAppearances light` limits the appearances (default `light,dark`).
/// - `-RoomShowcaseStage <clip>` (with `-RoomSpikeKeepRunning YES`, `Website/capture/record.sh`):
///   no captures; after the warm-up the clip's first state is set up in the first appearance,
///   `ready: <clip>` is written, and Room stays open for `room-record` to play the clip's script.
///
/// Every page gets `tidy` after it loads: consent banners hidden (captures are made from
/// the EU), the page scrolled to its scene's offset.
extension SidebarFixtures {
    /// One showcase page: where it goes and what it is called in the sidebar.
    struct ShowcasePage {
        let kind: EntryKind
        let url: String
        let title: String
        var folder: String?
    }

    static let showcaseEssentials: [(String, String)] = [
        ("https://www.figma.com", "Figma"), ("https://linear.app", "Linear"), ("https://github.com", "GitHub"),
        ("https://music.apple.com", "Apple Music"), ("https://www.are.na", "Are.na"), ("https://www.notion.so", "Notion"),
    ]

    /// Space name → (SF Symbol, theme colour, algorithm, opacity, second profile, pages).
    static let showcaseSpaces: [(name: String, icon: String, colour: String, algorithm: ThemeAlgorithm, opacity: Double, work: Bool,
                                 pages: [ShowcasePage])] = [
        ("Studio", "paintpalette", "#E8836A", .analogous, 0.55, false, [
            ShowcasePage(kind: .pinned, url: "https://www.artic.edu/collection", title: "Art Institute of Chicago"),
            ShowcasePage(kind: .pinned, url: "https://www.cosmos.so", title: "Cosmos", folder: "Inspiration"),
            ShowcasePage(kind: .pinned, url: "https://godly.website", title: "Godly", folder: "Inspiration"),
            ShowcasePage(kind: .pinned, url: "https://minimal.gallery", title: "Minimal Gallery", folder: "Inspiration"),
            ShowcasePage(kind: .pinned, url: "https://fontsinuse.com", title: "Fonts In Use", folder: "Type"),
            ShowcasePage(kind: .pinned, url: "https://www.typewolf.com", title: "Typewolf", folder: "Type"),
            ShowcasePage(kind: .today, url: "https://www.artic.edu/artworks/27992/a-sunday-on-la-grande-jatte-1884",
                         title: "A Sunday on La Grande Jatte"),
            ShowcasePage(kind: .today, url: "https://en.wikipedia.org/wiki/Risograph", title: "Risograph - Wikipedia"),
            ShowcasePage(kind: .today, url: "https://lospec.com/palette-list", title: "Palette List | Lospec"),
            ShowcasePage(kind: .today, url: "https://www.apple.com/macbook-pro/", title: "MacBook Pro - Apple"),
        ]),
        ("Reading", "book", "#3E8E7E", .analogous, 0.5, false, [
            ShowcasePage(kind: .pinned, url: "https://www.themarginalian.org", title: "The Marginalian"),
            ShowcasePage(kind: .pinned, url: "https://publicdomainreview.org", title: "The Public Domain Review"),
            ShowcasePage(kind: .pinned, url: "https://aeon.co", title: "Aeon"),
            ShowcasePage(kind: .today, url: "https://craigmod.com/essays/fast_software/", title: "Fast Software, the Best Software"),
            ShowcasePage(kind: .today, url: "https://en.wikipedia.org/wiki/Hokusai", title: "Hokusai - Wikipedia"),
            ShowcasePage(kind: .today, url: "https://maggieappleton.com/garden-history", title: "A Brief History of Digital Gardens"),
        ]),
        ("Work", "briefcase", "#2F5FAE", .triadic, 0.6, true, [
            ShowcasePage(kind: .pinned, url: "https://developer.apple.com/design/human-interface-guidelines", title: "Human Interface Guidelines"),
            ShowcasePage(kind: .pinned, url: "https://www.swift.org/documentation/", title: "Swift Documentation"),
            ShowcasePage(kind: .today, url: "https://developer.apple.com/documentation/appkit", title: "AppKit | Apple Developer"),
            ShowcasePage(kind: .today, url: "https://www.swift.org/blog/", title: "Swift.org Blog"),
        ]),
        ("Travel", "airplane", "#E5B53A", .floating, 0.6, false, [
            ShowcasePage(kind: .pinned, url: "https://www.atlasobscura.com", title: "Atlas Obscura"),
            ShowcasePage(kind: .today, url: "https://en.wikipedia.org/wiki/Vilnius", title: "Vilnius - Wikipedia"),
            ShowcasePage(kind: .today, url: "https://en.wikipedia.org/wiki/Curonian_Spit", title: "Curonian Spit - Wikipedia"),
        ]),
    ]

    /// Essentials for the profile, then the four spaces with their folders and pages.
    /// The first space keeps its id (the window shows it) and becomes Studio.
    static func populateShowcase(_ store: RoomStore, first space: Space, window: UUID) throws {
        let sidebar = store.sidebar
        for (url, title) in showcaseEssentials {
            try sidebar.addEntry(.essential, url: url, title: title, space: space.id)
        }
        let work = workProfile(sidebar)
        for (index, spec) in showcaseSpaces.enumerated() {
            let target: Space
            if index == 0 {
                try sidebar.updateSpace(space.id) {
                    $0.name = spec.name; $0.icon = spec.icon; $0.themeColors = [spec.colour]
                    $0.themeAlgorithm = spec.algorithm; $0.themeOpacity = spec.opacity
                }
                target = sidebar.space(space.id) ?? space
            } else {
                target = try sidebar.createSpace(name: spec.name, profile: spec.work ? work.id : space.profileID, icon: spec.icon,
                                                 themeColors: [spec.colour], themeAlgorithm: spec.algorithm, themeOpacity: spec.opacity)
            }
            var folders: [String: UUID] = [:]
            var last: UUID?
            for page in spec.pages {
                var folder: UUID?
                if let name = page.folder {
                    if folders[name] == nil { folders[name] = try sidebar.addFolder(name: name, space: target.id).id }
                    folder = folders[name]
                }
                last = try sidebar.addEntry(page.kind, url: page.url, title: page.title, space: target.id, folder: folder).id
            }
            if let name = folders.keys.sorted().last, let id = folders[name] { try sidebar.setFolderCollapsed(id, true) }
            if let last {
                store.windows.select(last, space: target.id, window: window)
                try? sidebar.markActive(last)
            }
        }
    }
}

extension SpikeRunner.Context {
    private var showcaseScenes: [String] {
        let all = ["hero", "sidebar", "spaces", "palette", "peek", "split", "reader", "hidden"]
        guard let only = UserDefaults.standard.string(forKey: "RoomShowcaseOnly") else { return all }
        let wanted = Set(only.split(separator: ",").map(String.init))
        return all.filter(wanted.contains)
    }

    private var showcaseAppearances: [String] {
        (UserDefaults.standard.string(forKey: "RoomShowcaseAppearances") ?? "light,dark").split(separator: ",").map(String.init)
    }

    private func showcaseEntry(_ fragment: String) -> Entry? {
        store.entries.values.first { $0.storedURL?.contains(fragment) == true }
    }

    private func showcaseSpace(_ name: String) -> Space? { store.spaces.first { $0.name == name } }

    /// Hides consent banners and similar overlays, then scrolls to `y`.
    private func tidy(_ page: any WebContents, scrollY: Int = 0) async {
        let hide = [
            "#onetrust-consent-sdk", "#onetrust-banner-sdk", ".fc-consent-root", "#CybotCookiebotDialog", "#usercentrics-root",
            ".osano-cm-window", ".qc-cmp2-container", "#truste-consent-track", "[id^=sp_message_container]", ".cc-window", ".cky-consent-container",
            "#cookie-banner", ".cookie-banner", "[class*=CookieBanner]", "[class*=cookie-consent]", "[id*=cookie-consent]",
            "[aria-label*=cookie i][role=dialog]", "[aria-label*=consent i][role=dialog]", "#didomi-host", ".didomi-popup-open",
        ].joined(separator: ",")
        let script = """
        (() => {
          const s = document.createElement('style');
          s.textContent = `\(hide) { display: none !important; } html, body { overflow: auto !important; }`;
          document.documentElement.append(s);
          document.body && document.body.classList.remove('didomi-popup-open', 'modal-open', 'no-scroll');
          window.scrollTo(0, \(scrollY));
          return 'ok';
        })()
        """
        _ = await js(page, script)
    }

    /// Selects the entry whose URL contains `fragment` in its space and waits for its page.
    @discardableResult
    private func showcaseShow(_ fragment: String, scrollY: Int = 0) async -> (any WebContents)? {
        guard let entry = showcaseEntry(fragment) else {
            SpikeRunner.record("showcase_missing", fragment)
            return nil
        }
        if let space = entry.spaceID, space != sidebar.activeSpaceID { sidebar.showSpace(space, animated: false) }
        sidebar.select(entry.id)
        guard let page = tabs.current else { return nil }
        await waitLoaded(page, timeout: 25)
        await tidy(page, scrollY: scrollY)
        return page
    }

    private func showcaseCapture(_ scene: String) async {
        for appearance in showcaseAppearances {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            try? await Task.sleep(for: .milliseconds(700))
            await requestCapture("\(scene)-\(appearance)")
        }
    }

    func showcase() async {
        SpikeRunner.record("window_id", window.windowNumber)
        let size = (UserDefaults.standard.string(forKey: "RoomShowcaseSize") ?? "1440x900").split(separator: "x").compactMap { Double($0) }
        window.setContentSize(NSSize(width: size.first ?? 1440, height: size.last ?? 900))
        window.center()
        controller.sidebarWidth = 300
        controller.isSidebarOpen = true
        controller.activityOverride = true
        _ = await waitUntil(15) { self.sidebar.debugPreparedSpaces == self.store.spaces.count }
        guard let studio = showcaseSpace("Studio") else { return SpikeRunner.record("error", "needs -RoomSidebarFixture showcase") }

        // Warm-up: every page once, so favicons and caches are in place before the captures.
        for space in store.spaces {
            sidebar.showSpace(space.id, animated: false)
            let pages = store.entries.values.filter { $0.spaceID == space.id && $0.storedURL != nil }
            for entry in pages + (space.id == studio.id ? store.essentials(profile: space.profileID) : []) {
                sidebar.select(entry.id)
                if let page = tabs.current { await waitLoaded(page, timeout: 20) }
            }
        }
        sidebar.showSpace(studio.id, animated: false)
        try? await Task.sleep(for: .seconds(2))

        if let stage = UserDefaults.standard.string(forKey: "RoomShowcaseStage") {
            let appearance = showcaseAppearances.first ?? "light"
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            restorePaletteHooks()
            switch stage {
            case "sidebar": await showcaseShow("la-grande-jatte")
            case "peek": await showcaseShow("garden-history", scrollY: 900)
            case "split": await showcaseShow("human-interface-guidelines")
            default: await showcaseShow("Risograph")
            }
            try? await Task.sleep(for: .seconds(1))
            SpikeRunner.record("ready", stage)
            return
        }

        for scene in showcaseScenes {
            switch scene {
            case "hero":
                await showcaseShow("la-grande-jatte", scrollY: 0)
            case "sidebar":
                await showcaseShow("godly.website")
            case "spaces":
                // The slide between two spaces, slowed and caught near its middle: both lists, two tints.
                await showcaseShow("Hokusai")
                if let reading = showcaseSpace("Reading") {
                    sidebar.showSpace(studio.id, animated: false)
                    await showcaseShow("Risograph")
                    for appearance in showcaseAppearances {
                        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                        sidebar.showSpace(studio.id, animated: false)
                        try? await Task.sleep(for: .milliseconds(800))
                        sidebar.debugSetSlideSlowdown(30)
                        sidebar.showSpace(reading.id)
                        try? await Task.sleep(for: .milliseconds(3_600))
                        await requestCapture("spaces-\(appearance)")
                        sidebar.debugSetSlideSlowdown(1)
                        try? await Task.sleep(for: .seconds(8))
                    }
                }
                continue
            case "palette":
                await showcaseShow("Risograph")
                restorePaletteHooks()
                palette?.toggleNew()
                try? await Task.sleep(for: .milliseconds(400))
                type("pal")
                try? await Task.sleep(for: .milliseconds(1_200))
                await showcaseCapture("palette")
                palette?.dismiss()
                continue
            case "peek":
                if let page = await showcaseShow("garden-history", scrollY: 900) {
                    tabs.openPeek(URL(string: "https://en.wikipedia.org/wiki/Digital_garden")!, from: page)
                    if let peek = tabs.shownPeek {
                        await waitLoaded(peek, timeout: 20)
                        await tidy(peek)
                    }
                    try? await Task.sleep(for: .milliseconds(800))
                    await showcaseCapture("peek")
                    _ = tabs.closeShownPeek()
                }
                continue
            case "split":
                if let a = showcaseEntry("human-interface-guidelines"), let b = showcaseEntry("documentation/appkit") {
                    await showcaseShow("human-interface-guidelines")
                    sidebar.joinIntoSplit(b.id, with: a.id)
                    if let other = tabs.contents(for: b.id) { await waitLoaded(other, timeout: 20); await tidy(other) }
                    try? await Task.sleep(for: .seconds(1))
                    await showcaseCapture("split")
                    if let group = store.splitGroup(of: a.id) { store.dissolveSplitGroup(group.id) }
                }
                continue
            case "reader":
                if let page = await showcaseShow("fast_software"), let entry = tabs.currentEntryID {
                    _ = page
                    pressReaderKey()
                    _ = await waitUntil(20) { self.tabs.readerContents(for: entry) != nil }
                    try? await Task.sleep(for: .seconds(1.5))
                    await showcaseCapture("reader")
                    escapeKey()
                }
                continue
            case "hidden":
                await showcaseShow("macbook-pro")
                controller.isSidebarOpen = false
                try? await Task.sleep(for: .milliseconds(800))
                await showcaseCapture("hidden")
                controller.isSidebarOpen = true
                continue
            default:
                continue
            }
            try? await Task.sleep(for: .milliseconds(1_200))
            await showcaseCapture(scene)
        }
        NSApp.appearance = nil
    }
}
#endif
