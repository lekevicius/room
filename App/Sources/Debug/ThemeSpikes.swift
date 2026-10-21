#if DEBUG
import AppKit
import Design
import Model
import Sidebar
import UIKitCore

/// 5.2b: the space themes, menus and space form in the matrix (`MatrixSpikes.swift` lists them), and
/// `-RoomSpike contrast` (`scripts/theme-contrast.sh`): the contrast of the sidebar's primary and
/// secondary text over the tinted material, for each of the five algorithms on eight sample colours,
/// over four busy wallpaper fixtures and a plain one placed behind Room's window (a borderless window
/// of the spike's own, never the user's desktop picture), light and dark, at the default and the
/// highest tint opacity. Text is probe labels in the sidebar (the rows' fonts and colours, "█"
/// glyphs so the text colour has solid pixels); each sample reads the text pixel and the material
/// beside it from a capture of the window (`WindowSnapshot`, the material composited over the
/// fixture) and records the WCAG ratio. Measurements for `spike-results.md`, never an assertion.
/// Window-list captures render the behind-window material the same over every fixture (they do not
/// include what is behind a window); the display as seen needs Screen Recording, which Room never
/// asks for: `-RoomContrastHold <s>` holds each fixture so a screenshot can be taken from outside.
/// - `-RoomSpikeOnly inactive`: the inactive window's desaturation (§I.12) and the mono traffic
///   lights instead, read from captures.
extension SpikeRunner.Context {
    // MARK: Matrix: themes

    /// The eight sample colours of the contrast table (chosen: the hue circle's primaries and
    /// secondaries at Material-like saturation, a pastel yellow and a dark slate).
    static let themeSamples = ["#E53935", "#FB8C00", "#FDD835", "#43A047", "#1E88E5", "#5E35B1", "#D81B60", "#37474F"]

    var themeNotes: [String] {
        [String(format: "The space tint (WindowMaterialView): Materials.tintOpacityRange %.2f–%.2f (opacity 0 → 1), default opacity 0.5 → %.3f; "
                + "dark variant lightness ≤ ThemePalette.darkMaxLightness %.2f; inactive × SpaceTintView.inactiveFactor 0.6.",
                Materials.tintOpacityRange.lowerBound, Materials.tintOpacityRange.upperBound,
                ThemePalette.tintAlpha(opacity: 0.5, range: Double(Materials.tintOpacityRange.lowerBound)...Double(Materials.tintOpacityRange.upperBound)),
                ThemePalette.darkMaxLightness),
         String(format: "Inactive: the sidebar's content at SidebarMetrics.inactiveSaturation %.1f (CIColorControls) and inactiveContentAlpha %.1f (§I.12). "
                + "Secondary text: Palette.sidebarSecondaryLabel. Rows: each algorithm on its sample colour at opacity 0.5, then Triadic at 1.0.",
                SidebarMetrics.inactiveSaturation, SidebarMetrics.inactiveContentAlpha)]
    }

    /// Each algorithm on one sample colour; the last row the highest opacity.
    func themeStates() -> [MatrixState] {
        let rows: [(String, ThemeAlgorithm, String, Double)] = [
            ("Complementary #E53935, 0.5", .complementary, "#E53935", 0.5),
            ("Split #FB8C00, 0.5", .split, "#FB8C00", 0.5),
            ("Analogous #43A047, 0.5", .analogous, "#43A047", 0.5),
            ("Triadic #1E88E5, 0.5", .triadic, "#1E88E5", 0.5),
            ("Floating #5E35B1, 0.5", .floating, "#5E35B1", 0.5),
            ("Triadic #1E88E5, 1.0 (the highest)", .triadic, "#1E88E5", 1.0),
        ]
        let rect = { self.sidebarRect(top: 0, height: 560) }
        return rows.map { label, algorithm, color, opacity in
            MatrixState(label: label, setup: {
                self.applyTheme([color], algorithm: algorithm, opacity: opacity)
                try? await Task.sleep(for: .milliseconds(300))
            }, shoot: { await self.matrixShot(rect(), scale: 0.5) }, teardown: { self.restoreSpaceTint() })
        }
    }

    func applyTheme(_ wells: [String], algorithm: ThemeAlgorithm, opacity: Double) {
        let colors = ThemePalette.colors(wells, algorithm: algorithm)
        controller.materialView.setTint(SpaceTint(SpaceTheme(colors: colors, opacity: opacity)), animated: false)
    }

    func restoreSpaceTint() {
        controller.materialView.setTint(sidebar.activeSpace?.theme.map(SpaceTint.init), animated: false)
    }

    // MARK: Matrix: menus (B-37)

    var menuNotes: [String] {
        ["Menus drawn by AppKit from MainMenuTable (UIKitCore): MenuKey.display gives each item its glyphs (⇧ with the base key, B-37); "
            + "a hidden alias per shifted key (MenuKey.equivalent: the character the key types on the US layout) does the matching.",
         "Captured from each menu's own window while it tracks (popUp, a timer captures and cancels it; no click). Inactive columns are the same menus."]
    }

    func menuStates() -> [MatrixState] {
        func item(_ title: String) -> NSMenu? { NSApp.mainMenu?.item(withTitle: title)?.submenu }
        let split = { item("Tab")?.items.first { $0.submenu?.items.contains { $0.action == NSSelectorFromString("newSplitPane:") } == true }?.submenu }
        return [
            MatrixState(label: "File", shoot: { await self.menuShot(item("File")) }),
            MatrixState(label: "Tab", shoot: { await self.menuShot(item("Tab")) }),
            MatrixState(label: "Tab ▸ Split View", shoot: { await self.menuShot(split()) }),
        ]
    }

    /// The menu's own window, captured while it tracks (a copy, popped up over the browser window).
    func menuShot(_ menu: NSMenu?, scale: CGFloat = 0.75) async -> CGImage? {
        guard let menu, let copy = menu.copy() as? NSMenu else { return nil }
        // Every item enabled, as with a page selected (validation is the app's; the glyphs are the point).
        copy.autoenablesItems = false
        for item in copy.items { item.isEnabled = !item.isSeparatorItem }
        let capture = MenuCapture(copy)
        capture.perform(#selector(MenuCapture.capture), with: nil, afterDelay: 0.4, inModes: [.common, .eventTracking])
        copy.popUp(positioning: nil, at: NSPoint(x: 340, y: window.contentLayoutRect.height - 60), in: window.contentView)
        guard let image = capture.image, scale != 1 else { return capture.image }
        let size = CGSize(width: (CGFloat(image.width) * scale).rounded(), height: (CGFloat(image.height) * scale).rounded())
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    // MARK: Matrix: the space window (B-23; 5.7b, B-122)

    var spaceFormNotes: [String] {
        [String(format: "The space window (5.7b, B-122: SwiftUI in a window of its own, %.0f × %.0f pt fitted to the visible frame, "
                + "at least %.0f): name, icon, colour wells and algorithm, the tint's opacity (B-23: TintOpacityControl, "
                + "0–100%% → Materials.tintOpacityRange %.2f–%.2f), the preview, profile, routes. SpaceFormMetrics.padding %.0f.",
                SpaceWindowMetrics.width, SpaceWindowMetrics.height, SpaceWindowMetrics.minHeight,
                Materials.tintOpacityRange.lowerBound, Materials.tintOpacityRange.upperBound, SpaceFormMetrics.padding)]
    }

    /// The space window in each of its openings: Space Settings… (name), Edit Theme… on a Triadic space,
    /// Space Routing Settings… with two routes, New Space.
    func spaceFormStates() -> [MatrixState] {
        guard let app = AppDelegate.current else { return [] }
        let openings: [(String, SpaceFormFocus, Bool)] = [
            ("Space Settings… (name)", .name, false), ("Edit Theme… on a Triadic space", .theme, false),
            ("Space Routing Settings… (two routes)", .routes, false), ("New Space", .name, true),
        ]
        var added: [UUID] = []
        return openings.map { label, focus, creates in
            MatrixState(label: label, setup: {
                guard let space = self.sidebar.activeSpace else { return }
                try? self.store.updateSpace(space.id) {
                    $0.themeColors = ["#1E88E5"]
                    $0.themeAlgorithm = .triadic
                    $0.themeOpacity = 0.5
                }
                if focus == .routes {
                    added = [try? self.store.addRoutingRule(.contains, pattern: "github.com/room", target: space.id).id,
                             try? self.store.addRoutingRule(.equals, pattern: "example.com", target: space.id).id].compactMap { $0 }
                }
                app.showSpaceWindow(creates ? nil : space.id, focus: focus, from: self.sidebar)
                try? await Task.sleep(for: .milliseconds(800))
            }, shoot: {
                guard let target = app.spaceWindow?.window else { return nil }
                if self.matrixActive { target.makeKeyAndOrderFront(nil) } else { self.window.makeKeyAndOrderFront(nil) }
                try? await Task.sleep(for: .milliseconds(400))
                return await self.matrixShot(in: target, scale: 0.5)
            }, teardown: {
                app.spaceWindow?.cancel()
                for id in added { self.store.removeRoutingRule(id) }
                added = []
                if let space = self.sidebar.activeSpace {
                    try? self.store.updateSpace(space.id) { $0.themeColors = [] }
                }
                self.window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(400))
            })
        }
    }

    // MARK: The contrast table (task 4)

    /// A wallpaper fixture: a deterministic image drawn behind Room's window.
    enum WallpaperFixture: String, CaseIterable {
        case plain, stripes, confetti, night, sky

        func image(size: CGSize) -> CGImage? {
            let width = Int(size.width), height = Int(size.height)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            var seed: UInt64 = 0x5_2B
            func random() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 10_000) / 10_000
            }
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            switch self {
            case .plain:
                // A plain desktop: mid grey.
                context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
                context.fill(bounds)
            case .stripes:
                // Black and white diagonal stripes, 48 px: the widest luminance swing.
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(bounds)
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                var x = -CGFloat(height)
                while x < CGFloat(width) {
                    context.beginPath()
                    context.move(to: CGPoint(x: x, y: 0))
                    context.addLine(to: CGPoint(x: x + 48, y: 0))
                    context.addLine(to: CGPoint(x: x + 48 + CGFloat(height), y: CGFloat(height)))
                    context.addLine(to: CGPoint(x: x + CGFloat(height), y: CGFloat(height)))
                    context.closePath()
                    context.fillPath()
                    x += 96
                }
            case .confetti:
                // Saturated rectangles of every hue on white.
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(bounds)
                for _ in 0..<600 {
                    let hue = HSLColor(hue: Double(random()), saturation: 0.9, lightness: 0.25 + 0.5 * Double(random())).rgb
                    context.setFillColor(CGColor(srgbRed: hue.red, green: hue.green, blue: hue.blue, alpha: 1))
                    context.fill(CGRect(x: random() * CGFloat(width), y: random() * CGFloat(height), width: 20 + random() * 140, height: 20 + random() * 140))
                }
            case .night:
                // A night photograph's palette: near-black blue with bright lights.
                let colors = [CGColor(srgbRed: 0.02, green: 0.03, blue: 0.10, alpha: 1), CGColor(srgbRed: 0.10, green: 0.05, blue: 0.25, alpha: 1)] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
                }
                for _ in 0..<900 {
                    let warm = random() > 0.5
                    context.setFillColor(CGColor(srgbRed: 1, green: warm ? 0.8 : 0.95, blue: warm ? 0.45 : 1, alpha: 0.4 + 0.6 * random()))
                    let r = 2 + random() * 14
                    context.fillEllipse(in: CGRect(x: random() * CGFloat(width), y: random() * CGFloat(height) * 0.6, width: r, height: r))
                }
            case .sky:
                // A bright landscape's palette: white and yellow sky, cyan, saturated green ground.
                let colors = [CGColor(srgbRed: 0.15, green: 0.55, blue: 0.20, alpha: 1), CGColor(srgbRed: 0.30, green: 0.80, blue: 0.95, alpha: 1),
                              CGColor(srgbRed: 1, green: 0.95, blue: 0.70, alpha: 1), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.35, 0.7, 1]) {
                    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
                }
                for _ in 0..<160 {
                    context.setFillColor(CGColor(srgbRed: 0.9 + 0.1 * random(), green: 0.3 + 0.6 * random(), blue: 0.1 * random(), alpha: 0.85))
                    let r = 30 + random() * 120
                    context.fillEllipse(in: CGRect(x: random() * CGFloat(width), y: random() * CGFloat(height), width: r, height: r * 0.6))
                }
            }
            return context.makeImage()
        }
    }

    /// One probe: a label of "█" in the sidebar, primary or secondary.
    struct ContrastProbe {
        let field: NSTextField
        let secondary: Bool
    }

    func contrastChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        window.setContentSize(NSSize(width: 1200, height: 780))
        controller.sidebarWidth = SidebarMetrics.defaultWidth
        controller.activityOverride = true
        await activate()
        try? await Task.sleep(for: .milliseconds(800))
        if only.contains("inactive") { return await inactiveChecks() }
        // `-RoomContrastInactive YES`: the same table for an inactive window (its content at
        // `SidebarMetrics.inactiveContentAlpha`, the tint fainter): a record, the rule is the active window's.
        if UserDefaults.standard.bool(forKey: "RoomContrastInactive") {
            controller.activityOverride = false
            SpikeRunner.record("contrast_activity", "inactive")
        }

        // The fixture behind the window: borderless, the same frame, ordered just below it.
        let fixture = NSWindow(contentRect: window.frame, styleMask: .borderless, backing: .buffered, defer: false)
        fixture.isReleasedWhenClosed = false
        fixture.ignoresMouseEvents = true
        fixture.hasShadow = false
        let fixtureView = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        fixtureView.wantsLayer = true
        fixture.contentView = fixtureView
        defer { fixture.orderOut(nil) }

        // Probes: six heights down the sidebar, primary at the rows' title inset, secondary beside it.
        let sidebarView = controller.sidebarView
        sidebarView.bodyView?.isHidden = true
        defer { sidebarView.bodyView?.isHidden = false }
        var probes: [ContrastProbe] = []
        for fraction in [0.30, 0.42, 0.54, 0.66, 0.78, 0.90] {
            for secondary in [false, true] {
                let field = NSTextField(labelWithString: "████")
                field.font = secondary ? Typography.secondary : Typography.sidebarRow
                field.textColor = secondary ? Palette.sidebarSecondaryLabel : .labelColor
                field.sizeToFit()
                let x = SidebarMetrics.rowHorizontalInset + SidebarMetrics.rowContentInset + 26 + (secondary ? 120 : 0)
                field.setFrameOrigin(NSPoint(x: x, y: sidebarView.bounds.height * fraction))
                sidebarView.contentView.addSubview(field)
                probes.append(ContrastProbe(field: field, secondary: secondary))
            }
        }
        defer { for probe in probes { probe.field.removeFromSuperview() } }

        let scale = window.backingScaleFactor
        let pixelSize = CGSize(width: window.frame.width * scale, height: window.frame.height * scale)
        SpikeRunner.record("contrast_window", "\(NSStringFromRect(window.frame)) screens=\(NSScreen.screens.map { NSStringFromRect($0.frame) }) scale=\(scale) screen=\(window.screen?.localizedName ?? "?") probes=\(probes.count)")
        let opacities = (UserDefaults.standard.string(forKey: "RoomContrastOpacities") ?? "0.5,1.0").split(separator: ",").compactMap { Double($0) }
        // `-RoomContrastAlgorithms triadic,…` and `-RoomContrastColors #1E88E5,…` narrow a quick run.
        let algorithms = Set((UserDefaults.standard.string(forKey: "RoomContrastAlgorithms") ?? "").split(separator: ",").map(String.init))
        let colors = Set((UserDefaults.standard.string(forKey: "RoomContrastColors") ?? "").split(separator: ",").map(String.init))
        for wallpaper in WallpaperFixture.allCases {
            fixtureView.layer?.contents = wallpaper.image(size: pixelSize)
            fixtureView.layer?.contentsGravity = .resize
            fixture.setFrame(window.frame, display: true)
            // The fixture in front first, then Room's window over it (an `order(.below)` alone left it in front).
            fixture.orderFront(nil)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(200))
            SpikeRunner.record("contrast_order", "\(wallpaper.rawValue): room \(window.orderedIndex) fixture \(fixture.orderedIndex) key=\(window.isKeyWindow)")
            for dark in [false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                try? await Task.sleep(for: .milliseconds(500))
                // `-RoomContrastHold <s>`: the window holds a theme over this fixture for a screenshot of the
                // display taken from outside (the planner's computer use; Room never captures the screen).
                let hold = UserDefaults.standard.double(forKey: "RoomContrastHold")
                if hold > 0 {
                    applyTheme(["#FDD835"], algorithm: .triadic, opacity: 1)
                    SpikeRunner.record("contrast_hold", "\(dark ? "dark" : "light") \(wallpaper.rawValue) triadic #FDD835 1.00 for \(hold) s")
                    try? await Task.sleep(for: .seconds(hold))
                }
                // The untinted material first (the neutral window, Dia's look).
                controller.materialView.setTint(nil, animated: false)
                await recordContrast("\(dark ? "dark" : "light") \(wallpaper.rawValue) none - -", probes: probes, dark: dark)
                for opacity in opacities {
                    for algorithm in ThemeAlgorithm.allCases where algorithms.isEmpty || algorithms.contains(algorithm.rawValue) {
                        for color in Self.themeSamples where colors.isEmpty || colors.contains(color) {
                            // Floating derives nothing: two wells (the colour and the next sample) show its gradient.
                            let wells = algorithm == .floating ? [color, Self.themeSamples[(Self.themeSamples.firstIndex(of: color)! + 3) % Self.themeSamples.count]] : [color]
                            applyTheme(wells, algorithm: algorithm, opacity: opacity)
                            await recordContrast(String(format: "%@ %@ %@ %@ %.2f", dark ? "dark" : "light", wallpaper.rawValue, algorithm.rawValue, color, opacity),
                                                 probes: probes, dark: dark)
                        }
                    }
                }
            }
        }
        NSApp.appearance = nil
        restoreSpaceTint()
    }

    /// One sample: the window captured, each probe's text pixel against the material beside it.
    private func recordContrast(_ key: String, probes: [ContrastProbe], dark: Bool) async {
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(140))
        // Room's own window as the window server composites it. Its behind-window material comes out
        // the same over every fixture (5.2b: a window-list capture does not include what is behind;
        // the screen as displayed needs Screen Recording, which Room's spikes never ask for).
        guard let image = WindowSnapshot.capture(window), let pixels = SRGBPixels(image) else {
            return SpikeRunner.record("contrast", "\(key) no-capture")
        }
        let scale = CGFloat(image.width) / window.frame.width
        var primary: [Double] = [], secondary: [Double] = [], computedSecondary: [Double] = []
        var backgrounds: [SRGBPixels.RGB] = []
        for probe in probes {
            let frame = probe.field.convert(probe.field.bounds, to: nil)
            // The first glyph's middle (solid text colour) and the material 6 pt either side of the label.
            let text = pixels.at(window: CGPoint(x: frame.minX + 6, y: frame.midY), scale: scale, windowHeight: window.frame.height)
            let left = pixels.at(window: CGPoint(x: frame.minX - 6, y: frame.midY), scale: scale, windowHeight: window.frame.height)
            let right = pixels.at(window: CGPoint(x: frame.maxX + 6, y: frame.midY), scale: scale, windowHeight: window.frame.height)
            let background = SRGBPixels.RGB(r: (left.r + right.r) / 2, g: (left.g + right.g) / 2, b: (left.b + right.b) / 2)
            backgrounds.append(background)
            let ratio = SRGBPixels.contrast(text, background)
            if probe.secondary {
                secondary.append(ratio)
                // The colour as AppKit resolves it, composited over the measured material.
                var resolved = NSColor.black
                (dark ? NSAppearance(named: .darkAqua)! : NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
                    resolved = Palette.sidebarSecondaryLabel.usingColorSpace(.sRGB) ?? .black
                }
                let a = Double(resolved.alphaComponent)
                let blended = SRGBPixels.RGB(r: Double(resolved.redComponent) * a + background.r * (1 - a),
                                             g: Double(resolved.greenComponent) * a + background.g * (1 - a),
                                             b: Double(resolved.blueComponent) * a + background.b * (1 - a))
                computedSecondary.append(SRGBPixels.contrast(blended, background))
            } else {
                primary.append(ratio)
            }
        }
        let mean = backgrounds.reduce(SRGBPixels.RGB(r: 0, g: 0, b: 0)) { SRGBPixels.RGB(r: $0.r + $1.r, g: $0.g + $1.g, b: $0.b + $1.b) }
        let n = Double(max(backgrounds.count, 1))
        SpikeRunner.record("contrast", String(format: "%@ primary=%.2f/%.2f secondary=%.2f/%.2f secondary_computed=%.2f bg=%@",
                                              key, primary.min() ?? 0, primary.sorted()[primary.count / 2], secondary.min() ?? 0,
                                              secondary.sorted()[secondary.count / 2], computedSecondary.min() ?? 0,
                                              SRGBPixels.RGB(r: mean.r / n, g: mean.g / n, b: mean.b / n).hex))
    }

    // MARK: Inactive (task 5)

    /// The sidebar's content and tint active and inactive (a saturated swatch and the tint read from
    /// captures), and the traffic lights with Settings ▸ Appearance's grey window buttons off and on.
    private func inactiveChecks() async {
        NSApp.appearance = NSAppearance(named: .aqua)
        applyTheme(["#1E88E5"], algorithm: .triadic, opacity: 0.5)
        let swatch = NSTextField(labelWithString: "████")
        swatch.font = Typography.sidebarRow
        swatch.textColor = .systemRed
        swatch.sizeToFit()
        swatch.setFrameOrigin(NSPoint(x: 40, y: controller.sidebarView.bounds.height * 0.8))
        controller.sidebarView.contentView.addSubview(swatch)
        defer { swatch.removeFromSuperview() }
        var saturations: [Bool: (swatch: Double, tint: Double, luma: Double)] = [:]
        for active in [true, false] {
            controller.activityOverride = active
            try? await Task.sleep(for: .milliseconds(600))
            guard let image = WindowSnapshot.capture(window), let pixels = SRGBPixels(image) else { continue }
            let scale = CGFloat(image.width) / window.frame.width
            let frame = swatch.convert(swatch.bounds, to: nil)
            let s = pixels.at(window: CGPoint(x: frame.minX + 6, y: frame.midY), scale: scale, windowHeight: window.frame.height)
            let tint = pixels.at(window: CGPoint(x: window.frame.width - 3, y: window.frame.height * 0.5), scale: scale, windowHeight: window.frame.height)
            SpikeRunner.record("inactive_stops_\(active ? "active" : "inactive")", controller.materialView.debugTintStops.joined(separator: ", "))
            saturations[active] = (s.saturation, tint.chroma, tint.luminance)
            SpikeRunner.record("inactive_\(active ? "active" : "inactive")", "swatch=\(s.hex) sat=\(String(format: "%.3f", s.saturation)) chroma=\(String(format: "%.3f", s.chroma)) "
                + "tint=\(tint.hex) sat=\(String(format: "%.3f", tint.saturation)) chroma=\(String(format: "%.3f", tint.chroma))")
        }
        if let a = saturations[true], let i = saturations[false] {
            SpikeRunner.record("inactive_ratio", String(format: "swatch saturation %.3f → %.3f (×%.2f); tint chroma %.3f → %.3f (×%.2f)",
                                                        a.swatch, i.swatch, i.swatch / max(a.swatch, 0.001), a.tint, i.tint, i.tint / max(a.tint, 0.001)))
        }
        controller.activityOverride = true
        // The traffic lights: the close button's middle, with the grey option off and on.
        for mono in [false, true] {
            controller.monoTrafficLights = mono
            try? await Task.sleep(for: .milliseconds(500))
            guard let close = window.standardWindowButton(.closeButton), let image = WindowSnapshot.capture(window),
                  let pixels = SRGBPixels(image) else { continue }
            let scale = CGFloat(image.width) / window.frame.width
            let center = close.convert(NSPoint(x: close.bounds.midX, y: close.bounds.midY), to: nil)
            let p = pixels.at(window: center, scale: scale, windowHeight: window.frame.height)
            SpikeRunner.record("traffic_lights_\(mono ? "mono" : "colour")", "close=\(p.hex) sat=\(String(format: "%.3f", p.saturation))")
        }
        controller.monoTrafficLights = false
        restoreSpaceTint()
        NSApp.appearance = nil
    }
}

/// Captures a tracking menu's window, then ends the tracking (the matrix's menus).
@MainActor
final class MenuCapture: NSObject {
    let menu: NSMenu
    var image: CGImage?

    init(_ menu: NSMenu) { self.menu = menu }

    @objc func capture() {
        if let number = WindowSnapshot.ownWindowNumbers(layer: Int(CGWindowLevelForKey(.popUpMenuWindow))).first {
            image = WindowSnapshot.capture(windowNumber: number)
        }
        if image == nil { SpikeRunner.record("menu_capture", "no menu window of this process at the pop-up menu level") }
        menu.cancelTracking()
    }
}

/// A capture's pixels in sRGB, 8 bits per channel, and WCAG contrast.
struct SRGBPixels {
    struct RGB {
        var r: Double, g: Double, b: Double

        var hex: String { String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }
        /// WCAG relative luminance.
        var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        var saturation: Double { HSLColor(red: r, green: g, blue: b).saturation }
        /// max − min of the channels: colourfulness that does not inflate near white as HSL saturation does.
        var chroma: Double { max(r, g, b) - min(r, g, b) }
    }

    let width: Int, height: Int
    private let data: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        self.width = width
        self.height = height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            // Opaque: a screen capture's alpha is the windows', not what is displayed.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        data = buffer
    }

    /// The pixel under `point` in window coordinates (origin bottom-left).
    func at(window point: CGPoint, scale: CGFloat, windowHeight: CGFloat) -> RGB {
        let x = min(max(Int((point.x * scale).rounded()), 0), width - 1)
        let y = min(max(Int(((windowHeight - point.y) * scale).rounded()), 0), height - 1)
        let i = (y * width + x) * 4
        return RGB(r: Double(data[i]) / 255, g: Double(data[i + 1]) / 255, b: Double(data[i + 2]) / 255)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (high, low) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (high + 0.05) / (low + 0.05)
    }
}
#endif
