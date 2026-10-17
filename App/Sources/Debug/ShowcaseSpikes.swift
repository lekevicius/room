#if DEBUG
import AppKit
import ImageIO
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



    // MARK: Recording (no Screen Recording permission: frames composed in process)

    /// `-RoomShowcaseRecord <clip> -RoomShowcaseDirectory <dir>` (`Website/capture/film.sh`): plays the
    /// clip's choreography with the window's animations slowed `-RoomShowcaseSlowdown` times (default
    /// 5) and composes frames as fast as it can meanwhile, each stamped with its time in the clip
    /// (real time / slowdown). Frames go to `<dir>/<clip>/<n>.jpg` at 1920 px, times to `times.txt`.
    private func showcaseRecord(_ clip: String) async {
        let slowdown = max(1, UserDefaults.standard.double(forKey: "RoomShowcaseSlowdown").nonZero ?? 5)
        guard let directory = UserDefaults.standard.string(forKey: "RoomShowcaseDirectory") else {
            return SpikeRunner.record("error", "record needs -RoomShowcaseDirectory")
        }
        let folder = URL(fileURLWithPath: directory).appending(path: clip)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let appearance = showcaseAppearances.first ?? "light"
        NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        guard let studio = showcaseSpace("Studio") else { return }
        sidebar.showSpace(studio.id, animated: false)
        await showcaseShow("la-grande-jatte")
        // Every space's page loaded and tidied before the camera rolls.
        for name in ["Reading", "Work", "Travel"] {
            guard let space = showcaseSpace(name) else { continue }
            sidebar.showSpace(space.id, animated: false)
            if let page = tabs.current {
                await waitLoaded(page, timeout: 20); await tidy(page, scrollY: nil)
                // Until it gives a real frame, so the camera has one to stand in while it repaints.
                for _ in 0..<12 {
                    try? await Task.sleep(for: .milliseconds(500))
                    if let image = await viewport(of: page), !Self.isBlank(image) { break }
                }
            }
        }
        sidebar.showSpace(studio.id, animated: false)
        try? await Task.sleep(for: .seconds(1.5))
        if let page = tabs.current { _ = await viewport(of: page) }
        guard window.occlusionState.contains(.visible) else { return SpikeRunner.record("capture_failed", "\(clip): not on screen") }

        // Slow every Core Animation animation in the window (and Room's own slide) by the same factor.
        let rootLayer = window.contentView?.superview?.layer ?? window.contentView?.layer
        rootLayer?.speed = Float(1 / slowdown)
        sidebar.debugSetSlideSlowdown(slowdown)
        defer { rootLayer?.speed = 1; sidebar.debugSetSlideSlowdown(1) }

        Self.pagesFrozen = true
        defer { Self.pagesFrozen = false }
        let roll = Roll()
        let start = Date()
        let camera = Task { @MainActor in
            while roll.rolling {
                let stamp = Date().timeIntervalSince(start) / slowdown
                let (image, _) = await self.composeImage()
                if let image {
                    self.writeFrame(image, to: folder.appending(path: String(format: "%05d.jpg", roll.times.count)))
                    roll.times.append(stamp)
                }
                await Task.yield()
            }
        }
        func hold(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds * slowdown)) }
        switch clip {
        default: // "hero", "spaces": a loop through every space and back to Studio.
            await hold(1.0)
            for digit in [2, 3, 4, 1] {
                sidebar.showSpace(digit: digit)
                await hold(1.6)
            }
            await hold(0.4)
        }
        roll.rolling = false
        await camera.value
        let times = roll.times
        try? times.map { String(format: "%.4f", $0) }.joined(separator: "\n").write(to: folder.appending(path: "times.txt"), atomically: true, encoding: .utf8)
        SpikeRunner.record("recorded", "\(clip) frames=\(times.count) seconds=\(String(format: "%.2f", times.last ?? 0)) slowdown=\(slowdown)")
    }

    /// A frame at 1920 px wide as JPEG.
    private func writeFrame(_ image: CGImage, to url: URL) {
        let width = 1920, height = Int((Double(image.height) / Double(image.width) * 1920).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.displayP3),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // Window corners on the paper colour of the site, so the video's corners blend into its frame.
        context.setFillColor(CGColor(red: 0.953, green: 0.925, blue: 0.878, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        CGImageDestinationFinalize(destination)
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

    /// One thing to lay over the window image, in the window's drawing order.
    private enum Layer {
        case page(CGImage, NSView)
        /// A translucent fill (a dim): the view's own layer colour over what is under it.
        case tint(CGColor, NSView)
        /// Glass or material (the palette, Peek's frame): its pixels from the window image.
        case paste(NSView)
        /// Anything Room draws itself (the screenshot overlay, labels, buttons): the view's own
        /// drawing with its transparency.
        case drawn(NSBitmapImageRep, NSView)
    }

    /// Composes the window as the window server draws it with the pages Chromium draws on the GPU.
    ///
    /// The window image lacks the pages: their area reads as opaque white whatever lies under or
    /// over it, so the pages cannot be keyed in. Instead the window's views are walked in drawing
    /// order: each page goes in where it is, and whatever Room draws above a page (Peek's dim and
    /// frame, the palette, the screenshot overlay) goes back over it. Returns nil on success.
    private func composeCapture(to url: URL) async -> String? {
        let (image, failure) = await composeImage()
        guard let image else { return failure ?? "no image" }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return "no png" }
        do { try data.write(to: url) } catch { return "write: \(error)" }
        return nil
    }

    /// A page's viewport, or nil after two seconds (a page being hidden mid-switch never answers).
    private func viewport(of page: any WebContents) async -> NSImage? {
        // While a clip rolls the pages hold still: their frames from before the camera started.
        if Self.pagesFrozen, let image = Self.lastViewport[ObjectIdentifier(page.nativeView)] { return image }
        let box = ViewportBox()
        let capture = Task { @MainActor in box.image = try? await page.captureViewport(); box.done = true }
        let deadline = Date().addingTimeInterval(2)
        while !box.done, Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        if !box.done { capture.cancel(); SpikeRunner.record("viewport_timeout", page.url?.host() ?? "?") }
        // A page that was hidden a moment ago answers blank until it paints again: its last real
        // frame stands in.
        let key = ObjectIdentifier(page.nativeView)
        if let image = box.image, !Self.isBlank(image) {
            Self.lastViewport[key] = image
            return image
        }
        return Self.lastViewport[key] ?? box.image
    }

    @MainActor private static var lastViewport: [ObjectIdentifier: NSImage] = [:]
    @MainActor private static var pagesFrozen = false

    /// Whether an image is (nearly) one flat colour: fewer than 2% of a 24×24 grid off its first cell.
    private static func isBlank(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return true }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return true }
        var off = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where abs(Int(pixels[i]) - Int(pixels[0])) + abs(Int(pixels[i + 1]) - Int(pixels[1])) + abs(Int(pixels[i + 2]) - Int(pixels[2])) > 12 {
            off += 1
        }
        return Double(off) / Double(side * side) < 0.02
    }

    /// The composed window (see `composeCapture`), or what went wrong.
    private func composeImage() async -> (CGImage?, String?) {
        if let backdrop = Self.backdrop { backdrop.order(.below, relativeTo: window.windowNumber) }
        let pages = visiblePages
        var images: [ObjectIdentifier: CGImage] = [:]
        for page in pages {
            if let image = await viewport(of: page), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                images[ObjectIdentifier(page.nativeView)] = cg
            }
        }
        guard let base = windowImage(), let root = window.contentView else { return (nil, "no window image") }
        let pageViews = pages.map(\.nativeView)
        func isPageOrInside(_ view: NSView) -> Bool { pageViews.contains { view === $0 || view.isDescendant(of: $0) } }
        func containsPage(_ view: NSView) -> Bool { pageViews.contains { $0.isDescendant(of: view) } }
        let pageRects = pageViews.map { $0.convert($0.bounds, to: nil) }

        // The drawing order: a depth-first walk, subviews in order. A view is "over a page" once
        // a page has been passed and it overlaps one.
        var layers: [Layer] = []
        var passedPage = false
        func visit(_ view: NSView) {
            guard !view.isHidden, view.alphaValue > 0.01 else { return }
            if let image = images[ObjectIdentifier(view)] { layers.append(.page(image, view)); passedPage = true; return }
            if isPageOrInside(view) { return }
            let frame = view.convert(view.bounds, to: nil)
            let over = passedPage && !containsPage(view) && pageRects.contains { $0.intersects(frame) }
            if over {
                if view is NSGlassEffectView || view is NSVisualEffectView { layers.append(.paste(view)); return }
                if let colour = view.layer?.backgroundColor, colour.alpha > 0.01 {
                    if colour.alpha < 0.99 { layers.append(.tint(colour, view)) } else { layers.append(.paste(view)); return }
                }
                if view.subviews.isEmpty || view is NSControl, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    layers.append(.drawn(rep, view))
                    return
                }
                if !(view is NSControl), let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    // A view that draws itself under its subviews (the screenshot overlay's dim).
                    view.cacheDisplay(in: view.bounds, to: rep)
                    layers.append(.drawn(rep, view))
                    return
                }
            }
            for subview in view.subviews { visit(subview) }
        }
        visit(root)
        if UserDefaults.standard.bool(forKey: "RoomShowcaseDebug") {
            SpikeRunner.record("compose_layers", layers.map { layer -> String in
                switch layer {
                case .page(_, let v): "page \(Swift.type(of: v))"
                case .tint(_, let v): "tint \(Swift.type(of: v))"
                case .paste(let v): "paste \(Swift.type(of: v))"
                case .drawn(_, let v): "drawn \(Swift.type(of: v))"
                }
            }.joined(separator: ", "))
        }

        let width = base.width, height = base.height
        let scale = CGFloat(width) / window.frame.width
        let space = base.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3)!
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (nil, "no context") }
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(base, in: full)
        context.interpolationQuality = .high
        func pixels(_ view: NSView) -> CGRect {
            let f = view.convert(view.bounds, to: nil)
            return CGRect(x: f.minX * scale, y: f.minY * scale, width: f.width * scale, height: f.height * scale)
        }
        func clip(_ view: NSView) {
            var path = CGPath(rect: pixels(view), transform: nil)
            if let corner = clippingCorner(of: view) {
                let r = corner.rect
                path = CGPath(roundedRect: CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale),
                              cornerWidth: corner.radius * scale, cornerHeight: corner.radius * scale, transform: nil)
            }
            context.addPath(path); context.clip()
        }
        for layer in layers {
            context.saveGState()
            switch layer {
            case .page(let image, let view):
                clip(view)
                context.draw(image, in: pixels(view))
            case .tint(let colour, let view):
                clip(view)
                context.setFillColor(colour)
                context.fill(pixels(view))
            case .paste(let view):
                let r = pixels(view)
                let radius = (view.layer?.cornerRadius ?? 0) * scale
                context.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)); context.clip()
                // The window image is top-left first; crop it to the view's rect.
                let crop = CGRect(x: r.minX, y: CGFloat(height) - r.maxY, width: r.width, height: r.height).integral
                if let piece = base.cropping(to: crop) { context.draw(piece, in: CGRect(x: crop.minX, y: CGFloat(height) - crop.maxY, width: crop.width, height: crop.height)) }
            case .drawn(let rep, let view):
                clip(view)
                if let image = rep.cgImage { context.draw(image, in: pixels(view)) }
            }
            context.restoreGState()
        }
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
            context.draw(layer.image, in: r)
            context.restoreGState()
        }
        return (context.makeImage(), nil)
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
        // The engine returns the result as JSON: a quoted string, with "/" possibly escaped.
        let string = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)) as? String
            ?? json.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
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

        if let clip = UserDefaults.standard.string(forKey: "RoomShowcaseRecord") {
            await showcaseRecord(clip)
            NSApp.appearance = nil
            return
        }

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
                SpikeRunner.record("pip_state", "windows=\(NSApp.windows.filter(\.isVisible).map { "\(Swift.type(of: $0)) \(NSStringFromRect($0.frame))" }) "
                    + "video=\(await js(video, "JSON.stringify({pip: !!document.pictureInPictureElement, ready: document.getElementById('video').readyState, w: document.getElementById('video').videoWidth})"))")
                let frameJSON = await js(video, "(() => { const v = document.getElementById('video'); const c = document.createElement('canvas'); c.width = v.videoWidth; c.height = v.videoHeight; c.getContext('2d').drawImage(v, 0, 0); return c.toDataURL('image/jpeg', 0.92); })()")
                SpikeRunner.record("pip_frame", "length=\(frameJSON.count) head=\(frameJSON.prefix(60))")
                if let pip = others().first, let frame = image(fromDataURL: frameJSON) {
                    await showcaseShow("la-grande-jatte")
                    let size = NSSize(width: 400, height: 225)
                    let origin = NSPoint(x: window.frame.maxX - size.width - 36, y: window.frame.minY + 36)
                    pip.setFrame(NSRect(origin: origin, size: size), display: true)
                    Self.extraLayers = [(frame, CGRect(x: origin.x - window.frame.minX, y: origin.y - window.frame.minY,
                                                       width: size.width, height: size.height), 12)]
                    // Where the picture-in-picture window sits, in window points from the top left:
                    // capture.sh cuts it out as its own layer, so the site can fade the window but not it.
                    SpikeRunner.record("pip_layer", String(format: "%.0f %.0f %.0f %.0f 12", origin.x - window.frame.minX,
                                                           window.frame.maxY - origin.y - size.height, size.width, size.height))
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
                let painting = await rect(of: ".m-article-header img, .o-article__primary-actions img, main img[src*=\"iiif\"], img[src*=\"iiif\"]", in: page)
                guard let painting, let controller = await openOverlay(app) else { continue }
                let inset = painting.insetBy(dx: -10, dy: -10)
                dragOverlay(controller.overlay, from: CGPoint(x: inset.minX, y: inset.minY), to: CGPoint(x: inset.maxX, y: inset.maxY))
                _ = await waitUntil(5) { controller.image != nil }
                try? await Task.sleep(for: .milliseconds(600))
                SpikeRunner.record("screenshot_state", "painting=\(NSStringFromRect(painting)) selection=\(controller.overlay.selection.map { NSStringFromRect($0) } ?? "nil") bar=\(controller.overlay.isBarShown) in_window=\(controller.overlay.window != nil) superview=\(controller.overlay.superview.map { "\(Swift.type(of: $0))" } ?? "nil")")
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

#if DEBUG
@MainActor private final class ViewportBox {
    var image: NSImage?
    var done = false
}

/// The camera's state while a clip rolls (main actor only).
@MainActor private final class Roll {
    var rolling = true
    var times: [Double] = []
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
#endif
