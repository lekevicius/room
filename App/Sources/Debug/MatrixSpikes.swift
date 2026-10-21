#if DEBUG
import AppKit
import SwiftUI
import Chrome
import Design
import Engine
import Model
import Sidebar
import Tabs
import UIKitCore

/// `matrix` (5.2a): the visual audit's screenshot matrix, for the user's eyes
/// (never an assertion). Every surface of the chrome on a sidebar of its own
/// (5.1a's `MotionFixture` on :8766), each state captured light and dark,
/// active and inactive (the window's `activityOverride`; a window of its own
/// such as Settings is inactive while the browser window is key), and one
/// contact sheet per surface with the tokens it uses printed above it.
/// Captures are of Room's own windows (`WindowSnapshot`, the popovers and
/// panels over a window composited with it; no screen recording).
/// - `-RoomSpikeSheetDirectory <dir>`: where the sheets go (default `research/screenshots/phase-5.2`).
/// - `-RoomMatrixSuffix <s>`: appended to each sheet's name (`-before` for the before run).
/// - `-RoomSpikeOnly rows,header,…`: the surfaces to shoot (default all): rows, header, footer,
///   palette, peek, split, toasts, downloads, sitepanel, prompts, library, settings, incognito,
///   extensions (the header with two extensions, one in the overflow menu); 5.2b's themes (the sidebar
///   under each algorithm), menus (B-37's key glyphs, from the menus' own windows) and spaceform (B-23);
///   `hairlines` (only when
///   named) reads the device pixels across each hairline instead.
/// `scripts/visual-matrix.sh` runs it on a throwaway state with search suggestions off.
extension SpikeRunner.Context {
    /// One column of the matrix.
    struct MatrixVariant {
        let dark: Bool
        let active: Bool
        var name: String { "\(dark ? "dark" : "light"), \(active ? "active" : "inactive")" }
    }

    static let matrixVariants = [MatrixVariant(dark: false, active: true), MatrixVariant(dark: false, active: false),
                                 MatrixVariant(dark: true, active: true), MatrixVariant(dark: true, active: false)]

    /// One row of a surface's sheet: how to get there, what to capture, how to leave.
    struct MatrixState {
        let label: String
        var setup: () async -> Void = {}
        /// The capture of one variant (the appearance and activity already applied).
        let shoot: () async -> CGImage?
        var teardown: () async -> Void = {}
    }

    private var matrixDirectory: URL {
        URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeSheetDirectory") ?? "research/screenshots/phase-5.2")
    }

    func visualMatrix() async {
        if UserDefaults.standard.bool(forKey: "RoomSuggestionsOff") { AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false } }
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty ? name != "hairlines" : only.contains(name) }
        try? FileManager.default.createDirectory(at: matrixDirectory, withIntermediateDirectories: true)
        window.setContentSize(NSSize(width: 1200, height: 780))
        controller.sidebarWidth = SidebarMetrics.defaultWidth
        // Downloads go to a throwaway folder, never ~/Downloads.
        let downloads = FileManager.default.temporaryDirectory.appending(path: "room-5.2-downloads-\(UUID().uuidString)")
        sidebar.store.settings.update { $0.downloadDirectory = downloads.path; $0.askWhereToSave = false }
        defer { try? FileManager.default.removeItem(at: downloads) }
        guard let first = store.spaces.first,
              let fixture = try? MotionFixture(store: store, first: first, base: Self.server + "find.html", window: sidebar.windowID) else {
            return SpikeRunner.record("error", "matrix: fixture")
        }
        await forgetTestSiteDecisions()
        try? await Task.sleep(for: .seconds(1))
        sidebar.select(fixture.today[2])
        if let page = tabs.contents(for: fixture.today[2]) {
            await waitLoaded(page, timeout: 15)
            page.load(URL(string: Self.server + "find.html?today-2-next")!)
            await waitLoaded(page, timeout: 15)
        }
        _ = await waitUntil(10) { self.sidebar.debugPreparedSpaces == self.store.spaces.count }
        await activate()
        try? await Task.sleep(for: .seconds(1))
        SpikeRunner.record("matrix_window", "\(NSStringFromSize(window.contentLayoutRect.size)) scale=\(window.backingScaleFactor) sidebar=\(controller.sidebarWidth)")
        SpikeRunner.record("extension_bar", NSStringFromRect(sidebar.extensionBar.frame))

        if runs("hairlines") { await hairlineReads(fixture: fixture) }
        let surfaces: [(String, String, [String], [MatrixState])] = [
            ("rows", "Sidebar rows", rowNotes, rowStates(fixture)),
            ("header", "Top bar and address row", headerNotes, headerStates()),
            ("footer", "Footer", footerNotes, footerStates()),
            ("palette", "Palette (each group)", paletteNotes, paletteStates()),
            ("peek", "Peek", peekNotes, peekStates()),
            ("split", "Split view", splitNotes, splitStates(fixture)),
            ("toasts", "Toasts", toastNotes, toastStates()),
            ("downloads", "Downloads popover", downloadNotes, downloadStates()),
            ("sitepanel", "Site panel", sitePanelNotes, sitePanelStates()),
            ("prompts", "The page's prompts", promptNotes, promptStates()),
            ("library", "Library", libraryNotes, libraryStates()),
            ("settings", "Settings (each section)", settingsNotes, settingsStates()),
            ("settingssheets", "Settings' sheets (5.7a)", settingsSheetNotes, settingsSheetStates()),
            ("incognito", "Incognito window", incognitoNotes, incognitoStates()),
            ("extensions", "Top bar with extensions (B-89, B-125)", extensionNotes, await extensionStates()),
            ("themes", "Space themes (each algorithm; 5.2b)", themeNotes, themeStates()),
            ("menus", "Menus' key glyphs (B-37; 5.2b)", menuNotes, menuStates()),
            ("spaceform", "The space form's theme (B-23; 5.2b)", spaceFormNotes, spaceFormStates()),
        ]
        // The name without its dash (an argument value starting with "-" would read as a flag).
        let suffix = (UserDefaults.standard.string(forKey: "RoomMatrixSuffix") ?? "").isEmpty ? "" : "-" + UserDefaults.standard.string(forKey: "RoomMatrixSuffix")!
        // 5.3b: `-RoomMatrixColumns modes|sizes` shoots the display options or the text sizes as the columns
        // (each light and dark, active) instead of light/dark × active/inactive; `-RoomMatrixPhase` names the sheets.
        let columns = matrixColumns()
        let phase = UserDefaults.standard.string(forKey: "RoomMatrixPhase") ?? "5.2"
        for (name, title, notes, states) in surfaces where runs(name) {
            var rows = states.map { SheetRow(label: $0.label, cells: []) }
            func shoot(_ state: MatrixState, _ column: MatrixColumn) async -> CGImage? {
                let image = await state.shoot()
                if let readBack = column.readBack, ["rows", "palette"].contains(name) {
                    SpikeRunner.record("clip_\(name)_\(column.key)", "\(state.label): " + readBack(name))
                }
                return image
            }
            if columns.contains(where: \.setupPerColumn) {
                // A text size is set before a state is set up (the palette measures its panel as it opens).
                for column in columns {
                    await column.apply()
                    try? await Task.sleep(for: .milliseconds(450))
                    for (index, state) in states.enumerated() {
                        await state.setup()
                        try? await Task.sleep(for: .milliseconds(300))
                        rows[index].cells.append(await shoot(state, column))
                        await state.teardown()
                    }
                }
            } else {
                for (index, state) in states.enumerated() {
                    await state.setup()
                    for column in columns {
                        await column.apply()
                        try? await Task.sleep(for: .milliseconds(450))
                        rows[index].cells.append(await shoot(state, column))
                    }
                    await state.teardown()
                }
            }
            NSApp.appearance = nil
            for session in AppDelegate.current?.windows.all ?? [] { session.controller.activityOverride = true }
            await resetMatrixColumns()
            let columnNotes = columns.first?.notes ?? []
            let sheet = ContactSheet(title: "Phase \(phase) — \(title)\(suffix.isEmpty ? "" : " (\(suffix.trimmingCharacters(in: CharacterSet(charactersIn: "-"))))")",
                                     columns: columns.map(\.name), notes: notes + columnNotes, rows: rows)
            let file = matrixDirectory.appending(path: "phase-\(phase)-\(name)\(suffix).png")
            SpikeRunner.record("sheet_\(name)", sheet.write(to: file) ? "\(file.lastPathComponent) \(rows.count) rows, \(rows.reduce(0) { $0 + $1.cells.compactMap { $0 }.count }) captures" : "failed")
        }
        controller.activityOverride = nil
    }

    /// Whether the matrix's current column is the active one (windows of their own read it).
    private static var matrixActiveValue = true
    var matrixActive: Bool {
        get { Self.matrixActiveValue }
        set { Self.matrixActiveValue = newValue }
    }

    // MARK: Captures

    /// `rect` (in `view`'s coordinates; `nil`: the whole window) of a capture of `target` (the browser
    /// window by default) with the app's popovers, panels and menus over it, scaled by `scale`.
    func matrixShot(_ rect: CGRect? = nil, of view: NSView? = nil, in target: NSWindow? = nil, scale: CGFloat = 0.5) async -> CGImage? {
        let target = target ?? window
        target.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(60))
        let others = NSApp.windows.filter {
            $0 !== target && $0.isVisible && $0.windowNumber > 0 && $0.frame.intersects(target.frame)
                && ($0.parent === target || $0.level.rawValue > target.level.rawValue || NSStringFromClass(Swift.type(of: $0)).contains("Popover"))
        }
        guard let image = others.isEmpty ? WindowSnapshot.capture(target) : WindowSnapshot.capture(target, with: others) else { return nil }
        var cropped = image
        if let rect {
            let inWindow = view.map { $0.convert(rect, to: nil) } ?? rect
            let pixels = CGFloat(image.width) / target.frame.width
            let height = target.frame.height
            let flipped = CGRect(x: inWindow.minX, y: height - inWindow.maxY, width: inWindow.width, height: inWindow.height)
                .intersection(CGRect(x: 0, y: 0, width: target.frame.width, height: height))
            let inPixels = CGRect(x: flipped.minX * pixels, y: flipped.minY * pixels, width: flipped.width * pixels, height: flipped.height * pixels).integral
            guard let part = image.cropping(to: inPixels) else { return nil }
            cropped = part
        }
        guard scale != 1 else { return cropped }
        let size = CGSize(width: (CGFloat(cropped.width) * scale).rounded(), height: (CGFloat(cropped.height) * scale).rounded())
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cropped }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    /// The sidebar's column in window coordinates, from `top` points under the window's top to `bottom` above its bottom.
    func sidebarRect(top: CGFloat = 0, height: CGFloat? = nil, fromBottom: Bool = false) -> CGRect {
        let view = controller.sidebarView
        let frame = view.convert(view.bounds, to: nil)
        let windowHeight = window.contentView?.bounds.height ?? frame.height
        let h = height ?? (windowHeight - top)
        let y = fromBottom ? frame.minY : windowHeight - top - h
        return CGRect(x: frame.minX, y: y, width: frame.width, height: h)
    }

    // MARK: Sidebar rows (B-112's shadow, B-115's folder glyph)

    private var rowNotes: [String] {
        [String(format: "Rows: SidebarMetrics.rowHeight %.0f pt, pill corner %.0f (Radius.large), insets %.0f / %.0f, favicon %.0f, title gap %.0f; Typography.sidebarRow 14 regular.",
                SidebarMetrics.rowHeight, SidebarMetrics.pillCornerRadius, SidebarMetrics.rowHorizontalInset, SidebarMetrics.rowContentInset,
                SidebarMetrics.faviconSize, SidebarMetrics.faviconTitleGap),
         String(format: "Selected pill: Palette.sidebarSelection (white 0.90 light / 0.12 dark); shadow opacity %.2f light / %.2f dark, radius %.1f, offset (0, %.1f); hover Palette.sidebarHover 6%%. "
                + "Folder glyph IconStyle.folder %.0f pt %@ in a %.0f × %.0f box.",
                SidebarMetrics.pillShadowOpacity, SidebarMetrics.pillShadowOpacityDark, SidebarMetrics.pillShadowRadius, SidebarMetrics.pillShadowOffset.height,
                IconStyle.folder.pointSize, IconStyle.folder.weight == .regular ? "regular" : "\(IconStyle.folder.weight)", SidebarMetrics.folderGlyphSize.width, SidebarMetrics.folderGlyphSize.height),
         "States: the selected Today tab; Pinned 0 changed (the dot) and hovered (reset icon); unloaded rows (50% icon, 70% title); the folder open; "
            + "then two Today tabs multi-selected (accent 18%) with the keyboard focus ring and the folder closed; then an Essential selected."]
    }

    func rowStates(_ fixture: MotionFixture) -> [MatrixState] {
        let rect = { self.sidebarRect(top: 96, height: 470) }
        return [
            MatrixState(label: "selected, changed + hover, unloaded, folder open", setup: {
                if let page = self.tabs.contents(for: fixture.pinned[0]) ?? self.store.entry(fixture.pinned[0]).flatMap({ self.tabs.loadInBackground($0) }) {
                    await self.waitLoaded(page, timeout: 10)
                    page.load(URL(string: Self.server + "find.html?pinned-0-away")!)
                    await self.waitLoaded(page, timeout: 10)
                }
                self.sidebar.select(fixture.today[2])
                self.sidebar.debugHover(fixture.pinned[0])
            }, shoot: { await self.matrixShot(rect(), scale: 0.75) }, teardown: { self.sidebar.debugHover(nil) }),
            MatrixState(label: "multi-selection, focus ring, folder closed", setup: {
                try? self.store.setFolderCollapsed(fixture.folder, true)
                self.sidebar.debugToggleSelection(fixture.today[0])
                self.sidebar.debugToggleSelection(fixture.today[1])
                self.sidebar.debugFocus(fixture.today[4])
                self.sidebar.debugHover(fixture.today[3])
            }, shoot: { await self.matrixShot(rect(), scale: 0.75) }, teardown: {
                self.sidebar.debugHover(nil)
                self.sidebar.debugFocus(nil)
                self.sidebar.debugClearMultiSelection()
                try? self.store.setFolderCollapsed(fixture.folder, false)
            }),
            MatrixState(label: "an Essential selected", setup: {
                if let essential = self.store.essentials(profile: self.sidebar.activeSpace?.profileID ?? UUID()).first?.id {
                    self.sidebar.select(essential)
                }
                try? await Task.sleep(for: .milliseconds(500))
            }, shoot: { await self.matrixShot(rect(), scale: 0.75) }, teardown: { self.sidebar.select(fixture.today[2]) }),
        ] + (UserDefaults.standard.string(forKey: "RoomMatrixColumns") == "modes" ? [modeRowState(fixture, rect: rect)] : [])
    }

    /// 5.3b's modes sheet: the marks Differentiate Without Colour changes, at rest (no hover): Pinned 0
    /// changed (left so by the first state), a muted Today tab, an Essential changed.
    private func modeRowState(_ fixture: MotionFixture, rect: @escaping () -> CGRect) -> MatrixState {
        let essential = { self.store.essentials(profile: self.sidebar.activeSpace?.profileID ?? UUID()).first?.id }
        return MatrixState(label: "changed dots (row, tile), a muted tab", setup: {
            if let id = essential(), let entry = self.store.entry(id),
               let page = self.tabs.contents(for: id) ?? self.tabs.loadInBackground(entry) {
                await self.waitLoaded(page, timeout: 10)
                page.load(URL(string: Self.server + "find.html?essential-away")!)
                await self.waitLoaded(page, timeout: 10)
            }
            if let entry = self.store.entry(fixture.today[1]), self.tabs.contents(for: entry.id) == nil { self.tabs.loadInBackground(entry) }
            try? await Task.sleep(for: .milliseconds(500))
            self.tabs.setMuted(true, entry: fixture.today[1])
            self.sidebar.select(fixture.today[2])
            try? await Task.sleep(for: .milliseconds(500))
        }, shoot: { await self.matrixShot(rect(), scale: 0.75) }, teardown: { self.tabs.setMuted(false, entry: fixture.today[1]) })
    }

    // MARK: Header and footer (B-110, B-89)

    private var headerNotes: [String] {
        [String(format: "Top bar: buttons SidebarMetrics.topBarButtonSize %.0f pt (min %.0f), group gap %.0f, symbols %.0f pt; address field %.0f pt, padding %.0f, corner %.0f.",
                SidebarMetrics.topBarButtonSize, SidebarMetrics.topBarButtonMinSize, SidebarMetrics.topBarGroupGap, IconStyle.control.pointSize,
                SidebarMetrics.addressFieldHeight, SidebarMetrics.addressFieldPadding, SidebarMetrics.pillCornerRadius),
         "Hover: ControlFeedback, the fill Palette.sidebarHover over Motion.fast; the address field's fill Palette.sidebarHover → Palette.addressFieldHover."]
    }

    func headerStates() -> [MatrixState] {
        let rect = { self.sidebarRect(top: 0, height: 100) }
        let back = { Self.view(in: self.controller.rootView, identifier: "nav-back") as? HoverButton }
        return [
            MatrixState(label: "rest", shoot: { await self.matrixShot(rect(), scale: 1) }),
            MatrixState(label: "Back hovered", setup: { back()?.feedback.setHovering(true, animated: false) },
                        shoot: { await self.matrixShot(rect(), scale: 1) }, teardown: { back()?.feedback.setHovering(false, animated: false) }),
            MatrixState(label: "address field hovered", setup: { self.hoverAddressField(true) },
                        shoot: { await self.matrixShot(rect(), scale: 1) }, teardown: { self.hoverAddressField(false) }),
        ]
    }

    private func hoverAddressField(_ on: Bool) {
        let field = sidebar.addressField
        guard let event = NSEvent.enterExitEvent(with: on ? .mouseEntered : .mouseExited, location: .zero, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) else { return }
        if on { field.mouseEntered(with: event) } else { field.mouseExited(with: event) }
    }

    private var footerNotes: [String] {
        [String(format: "Footer: SidebarMetrics.footerHeight %.0f; buttons SidebarMetrics.footerButtonSize %.0f (ControlMetrics.size), %.0f pt from the edges; glyphs IconStyle.control %.0f pt "
                + "(the arrow in the ring IconStyle.downloadProgress %.0f); space icons: %.0f pt glyphs in %.0f pt squares (the pitch), inactive alpha %.2f, the active one ×%.2f on a Palette.sidebarHover circle.",
                SidebarMetrics.footerHeight, SidebarMetrics.footerButtonSize, SidebarMetrics.rowHorizontalInset, IconStyle.control.pointSize, IconStyle.downloadProgress.pointSize,
                Self.spaceIconSize, Self.spaceIconPitch, Self.spaceIconInactiveAlpha, Self.spaceIconActiveScale),
         "Hover: ControlFeedback, the fill Palette.sidebarHover over Motion.fast on a ControlMetrics.cornerRadius square (the space icons also brighten)."]
    }

    static var spaceIconSize: CGFloat { SpaceIconMetrics.size }
    static var spaceIconPitch: CGFloat { SpaceIconMetrics.pitch }
    static var spaceIconInactiveAlpha: CGFloat { SpaceIconMetrics.inactiveAlpha }
    static var spaceIconActiveScale: CGFloat { SpaceIconMetrics.activeScale }

    func footerStates() -> [MatrixState] {
        let rect = { self.sidebarRect(height: SidebarMetrics.footerHeight + 8, fromBottom: true) }
        let plus = { Self.view(in: self.controller.rootView, identifier: "footer-plus") as? HoverButton }
        let inactiveIcon = { () -> NSView? in
            guard let row = Self.view(in: self.controller.rootView, identifier: "space-icons") else { return nil }
            return row.subviews.first { String(describing: Swift.type(of: $0)).contains("SpaceIcon") && $0.alphaValue < 1 }
        }
        let hoverIcon = { (on: Bool) in
            guard let icon = inactiveIcon() ?? (on ? nil : Self.view(in: self.controller.rootView, identifier: "space-icons")?.subviews.last),
                  let event = NSEvent.enterExitEvent(with: on ? .mouseEntered : .mouseExited, location: .zero, modifierFlags: [],
                                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: self.window.windowNumber,
                                                     context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) else { return }
            if on { icon.mouseEntered(with: event) } else { icon.mouseExited(with: event) }
        }
        return [
            MatrixState(label: "rest", shoot: { await self.matrixShot(rect(), scale: 1) }),
            MatrixState(label: "downloads hovered", setup: { self.sidebar.downloadsButton.feedback.setHovering(true, animated: false) },
                        shoot: { await self.matrixShot(rect(), scale: 1) },
                        teardown: { self.sidebar.downloadsButton.feedback.setHovering(false, animated: false) }),
            MatrixState(label: "space icon hovered", setup: { hoverIcon(true) }, shoot: { await self.matrixShot(rect(), scale: 1) },
                        teardown: { hoverIcon(false) }),
            MatrixState(label: "New Tab hovered", setup: { plus()?.feedback.setHovering(true, animated: false) },
                        shoot: { await self.matrixShot(rect(), scale: 1) }, teardown: { plus()?.feedback.setHovering(false, animated: false) }),
        ]
    }

    // MARK: Palette

    private var paletteNotes: [String] {
        [String(format: "PaletteMetrics.width %.0f, field %.0f pt (Typography.paletteField 18), rows %.0f pt, icons %.0f, list padding %.0f, group gap %.0f; "
                + "highlight Palette.sidebarMultiSelection (accent 18%%), Radius.medium; panel NSGlassEffectView, Radius.large. Suggestions off.",
                PaletteMetrics.width, PaletteMetrics.fieldHeight, PaletteMetrics.rowHeight, PaletteMetrics.iconSize, PaletteMetrics.listPadding, PaletteMetrics.groupGap)]
    }

    func paletteStates() -> [MatrixState] {
        guard let palette = AppDelegate.current?.activeWindow?.palette else { return [] }
        let rect = { () -> CGRect? in
            guard let panel = palette.debugPanel else { return nil }
            return panel.convert(panel.bounds, to: nil).insetBy(dx: -24, dy: -24)
        }
        func state(_ label: String, _ open: @escaping () -> Void) -> MatrixState {
            MatrixState(label: label, setup: {
                open()
                try? await Task.sleep(for: .milliseconds(500))
            }, shoot: { await self.matrixShot(rect(), scale: 0.5) }, teardown: {
                palette.dismiss()
                try? await Task.sleep(for: .milliseconds(300))
            })
        }
        return [
            state("empty (⌘T)") { palette.toggleNew() },
            state("\"today\": open tabs, pinned, search") { palette.toggleNew(); palette.setText("today") },
            state("\"127.0.0.1\": history, the URL") { palette.toggleNew(); palette.setText("127.0.0.1") },
            state("commands (>)") { palette.toggleCommands() },
            state("⌘L: the URL selected") { palette.toggleEdit(docked: false) },
        ]
    }

    // MARK: Peek, split

    private var peekNotes: [String] {
        [String(format: "PeekMetrics: %.0f%% of the card, corner %.0f, dim black %.0f%%, header %.0f pt, buttons %.0f; shadow %.0f at %.2f / %.2f.",
                PeekMetrics.sizeFraction * 100, PeekMetrics.cornerRadius, PeekMetrics.dimAlpha * 100, PeekMetrics.headerHeight,
                PeekMetrics.headerButtonSize, PeekMetrics.shadowRadius, PeekMetrics.shadowOpacityLight, PeekMetrics.shadowOpacityDark)]
    }

    func peekStates() -> [MatrixState] {
        [MatrixState(label: "a Peek over a Today tab", setup: {
            guard let page = self.tabs.current else { return }
            self.tabs.openPeek(URL(string: Self.server + "find.html?peek")!, from: page)
            if let shown = self.tabs.shownPeek { await self.waitLoaded(shown, timeout: 10) }
            try? await Task.sleep(for: .milliseconds(700))
        }, shoot: { await self.matrixShot(scale: 0.5) }, teardown: {
            _ = self.tabs.closeShownPeek()
            try? await Task.sleep(for: .milliseconds(500))
        })]
    }

    private var splitNotes: [String] {
        [String(format: "Split view: each pane a card (B-113): SplitMetrics.paneGap %.0f pt between them (= CardMetrics.inset), resizer %.0f pt over the gap, pane header %.0f pt; "
                + "each card CardMetrics corner %.0f, border %.0f px (Hairline), shadow radius %.0f at %.2f / %.2f.",
                SplitMetrics.paneGap, SplitMetrics.resizerHitWidth, SplitMetrics.paneHeaderHeight, CardMetrics.cornerRadius,
                CardMetrics.borderWidth, CardMetrics.shadowRadius, CardMetrics.shadowOpacityLight, CardMetrics.shadowOpacityDark)]
    }

    func splitStates(_ fixture: MotionFixture) -> [MatrixState] {
        func state(_ label: String, layout: SplitLayout) -> MatrixState {
            MatrixState(label: label, setup: {
                self.sidebar.select(fixture.today[2])
                if let entry = self.store.entry(fixture.today[3]), self.tabs.contents(for: entry.id) == nil { self.tabs.loadInBackground(entry) }
                try? await Task.sleep(for: .milliseconds(500))
                self.sidebar.joinIntoSplit(fixture.today[3], with: fixture.today[2])
                try? await Task.sleep(for: .milliseconds(400))
                if layout != .hbox { self.sidebar.setSplitLayout(layout) }
                try? await Task.sleep(for: .milliseconds(700))
            }, shoot: { await self.matrixShot(scale: 0.5) }, teardown: {
                self.sidebar.unsplit()
                self.sidebar.select(fixture.today[2])
                try? await Task.sleep(for: .milliseconds(500))
            })
        }
        return [state("two panes side by side", layout: .hbox), state("two panes stacked", layout: .vbox)]
    }

    // MARK: Toasts, downloads, the site panel, prompts

    private var toastNotes: [String] {
        [String(format: "Toasts: spring Motion.toast %.2f s; Timing.toast %.0f s, with a button %.0f s; the capsule on the glass at the sidebar's bottom.",
                Motion.toast.duration, Timing.toast, Timing.toastWithAction)]
    }

    func toastStates() -> [MatrixState] {
        guard let toasts = AppDelegate.current?.activeWindow?.toasts else { return [] }
        let rect = { self.sidebarRect(height: 160, fromBottom: true) }
        func state(_ label: String, _ toast: Toast) -> MatrixState {
            MatrixState(label: label, setup: {
                toasts.show(toast)
                try? await Task.sleep(for: .milliseconds(900))
            }, shoot: { await self.matrixShot(rect(), scale: 1) }, teardown: {
                toasts.dismiss(id: toast.id)
                try? await Task.sleep(for: .milliseconds(500))
            })
        }
        return [
            state("plain", Toast(id: "matrix-plain", symbol: .copyURL, message: "Copied URL", duration: 60)),
            state("with a button", Toast(id: "matrix-action", symbol: .clearToday, message: "3 tabs closed",
                                         action: Toast.Action(title: "Undo") {}, duration: 60)),
        ]
    }

    private var downloadNotes: [String] {
        ["Downloads popover: NSPopover above the footer's button, DownloadsMetrics.popoverWidth 320; rows 32 pt icons, Typography.row names, Typography.secondary detail; hover Palette.sidebarHover, Radius.small.",
         "States: empty; one finished and one in progress (a 6 MB file at 1 MB/s from :8766)."]
    }

    func downloadStates() -> [MatrixState] {
        guard let downloads = AppDelegate.current?.downloads else { return [] }
        func open() async {
            if !downloads.popover.isShown { downloads.togglePopover() }
            _ = await waitUntil(3) { downloads.popover.isShown }
            try? await Task.sleep(for: .milliseconds(500))
        }
        func close() async {
            downloads.popover.close()
            try? await Task.sleep(for: .milliseconds(300))
        }
        let rect = { self.sidebarRect(height: 360, fromBottom: true).insetBy(dx: 0, dy: 0).union(self.sidebarRect(height: 360, fromBottom: true).offsetBy(dx: 120, dy: 0)) }
        return [
            MatrixState(label: "empty", setup: { await open() }, shoot: { await self.matrixShot(rect(), scale: 0.75) }, teardown: { await close() }),
            MatrixState(label: "finished, in progress", setup: {
                if let page = await self.openTest("downloads.html") {
                    await self.click(page, "#small")
                    try? await Task.sleep(for: .milliseconds(800))
                    await self.click(page, "#slow")
                    _ = await self.waitUntil(5) { downloads.list.rows.count >= 2 }
                    try? await Task.sleep(for: .milliseconds(1200))
                }
                await open()
            }, shoot: { await self.matrixShot(rect(), scale: 0.75) }, teardown: {
                await close()
                for row in downloads.list.rows { downloads.list.cancel(row.item.id) }
            }),
        ]
    }

    private var sitePanelNotes: [String] {
        [String(format: "Site panel: NSPopover on the site button, SitePanelMetrics.width %.0f; the host as the headline, the connection line, Permissions menus, Cookies and site data.",
                SitePanelMetrics.width)]
    }

    func sitePanelStates() -> [MatrixState] {
        guard let app = AppDelegate.current else { return [] }
        return [MatrixState(label: "permissions.html", setup: {
            _ = await self.openTest("permissions.html")
            app.showSitePanel()
            _ = await self.waitUntil(3) { app.sitePanel.isShown }
            try? await Task.sleep(for: .milliseconds(500))
        }, shoot: {
            let rect = self.sidebarRect(top: 0, height: 560).union(self.sidebarRect(top: 0, height: 560).offsetBy(dx: 200, dy: 0))
            return await self.matrixShot(rect, scale: 0.75)
        }, teardown: {
            app.sitePanel.close()
            try? await Task.sleep(for: .milliseconds(300))
        })]
    }

    private var promptNotes: [String] {
        [String(format: "Dialog sheet: PromptMetrics.dialogWidth %.0f, top inset %.0f, padding %.0f, spacing %.0f, NSGlassEffectView Radius.large, the page dimmed %.2f / %.2f; "
                + "permission popover %.0f pt on the site button; certificate interstitial %.0f pt column, icon %.0f pt.",
                PromptMetrics.dialogWidth, PromptMetrics.dialogTopInset, PromptMetrics.dialogPadding, PromptMetrics.dialogSpacing,
                PromptMetrics.dimAlphaLight, PromptMetrics.dimAlphaDark, PromptMetrics.permissionWidth, PromptMetrics.interstitialWidth,
                PromptMetrics.interstitialIconSize)]
    }

    func promptStates() -> [MatrixState] {
        [
            MatrixState(label: "confirm() sheet", setup: {
                guard let page = await self.openTest("dialogs.html") else { return }
                Task { await self.click(page, "#confirm") }
                _ = await self.waitForDialog()
            }, shoot: { await self.matrixShot(scale: 0.5) }, teardown: {
                self.pressEscape()
                _ = await self.waitUntil(5) { self.prompts.visibleDialog == nil }
            }),
            MatrixState(label: "permission popover", setup: {
                guard let page = await self.openTest("permissions.html") else { return }
                Task { await self.click(page, "#geo") }
                _ = await self.waitUntil(8) { self.prompts.visiblePermission != nil }
                try? await Task.sleep(for: .milliseconds(500))
            }, shoot: {
                let rect = self.sidebarRect(top: 0, height: 360).union(self.sidebarRect(top: 0, height: 360).offsetBy(dx: 220, dy: 0))
                return await self.matrixShot(rect, scale: 0.75)
            }, teardown: {
                self.button(identifier: "permission-deny", in: self.presenter?.permissionView)?.performClick(nil)
                _ = await self.waitUntil(5) { self.prompts.visiblePermission == nil }
            }),
            MatrixState(label: "certificate interstitial", setup: {
                _ = self.session.newPage(URL(string: Self.secureServer + "secure.html")!)
                _ = await self.waitForDialog()
                try? await Task.sleep(for: .milliseconds(500))
            }, shoot: { await self.matrixShot(scale: 0.5) }),
        ]
    }

    // MARK: Library, Settings, the incognito window

    private var libraryNotes: [String] {
        [String(format: "Library: LibraryMetrics search field %.0f, sections %.0f, days %.0f, items %.0f pt, buttons %.0f, chips %.0f.",
                LibraryMetrics.searchFieldHeight, LibraryMetrics.sectionRowHeight, LibraryMetrics.dayRowHeight, LibraryMetrics.itemRowHeight,
                LibraryMetrics.buttonSize, LibraryMetrics.chipHeight)]
    }

    func libraryStates() -> [MatrixState] {
        guard let app = AppDelegate.current else { return [] }
        return [MatrixState(label: "the Library", setup: {
            if !app.isLibraryShown { app.toggleLibrary(nil) }
            try? await Task.sleep(for: .milliseconds(800))
        }, shoot: { await self.matrixShot(self.sidebarRect(), scale: 0.5) }, teardown: {
            if app.isLibraryShown { app.toggleLibrary(nil) }
            try? await Task.sleep(for: .milliseconds(300))
        })]
    }

    private var settingsNotes: [String] {
        [String(format: "Settings: toolbar tabs, %.0f pt (SettingsWindowFit.contentWidth), every pane %.0f pt tall at most (SettingsWindowFit.preferredContentHeight; ", SettingsWindowFit.contentWidth, SettingsWindowFit.preferredContentHeight)
            + "less on a smaller display) and scrolling inside; each a grouped SwiftUI Form (Shortcuts an AppKit table). "
            + "Inactive: the browser window key, Settings behind it."]
    }

    private var settingsSheetNotes: [String] {
        [String(format: "Privacy's sheets (5.7a): filter lists, custom rules, allowed sites %.0f × %.0f (ContentBlockingSheetMetrics); ", ContentBlockingSheetMetrics.width, ContentBlockingSheetMetrics.height)
            + String(format: "site permissions %.0f × %.0f (SitePermissionsMetrics), Safari's Websites layout. Each shot alone, as the sheet's own window.", SitePermissionsMetrics.width, SitePermissionsMetrics.height)]
    }

    func settingsSheetStates() -> [MatrixState] {
        guard let app = AppDelegate.current, let store = app.store else { return [] }
        let blocking = app.contentBlocking
        var sheets: [(String, () -> NSViewController?)] = []
        if let blocking {
            for which in [ContentBlockingSettingsView.Sheet.lists, .rules, .sites] {
                sheets.append((which.rawValue.capitalized, {
                    NSHostingController(rootView: ContentBlockingSheet(controller: blocking, which: which) {})
                }))
            }
        }
        sheets.append(("Site permissions", {
            NSHostingController(rootView: SitePermissionsSheet(sidebar: store.sidebar, profiles: app.profileServices()) {})
        }))
        var sheetWindow: NSWindow?
        return sheets.map { label, make in
            MatrixState(label: label, setup: {
                app.showSettings(section: .privacy)
                try? await Task.sleep(for: .milliseconds(500))
                guard let settings = app.debugSettingsWindow?.window, let content = make() else { return }
                let sheet = NSWindow(contentViewController: content)
                sheetWindow = sheet
                settings.beginSheet(sheet, completionHandler: nil)
                try? await Task.sleep(for: .milliseconds(800))
            }, shoot: {
                guard let sheet = sheetWindow, let settings = app.debugSettingsWindow?.window else { return nil }
                if self.matrixActive { settings.makeKeyAndOrderFront(nil) } else { self.window.makeKeyAndOrderFront(nil) }
                try? await Task.sleep(for: .milliseconds(400))
                return await self.matrixShot(in: sheet, scale: 0.5)
            }, teardown: {
                if let sheet = sheetWindow { app.debugSettingsWindow?.window?.endSheet(sheet) }
                sheetWindow = nil
                app.debugSettingsWindow?.window?.orderOut(nil)
                self.window.makeKeyAndOrderFront(nil)
            })
        }
    }

    func settingsStates() -> [MatrixState] {
        guard let app = AppDelegate.current else { return [] }
        return SettingsWindowController.Section.allCases.map { section in
            MatrixState(label: section.title, setup: {
                app.showSettings(section: section)
                try? await Task.sleep(for: .milliseconds(800))
            }, shoot: {
                guard let settings = app.debugSettingsWindow?.window else { return nil }
                if self.matrixActive { settings.makeKeyAndOrderFront(nil) } else { self.window.makeKeyAndOrderFront(nil) }
                try? await Task.sleep(for: .milliseconds(400))
                return await self.matrixShot(in: settings, scale: 0.5)
            }, teardown: {
                app.debugSettingsWindow?.window?.orderOut(nil)
                self.window.makeKeyAndOrderFront(nil)
            })
        }
    }

    private var incognitoNotes: [String] {
        ["The incognito window: Palette.incognitoAppearance (Dark Aqua whatever the system's), tint \(Palette.incognitoTintHex), "
            + String(format: "the \"Incognito\" label WindowMetrics.incognitoLabelHeight %.0f. Its own window: light and dark columns are the same window.", WindowMetrics.incognitoLabelHeight)]
    }

    func incognitoStates() -> [MatrixState] {
        guard let app = AppDelegate.current else { return [] }
        var incognito: WindowSession? { app.windows.all.first { $0.isIncognito } }
        return [MatrixState(label: "a new incognito window", setup: {
            app.newIncognitoWindow(nil)
            _ = await self.waitUntil(5) { incognito != nil }
            if let session = incognito, let page = session.tabs?.current { await self.waitLoaded(page, timeout: 5) }
            try? await Task.sleep(for: .milliseconds(800))
        }, shoot: {
            guard let session = incognito, let target = session.window else { return nil }
            session.controller.activityOverride = self.matrixActive
            return await self.matrixShot(in: target, scale: 0.5)
        }, teardown: {
            incognito?.window?.performClose(nil)
            _ = await self.waitUntil(5) { incognito == nil }
            self.window.makeKeyAndOrderFront(nil)
        })]
    }

    // MARK: The top bar with extensions (B-89, B-125)

    private var extensionNotes: [String] {
        ["The 3.6 fixture extension and a second one (its action without an icon: the puzzle-piece placeholder), loaded unpacked; "
            + "rows: both pinned at the default sidebar width (300), then the fixture unpinned (the overflow button)."]
    }

    func extensionStates() async -> [MatrixState] {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        guard only.isEmpty || only.contains("extensions"), let app = AppDelegate.current, let center = app.extensions,
              let section = center.sections.first else { return [] }
        let field = sidebar.extensionBar
        let rect = { self.sidebarRect(top: 0, height: 100) }
        var fixtureID: String?
        return [
            MatrixState(label: "two pinned", setup: {
                _ = await self.waitUntil(10) { section.extensions.isReady }
                let fixture = SpikeRunner.pagesDirectory.deletingLastPathComponent().appending(path: "phase-3.6/extension", directoryHint: .isDirectory)
                fixtureID = try? await section.extensions.loadUnpacked(at: fixture)
                let root = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomStateDirectory") ?? NSTemporaryDirectory())
                    .appending(path: "second-extension", directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try? #"{"manifest_version": 3, "name": "Room 4.5 second", "version": "1.0", "action": {"default_title": "Second"}}"#
                    .write(to: root.appending(path: "manifest.json"), atomically: true, encoding: .utf8)
                _ = try? await section.extensions.loadUnpacked(at: root)
                _ = await self.waitUntil(5) { field.extensionActionIDs.count == 2 }
                try? await Task.sleep(for: .milliseconds(800))
                SpikeRunner.record("matrix_extensions_two", "bar=\(NSStringFromRect(field.frame)) pinned=\(field.extensionActionIDs.count) "
                    + "shown=\(field.subviews.filter { !$0.isHidden && $0.accessibilityIdentifier().hasPrefix("extension-action") }.count) overflow_button=\(field.overflowButtonView != nil)")
            }, shoot: { await self.matrixShot(rect(), scale: 1) }),
            MatrixState(label: "one unpinned: the overflow button", setup: {
                if let id = fixtureID, let item = center.sections.first?.installed.first(where: { $0.id == id }) {
                    center.setPinned(false, item, in: section)
                }
                _ = await self.waitUntil(5) { field.overflowButtonView != nil }
                try? await Task.sleep(for: .milliseconds(600))
            }, shoot: { await self.matrixShot(rect(), scale: 1) }),
        ]
    }

    // MARK: Hairlines (task 3: 1 px at the display's scale)

    /// The device pixels across each hairline, read from a capture at the backing scale: the card's
    /// border, the status pill's, the split's divider and the Today separator. A tool for the
    /// record (spike-results), not an assertion.
    private func hairlineReads(fixture: MotionFixture) async {
        NSApp.appearance = NSAppearance(named: .aqua)
        try? await Task.sleep(for: .milliseconds(500))
        SpikeRunner.record("hairline_scale", "backing \(window.backingScaleFactor)× (screen \(window.screen?.localizedName ?? "?"))")
        // The card's trailing edge at mid height: the material, the border, the page.
        let card = controller.rootView.currentLayout.card
        let cardInWindow = controller.rootView.convert(card, to: nil)
        await profile("card_border_trailing", across: CGPoint(x: cardInWindow.maxX, y: cardInWindow.midY), horizontal: true)
        await profile("card_border_bottom", across: CGPoint(x: cardInWindow.midX, y: cardInWindow.minY), horizontal: false)
        // The Today separator (Clear's line) in the sidebar.
        if let line = Self.firstView(in: controller.sidebarView, where: {
            (($0 as? NSBox)?.boxType == .separator || $0 is HairlineView) && !$0.isHiddenOrHasHiddenAncestor
        }) {
            let frame = line.convert(line.bounds, to: nil)
            await profile("today_separator", across: CGPoint(x: frame.midX, y: frame.midY), horizontal: false)
        }
        // The split's divider.
        sidebar.select(fixture.today[2])
        if let entry = store.entry(fixture.today[3]), tabs.contents(for: entry.id) == nil { tabs.loadInBackground(entry) }
        try? await Task.sleep(for: .milliseconds(500))
        sidebar.joinIntoSplit(fixture.today[3], with: fixture.today[2])
        try? await Task.sleep(for: .milliseconds(900))
        let middle = controller.rootView.convert(controller.rootView.currentLayout.card, to: nil)
        await profile("split_divider", across: CGPoint(x: middle.midX, y: middle.midY), horizontal: true, radius: 12)
        sidebar.unsplit()
        sidebar.select(fixture.today[2])
        try? await Task.sleep(for: .milliseconds(500))
        NSApp.appearance = nil
    }

    /// Luma (0–255) of the pixels across `point` (window coordinates): `radius` points either side.
    private func profile(_ name: String, across point: CGPoint, horizontal: Bool, radius: CGFloat = 4) async {
        guard let image = WindowSnapshot.capture(window), let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return SpikeRunner.record("hairline_\(name)", "no capture")
        }
        let scale = CGFloat(image.width) / window.frame.width
        let px = Int((point.x * scale).rounded()), py = Int(((window.frame.height - point.y) * scale).rounded())
        let span = Int(radius * scale)
        var lumas: [Int] = []
        for offset in -span...span {
            let x = horizontal ? px + offset : px, y = horizontal ? py : py + offset
            guard x >= 0, y >= 0, x < image.width, y < image.height else { continue }
            let p = bytes + y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
            // BGRA (the window server's) or RGBA: luma from the three colour bytes either way is close enough for a profile.
            lumas.append(Int((Double(p[0]) + Double(p[1]) + Double(p[2])) / 3))
        }
        SpikeRunner.record("hairline_\(name)", "\(horizontal ? "x" : "y") across \(horizontal ? px : py) ±\(span) px at \(scale)×: \(lumas.map(String.init).joined(separator: " "))")
    }

    static func firstView(in root: NSView, where match: (NSView) -> Bool) -> NSView? {
        if match(root) { return root }
        for subview in root.subviews {
            if let found = firstView(in: subview, where: match) { return found }
        }
        return nil
    }
}
#endif
