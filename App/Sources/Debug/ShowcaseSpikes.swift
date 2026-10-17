#if DEBUG
import AppKit
import Engine
import Model
import Store
import UIKitCore

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
/// - `-RoomShowcaseDirectory <dir>`: compose each capture in process instead of asking the script:
///   the window as the window server draws it (`WindowSnapshot`, own window: no Screen Recording
///   permission) with every visible page's `captureViewport()` laid into its place, under the
///   window's own overlays where the window is clear there. Written as `<dir>/<name>.png`.
/// - `-RoomShowcaseBackdrop <image>`: a borderless window behind Room filled with the image, so
///   the sidebar's material samples a chosen wallpaper rather than whatever is on the desktop.
///
/// - `-RoomShowcaseFixtures <http base>`: `Website/capture/fixtures` served (by `capture.sh`) for the
///   `music` and `pip` scenes.
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
        ("https://www.figma.com/", "Figma"), ("https://linear.app/", "Linear"), ("https://github.com/", "GitHub"),
        ("https://music.apple.com/us/new", "Apple Music"), ("https://www.are.na/", "Are.na"), ("https://www.notion.com/", "Notion"),
    ]

    /// Space name → (SF Symbol, theme colour, algorithm, opacity, second profile, pages).
    static let showcaseSpaces: [(name: String, icon: String, colour: String, algorithm: ThemeAlgorithm, opacity: Double, work: Bool,
                                 pages: [ShowcasePage])] = [
        ("Studio", "paintpalette", "#E8836A", .analogous, 0.55, false, [
            ShowcasePage(kind: .pinned, url: "https://www.artic.edu/collection", title: "Art Institute of Chicago"),
            ShowcasePage(kind: .pinned, url: "https://www.cosmos.so/", title: "Cosmos", folder: "Inspiration"),
            ShowcasePage(kind: .pinned, url: "https://www.siteinspire.com/", title: "siteInspire", folder: "Inspiration"),
            ShowcasePage(kind: .pinned, url: "https://minimal.gallery/", title: "Minimal Gallery", folder: "Inspiration"),
            ShowcasePage(kind: .pinned, url: "https://fontsinuse.com/", title: "Fonts In Use", folder: "Type"),
            ShowcasePage(kind: .pinned, url: "https://www.typewolf.com/", title: "Typewolf", folder: "Type"),
            ShowcasePage(kind: .today, url: "https://www.artic.edu/artworks/27992/a-sunday-on-la-grande-jatte-1884",
                         title: "A Sunday on La Grande Jatte"),
            ShowcasePage(kind: .today, url: "https://en.wikipedia.org/wiki/Risograph", title: "Risograph - Wikipedia"),
            ShowcasePage(kind: .today, url: "https://lospec.com/palette-list", title: "Palette List | Lospec"),
            ShowcasePage(kind: .today, url: "https://www.apple.com/macbook-pro/", title: "MacBook Pro - Apple"),
        ]),
        ("Reading", "book", "#3E8E7E", .analogous, 0.5, false, [
            ShowcasePage(kind: .pinned, url: "https://www.themarginalian.org/", title: "The Marginalian"),
            ShowcasePage(kind: .pinned, url: "https://publicdomainreview.org/", title: "The Public Domain Review"),
            ShowcasePage(kind: .pinned, url: "https://aeon.co/", title: "Aeon"),
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
            ShowcasePage(kind: .pinned, url: "https://www.atlasobscura.com/", title: "Atlas Obscura"),
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
        let all = ["hero", "sidebar", "spaces", "palette", "peek", "split", "reader", "hidden", "music", "pip", "screenshot"]
        guard let only = UserDefaults.standard.string(forKey: "RoomShowcaseOnly") else { return all }
        let wanted = Set(only.split(separator: ",").map(String.init))
        return all.filter(wanted.contains)
    }

    private var showcaseAppearances: [String] {
        (UserDefaults.standard.string(forKey: "RoomShowcaseAppearances") ?? "light,dark").split(separator: ",").map(String.init)
    }

    private func showcaseEntry(_ fragment: String) -> Entry? {
        store.entries.values.first { ($0.storedURL ?? $0.liveURL)?.contains(fragment) == true }
    }

    private func showcaseSpace(_ name: String) -> Space? { store.spaces.first { $0.name == name } }

    /// Hides consent banners and similar overlays, then scrolls to `y`.
    private func tidy(_ page: any WebContents, scrollY: Int? = 0) async {
        let hide = [
            "#onetrust-consent-sdk", "#onetrust-banner-sdk", ".fc-consent-root", "#CybotCookiebotDialog", "#usercentrics-root",
            ".osano-cm-window", ".qc-cmp2-container", "#truste-consent-track", "[id^=sp_message_container]", ".cc-window", ".cky-consent-container",
            "#cookie-banner", ".cookie-banner", "[class*=CookieBanner]", "[class*=cookie-consent]", "[id*=cookie-consent]",
            "[aria-label*=cookie i][role=dialog]", "#ac-ls", ".ac-ls", "#ac-gn-segmentbar", ".ac-gn-segmentbar", "[aria-label*=consent i][role=dialog]", "#didomi-host", ".didomi-popup-open",
        ].joined(separator: ",")
        let script = """
        (() => {
          const s = document.createElement('style');
          s.textContent = `\(hide) { display: none !important; } html, body { overflow: auto !important; }`;
          document.documentElement.append(s);
          document.body && document.body.classList.remove('didomi-popup-open', 'modal-open', 'no-scroll');
          // Anything else pinned to the viewport that talks about cookies or consent.
          for (const el of document.querySelectorAll('body *')) {
            const style = getComputedStyle(el);
            if (style.position !== 'fixed' && style.position !== 'sticky') continue;
            const text = el.textContent || '';
            const frame = el.tagName === 'IFRAME' && /consent|cmp|privacy-mgmt|cookie/i.test(el.src || '');
            if (frame || (text.length < 2000 && /cookie|consent/i.test(text))) el.style.setProperty('display', 'none', 'important');
          }
          \(scrollY.map { "window.scrollTo(0, \($0));" } ?? "")
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

    private func showcaseCaptureAll(_ scene: String) async { await showcaseCapture(scene) }

    private func showcaseCapture(_ scene: String) async {
        for appearance in showcaseAppearances {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            try? await Task.sleep(for: .milliseconds(700))
            await showcaseRequest("\(scene)-\(appearance)")
        }
    }


    // MARK: Capture

    /// The script's window-server capture, or a composed one with `-RoomShowcaseDirectory`.
    private func showcaseRequest(_ name: String) async {
        guard let directory = UserDefaults.standard.string(forKey: "RoomShowcaseDirectory") else {
            return await requestCapture(name)
        }
        // A window that is not on screen (the Mac locked, another Space in front) keeps stale pixels
        // in the window server: better no capture than a wrong one.
        guard window.occlusionState.contains(.visible) else {
            return SpikeRunner.record("capture_failed", "\(name): Room's window is not on screen (is the Mac locked?)")
        }
        for page in visiblePages { await tidy(page, scrollY: nil) }
        try? await Task.sleep(for: .milliseconds(600))
        let url = URL(fileURLWithPath: directory).appending(path: "\(name).png")
        if let failure = await composeCapture(to: url) {
            SpikeRunner.record("capture_failed", "\(name): \(failure)")
        } else {
            SpikeRunner.record("captured", name)
        }
    }

    /// Every page whose view is showing in this window: the selection, split panes, Peek, Reader.
    private var visiblePages: [any WebContents] {
        var pages: [any WebContents] = store.entries.keys.compactMap { tabs.contents(for: $0) }
        pages += store.entries.keys.compactMap { tabs.readerContents(for: $0) }
        if let peek = tabs.shownPeek { pages.append(peek) }
        return pages.filter { page in
            let view = page.nativeView
            return view.window === window && !view.isHiddenOrHasHiddenAncestor && !view.visibleRect.isEmpty && view.alphaValue > 0
        }
    }

    /// The innermost ancestor that clips with rounded corners: where the card cuts the page.
    private func clippingCorner(of view: NSView) -> (rect: NSRect, radius: CGFloat)? {
        var current: NSView? = view
        while let candidate = current {
            if let layer = candidate.layer, layer.cornerRadius > 0, layer.masksToBounds || candidate.clipsToBounds {
                return (candidate.convert(candidate.bounds, to: nil), layer.cornerRadius)
            }
            current = candidate.superview
        }
        return nil
    }

    /// The window as the window server draws it, with this app's windows over it (not the backdrop).
    private func windowImage() -> CGImage? {
        let others = NSApp.windows.filter { other in
            // Chromium's own widget windows (NativeWidgetMacNSWindow, the size of the window) hold no
            // pixels of their own here and would cover the card; the palette and popovers are ours.
            other !== window && other !== Self.backdrop && other.isVisible && other.frame.intersects(window.frame)
                && other.orderedIndex < window.orderedIndex && !String(describing: Swift.type(of: other)).hasPrefix("NativeWidget")
        }
        return WindowSnapshot.capture(window, with: others) ?? WindowSnapshot.capture(window)
    }

    /// Returns nil on success, or what went wrong.
    ///
    /// The window server's image lacks the pages (Chromium draws them in its GPU process), and the
    /// card is opaque behind them, so a page cannot simply go under the window's own overlays (the
    /// palette, Peek's dim and glass). Difference matting recovers them: each page is captured, then
    /// the window twice with the page's view hidden and its container black (B), then white (W); per
    /// channel, an overlay of colour F and opacity a gives B = aF and W = aF + (1 − a), so over the
    /// page P the result is B + (W − B)·P.
    private func composeCapture(to url: URL) async -> String? {
        if let backdrop = Self.backdrop { backdrop.order(.below, relativeTo: window.windowNumber) }
        let pages = visiblePages
        // The pages first, while they are showing.
        var shots: [(CGImage, NSView)] = []
        for page in pages {
            if let image = try? await page.captureViewport(), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                shots.append((cg, page.nativeView))
            }
        }
        // Keying the page (black, then white) to recover the window's own overlays over it by
        // difference matting does not work yet: Chromium's remote content comes out opaque white in
        // our own window's image whatever lies under or over it. Until then the pages are drawn over
        // the window (B = W, so the result is the page): overlays inside the card (the palette, Peek's
        // dim) are lost, everything else is right.
        let views = shots.map(\.1)
        let black = windowImage()
        let white = black
        guard let black, let white else { return "no window image" }
        _ = views
        if UserDefaults.standard.bool(forKey: "RoomShowcaseDebug") {
            try? NSBitmapImageRep(cgImage: black).representation(using: .png, properties: [:])?
                .write(to: url.deletingPathExtension().appendingPathExtension("black.png"))
            let list = NSApp.windows.filter(\.isVisible).map { "\(Swift.type(of: $0)) #\($0.windowNumber) idx \($0.orderedIndex)" }
            SpikeRunner.record("windows", list.joined(separator: " | ") + "; pages \(pages.count)")
        }

        let width = black.width, height = black.height
        let scale = CGFloat(width) / window.frame.width
        let space = black.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3)!
        func buffer(_ draw: (CGContext) -> Void) -> [UInt8]? {
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                draw(context)
                return true
            }
            return ok ? bytes : nil
        }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        // The pages, each in its place and clipped to its card's corners, on white.
        let pageBytes = buffer { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(full)
            for (image, view) in shots {
                let frame = view.convert(view.bounds, to: nil)
                let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
                context.saveGState()
                if let corner = clippingCorner(of: view) {
                    let r = corner.rect
                    context.addPath(CGPath(roundedRect: CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale),
                                           cornerWidth: corner.radius * scale, cornerHeight: corner.radius * scale, transform: nil))
                    context.clip()
                }
                context.interpolationQuality = .high
                context.draw(image, in: rect)
                context.restoreGState()
            }
        }
        var maskBytes = [UInt8](repeating: 0, count: width * height)
        maskBytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.setFillColor(gray: 1, alpha: 1)
            for (_, view) in shots {
                let frame = view.convert(view.bounds, to: nil)
                let rect = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
                context.saveGState()
                if let corner = clippingCorner(of: view) {
                    let r = corner.rect
                    context.addPath(CGPath(roundedRect: CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale),
                                           cornerWidth: corner.radius * scale, cornerHeight: corner.radius * scale, transform: nil))
                    context.clip()
                }
                context.fill(rect)
                context.restoreGState()
            }
        }
        guard var out = buffer({ $0.draw(black, in: full) }), let whiteBytes = buffer({ $0.draw(white, in: full) }), let pageBytes else {
            return "no buffers"
        }
        // Pages over the window, where the pages are (see above); the window's shape from W.
        out.withUnsafeMutableBufferPointer { o in
            whiteBytes.withUnsafeBufferPointer { w in
                pageBytes.withUnsafeBufferPointer { p in
                    var i = 0
                    let count = o.count
                    while i < count {
                        // The page layer is opaque white outside the pages; the pages' own pixels are
                        // told apart by the mask drawn alongside them.
                        if maskBytes[i / 4] != 0 { o[i] = p[i]; o[i + 1] = p[i + 1]; o[i + 2] = p[i + 2] }
                        o[i + 3] = w[i + 3]
                        i += 4
                    }
                }
            }
        }
        let result: CGImage? = out.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            // Windows Chromium draws on the GPU (picture in picture), laid in with their shadow and corners.
            for layer in Self.extraLayers {
                let r = CGRect(x: layer.rect.minX * scale, y: layer.rect.minY * scale, width: layer.rect.width * scale, height: layer.rect.height * scale)
                let path = CGPath(roundedRect: r, cornerWidth: layer.radius * scale, cornerHeight: layer.radius * scale, transform: nil)
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 40 * scale, color: CGColor(gray: 0, alpha: 0.38))
                context.addPath(path); context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fillPath()
                context.restoreGState()
                context.saveGState()
                context.addPath(path); context.clip()
                context.interpolationQuality = .high
                context.draw(layer.image, in: r)
                context.restoreGState()
            }
            return context.makeImage()
        }
        guard let result, let data = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:]) else { return "no png" }
        do { try data.write(to: url) } catch { return "write: \(error)" }
        return nil
    }

    /// A borderless window under Room, filled with the backdrop image.
    private func showBackdrop() {
        guard let path = UserDefaults.standard.string(forKey: "RoomShowcaseBackdrop"), let image = NSImage(contentsOfFile: path),
              let screen = window.screen else { return }
        let backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.ignoresMouseEvents = true
        backdrop.hasShadow = false
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resizeAspectFill
        backdrop.contentView = view
        backdrop.level = window.level
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backdrop.order(.below, relativeTo: window.windowNumber)
        Self.backdrop = backdrop
    }

    @MainActor private static var backdrop: NSWindow?
    /// Images composed over the window at a rect in window points, with corner radius.
    @MainActor private static var extraLayers: [(image: CGImage, rect: CGRect, radius: CGFloat)] = []

    private var fixturesBase: String? { UserDefaults.standard.string(forKey: "RoomShowcaseFixtures") }

    /// A JS data URL (as the engine returns it, JSON-quoted) as an image.
    private func image(fromDataURL json: String) -> CGImage? {
        let string = json.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard let comma = string.firstIndex(of: ","), let data = Data(base64Encoded: String(string[string.index(after: comma)...])),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func showcase() async {
        SpikeRunner.record("window_id", window.windowNumber)
        let size = (UserDefaults.standard.string(forKey: "RoomShowcaseSize") ?? "1440x900").split(separator: "x").compactMap { Double($0) }
        window.setContentSize(NSSize(width: size.first ?? 1440, height: size.last ?? 900))
        window.center()
        controller.sidebarWidth = 300
        controller.isSidebarOpen = true
        controller.activityOverride = true
        // On screen for real: an occluded window's pixels stop reaching the window server, and the
        // in-process captures read stale ones. Floating keeps Room (and its backdrop) above the
        // windows of whatever app is in front while a run goes unattended.
        window.level = .floating
        // …and on the Space in front, even when that is another app's full screen.
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        showBackdrop()
        _ = await waitUntil(15) { self.sidebar.debugPreparedSpaces == self.store.spaces.count }
        guard let studio = showcaseSpace("Studio") else { return SpikeRunner.record("error", "needs -RoomSidebarFixture showcase") }

        // Warm-up: every page once, so favicons and caches are in place before the captures.
        for space in store.spaces {
            sidebar.showSpace(space.id, animated: false)
            let pages = store.entries.values.filter { $0.spaceID == space.id && ($0.storedURL ?? $0.liveURL) != nil }
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
                await showcaseShow("cosmos.so")
            case "spaces":
                // A second space in its own colours, the footer's space icons hovered.
                await showcaseShow("Curonian_Spit")
                if let reading = showcaseSpace("Reading") {
                    sidebar.debugHoverSpaceIcon(reading.id)
                    try? await Task.sleep(for: .milliseconds(600))
                    await showcaseCaptureAll("spaces")
                    sidebar.debugHoverSpaceIcon(nil)
                }
                continue
            case "palette":
                await showcaseShow("Risograph")
                restorePaletteHooks()
                palette?.toggleNew()
                try? await Task.sleep(for: .milliseconds(400))
                SpikeRunner.record("palette_open", "\(palette?.isOpen ?? false) app active \(NSApp.isActive) key \(window.isKeyWindow)")
                type("pal")
                try? await Task.sleep(for: .milliseconds(1_200))
                await showcaseCapture("palette")
                palette?.dismiss()
                continue
            case "peek":
                if let page = await showcaseShow("garden-history", scrollY: 900) {
                    tabs.openPeek(URL(string: "https://en.wikipedia.org/wiki/Zettelkasten")!, from: page)
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
            case "music":
                // Something playing in another space: the media row above the footer, with its artwork.
                guard let base = fixturesBase, let travel = showcaseSpace("Travel") else { continue }
                sidebar.showSpace(travel.id, animated: false)
                guard let player = await open(URL(string: "\(base)/music.html")!) else { continue }
                await click(player, "#play")
                _ = await waitUntil(8) { player.mediaSession?.playbackState == .playing }
                await showcaseShow("la-grande-jatte")
                _ = await waitUntil(6) { self.sidebar.mediaRowContent != nil }
                try? await Task.sleep(for: .milliseconds(1_200))
                await showcaseCapture("music")
                _ = await js(player, "document.getElementById('audio').pause()")
                if let entry = tabs.entryID(for: player) { _ = try? store.remove(entry) }
                continue
            case "pip":
                // A video in picture in picture over the window's corner.
                guard let base = fixturesBase, let video = await open(URL(string: "\(base)/pip.html")!) else { continue }
                await click(video, "#pip")
                let others = { NSApp.windows.filter { $0 !== self.window && $0.isVisible && $0.frame.width < self.window.frame.width * 0.6
                    && String(describing: Swift.type(of: $0)).hasPrefix("NativeWidget") } }
                _ = await waitUntil(8) { !others().isEmpty }
                try? await Task.sleep(for: .seconds(2.5))
                if let pip = others().first, let frame = image(fromDataURL: await js(video, "roomFrame()")) {
                    await showcaseShow("la-grande-jatte")
                    let size = NSSize(width: 400, height: 225)
                    let origin = NSPoint(x: window.frame.maxX - size.width - 36, y: window.frame.minY + 36)
                    pip.setFrame(NSRect(origin: origin, size: size), display: true)
                    Self.extraLayers = [(frame, CGRect(x: origin.x - window.frame.minX, y: origin.y - window.frame.minY,
                                                       width: size.width, height: size.height), 12)]
                    try? await Task.sleep(for: .milliseconds(600))
                    await showcaseCapture("pip")
                    Self.extraLayers = []
                } else {
                    SpikeRunner.record("showcase_missing", "picture in picture window or frame")
                }
                _ = await js(video, "document.exitPictureInPicture && document.exitPictureInPicture()")
                if let entry = tabs.entryID(for: video) { _ = try? store.remove(entry) }
                continue
            case "screenshot":
                // ⇧⌘2 with the painting selected: the bar with Copy, Save and Open as Tab.
                guard let app = AppDelegate.current, let page = await showcaseShow("la-grande-jatte") else { continue }
                let painting = await rect(of: "main img, .m-article-header img, img", in: page)
                guard let painting, let controller = await openOverlay(app) else { continue }
                let inset = painting.insetBy(dx: -10, dy: -10)
                dragOverlay(controller.overlay, from: CGPoint(x: inset.minX, y: inset.minY), to: CGPoint(x: inset.maxX, y: inset.maxY))
                _ = await waitUntil(5) { controller.image != nil }
                try? await Task.sleep(for: .milliseconds(600))
                await showcaseCapture("screenshot")
                escapeKey()
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
