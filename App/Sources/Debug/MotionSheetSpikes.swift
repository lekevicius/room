#if DEBUG
import AppKit
import Chrome
import Design
import Sidebar
import UIKitCore

/// `motionsheet` (5.1b): the review sheet's contact sheets, for the user's
/// eyes (never an assertion). On the motion harness's own sidebar, in light
/// and dark:
/// - `phase-5.1b-controls.png`: each control of the top bar and the footer
///   (B-111) at rest, hovered, pressed (the press held at its end) and
///   pressed under Reduce Motion, cropped from captures of the window;
/// - `phase-5.1b-reveal.png`: the hidden sidebar (B-114) without traffic
///   lights, the reveal's slide frozen at 0, 25, 50 and 75% of
///   `Motion.revealIn`, and in place; the Reduce Motion fade at the same points.
/// The tokens are printed beside them. Captures are of Room's own window
/// (`CGWindowListCreateImage` with the window's id; no screen recording).
/// `-RoomSpikeSheetDirectory <dir>` (default `research/screenshots/phase-5.1`).
extension SpikeRunner.Context {
    func motionSheet() async {
        if UserDefaults.standard.bool(forKey: "RoomSuggestionsOff") { AppDelegate.current?.store?.settings.update { $0.searchSuggestions = false } }
        let directory = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeSheetDirectory") ?? "research/screenshots/phase-5.1")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let first = store.spaces.first,
              let fixture = try? MotionFixture(store: store, first: first, base: "http://127.0.0.1:8766/find.html", window: sidebar.windowID) else {
            return SpikeRunner.record("error", "motionsheet: fixture")
        }
        try? await Task.sleep(for: .seconds(1))
        sidebar.select(fixture.today[2])
        if let page = tabs.contents(for: fixture.today[2]) {
            await waitLoaded(page, timeout: 15)
            // A second page, so Back is enabled (its hover and press show).
            page.load(URL(string: "http://127.0.0.1:8766/find.html?today-2-next")!)
            await waitLoaded(page, timeout: 15)
        }
        _ = await waitUntil(10) { self.sidebar.debugPreparedSpaces == self.store.spaces.count }
        controller.activityOverride = true
        await activate()
        try? await Task.sleep(for: .seconds(1))

        var controlRows: [SheetRow] = []
        var revealRows: [SheetRow] = []
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            try? await Task.sleep(for: .milliseconds(800))
            controlRows += await controlCells(dark: dark)
            revealRows += await revealCells(dark: dark, reduced: false)
            revealRows += await revealCells(dark: dark, reduced: true)
        }
        NSApp.appearance = nil
        Motion.preferences = .system
        let controls = ContactSheet(
            title: "Phase 5.1b — hover and press (B-111), light and dark",
            columns: ["rest", "hover", "pressed", "pressed, Reduce Motion"],
            notes: [
                "Hover: the fill fades to Palette.sidebarHover (6% label colour) over Motion.fast 0.12 s ease-out (the address field: Palette.sidebarHover → Palette.addressFieldHover, 10%); "
                    + "space icons brighten from SpaceIconMetrics.inactiveAlpha to 1.",
                String(format: "Press: scale Motion.pressScale %.2f about the centre over Motion.pressIn %.2f s ease-out; release: spring Motion.pressRelease %.2f s, bounce %.2f. "
                    + "Reduce Motion: no scale, alpha × Motion.pressReducedAlpha %.1f over %.2f s.", Motion.pressScale, Motion.pressIn,
                    Motion.pressRelease.duration, Motion.pressRelease.bounce, Motion.pressReducedAlpha, Motion.fast),
                "Captured from Room's window (2× pixels), the press held at its end; the address field has no press state.",
            ],
            rows: controlRows)
        let reveal = ContactSheet(
            title: "Phase 5.1b — the hidden sidebar's reveal (B-114: no traffic-light pill), light and dark",
            columns: ["hidden", "0%", "25%", "50%", "75%", "in place"],
            notes: [
                String(format: "Reveal: Timing.revealDwell %.0f ms in the 4 pt band (was 150), then the slide Motion.revealIn %.0f ms ease-out (was Motion.medium 250); "
                    + "out: Motion.revealOut %.0f ms ease-in after Timing.revealGrace %.0f ms.", Timing.revealDwell * 1000, Motion.revealIn * 1000,
                    Motion.revealOut * 1000, Timing.revealGrace * 1000),
                "The traffic lights fade in with the slide (ease-in, the same length) and out with it; hidden, there are none (no floating cluster).",
                "Frames at 0, 25, 50 and 75% of the slide's time, set from the curves (the overlay's origin on ease-out, the lights' alpha on ease-in); Reduce Motion: the overlay's opacity on ease-out.",
            ],
            rows: revealRows)
        for (sheet, name) in [(controls, "phase-5.1b-controls"), (reveal, "phase-5.1b-reveal")] {
            let file = directory.appending(path: "\(name).png")
            SpikeRunner.record("sheet", sheet.write(to: file) ? "\(file.path) \(sheet.rows.count) rows" : "failed: \(name)")
        }
    }

    // MARK: The controls

    private func controlCells(dark: Bool) async -> [SheetRow] {
        guard let root = window.contentView else { return [] }
        let appearance = dark ? "dark" : "light"
        var targets: [(String, NSView)] = []
        for (identifier, label) in [("sidebar-toggle", "Sidebar toggle"), ("extension-overflow", "Extensions"), ("nav-back", "Back"),
                                    ("nav-forward", "Forward"), ("nav-reload", "Reload"), ("address-field", "Address field"),
                                    ("downloads", "Downloads"), ("footer-plus", "New Tab")] {
            if let view = Self.view(in: root, identifier: identifier), !view.isHiddenOrHasHiddenAncestor { targets.append((label, view)) }
        }
        if let row = Self.view(in: root, identifier: "space-icons") {
            let icons = row.subviews.filter { String(describing: Swift.type(of: $0)).contains("SpaceIcon") }
            if let inactive = icons.first(where: { $0.alphaValue < 1 }) { targets.append(("Space icon (inactive)", inactive)) }
        }
        var rows: [SheetRow] = []
        for (label, view) in targets {
            var cells: [CGImage?] = []
            let rect = view.convert(view.bounds, to: nil).insetBy(dx: -8, dy: -6)
            cells.append(await crop(rect))
            hover(view, true)
            try? await Task.sleep(for: .milliseconds(300))
            cells.append(await crop(rect))
            if view.accessibilityIdentifier() == "address-field" {
                cells += [nil, nil]
            } else {
                for reduced in [false, true] {
                    Motion.preferences = .fixed(reduceMotion: reduced)
                    press(view, true)
                    try? await Task.sleep(for: .milliseconds(300))
                    cells.append(await crop(rect))
                    press(view, false)
                    try? await Task.sleep(for: .milliseconds(700))
                }
                Motion.preferences = .fixed(reduceMotion: false)
            }
            hover(view, false)
            try? await Task.sleep(for: .milliseconds(300))
            rows.append(SheetRow(label: "\(label), \(appearance)", cells: cells))
        }
        SpikeRunner.record("sheet_controls_\(appearance)", targets.map(\.0).joined(separator: ", "))
        return rows
    }

    private func hover(_ view: NSView, _ on: Bool) {
        if let button = view as? HoverButton { return button.feedback.setHovering(on) }
        if let downloads = view as? DownloadsButton { return downloads.feedback.setHovering(on) }
        guard let event = NSEvent.enterExitEvent(with: on ? .mouseEntered : .mouseExited, location: .zero, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) else { return }
        if on { view.mouseEntered(with: event) } else { view.mouseExited(with: event) }
    }

    private func press(_ view: NSView, _ down: Bool) {
        if let button = view as? HoverButton { return button.highlight(down) }
        if let downloads = view as? DownloadsButton { return downloads.feedback.setPressed(down) }
        // A space icon: a press, and a release outside it (no click).
        let location = down ? view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil) : NSPoint(x: -100, y: -100)
        guard let event = NSEvent.mouseEvent(with: down ? .leftMouseDown : .leftMouseUp, location: location, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: down ? 1 : 0) else { return }
        if down { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
    }

    // MARK: The reveal

    private func revealCells(dark: Bool, reduced: Bool) async -> [SheetRow] {
        let root = controller.rootView
        Motion.preferences = .fixed(reduceMotion: reduced)
        defer { Motion.preferences = .fixed(reduceMotion: false) }
        controller.isSidebarOpen = false
        try? await Task.sleep(for: .milliseconds(600))
        let width = root.overlayFrame.maxX + 60
        let rect = CGRect(x: 0, y: 0, width: width, height: root.bounds.height)
        var cells: [CGImage?] = [await crop(rect, scale: 0.5)]
        // Pausing Core Animation did not hold the glass overlay's slide in a capture (its position
        // rendered in place while the traffic lights' fade froze), so the frames are set from the
        // tokens' curves: the overlay's origin on ease-out, the traffic lights' alpha on ease-in.
        controller.reveal.togglePin()
        _ = await waitUntil(2) { controller.reveal.isShown && !root.isOverlayAnimating }
        let overlay = root.overlayView
        let rest = overlay.frame.origin
        _ = rest.y
        let away = rest.x - (overlay.frame.maxX + Spacing.l)
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        for fraction in [0.0, 0.25, 0.5, 0.75] {
            let progress = Self.curve(fraction, CAMediaTimingFunction(name: .easeOut))
            if reduced {
                overlay.alphaValue = progress
            } else {
                // A translation on the layer (a layout pass puts the frame back while nothing animates).
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                overlay.layer?.transform = CATransform3DMakeTranslation((away - rest.x) * (1 - progress), 0, 0)
                CATransaction.commit()
            }
            let lights = Self.curve(fraction, CAMediaTimingFunction(name: .easeIn))
            buttons.forEach { $0.alphaValue = lights }
            try? await Task.sleep(for: .milliseconds(150))
            cells.append(await crop(rect, scale: 0.5))
        }
        overlay.layer?.transform = CATransform3DIdentity
        overlay.alphaValue = 1
        buttons.forEach { $0.alphaValue = 1 }
        try? await Task.sleep(for: .milliseconds(300))
        cells.append(await crop(rect, scale: 0.5))
        SpikeRunner.record("sheet_reveal_\(dark ? "dark" : "light")\(reduced ? "_reduced" : "")", "shown=\(controller.reveal.isShown)")
        controller.reveal.togglePin()
        _ = await waitUntil(2) { !root.isOverlayAnimating }
        controller.isSidebarOpen = true
        try? await Task.sleep(for: .milliseconds(500))
        return [SheetRow(label: "\(dark ? "dark" : "light")\(reduced ? ", Reduce Motion" : "")", cells: cells)]
    }

    /// A timing curve's progress at time fraction `x` (its cubic Bézier solved for x).
    static func curve(_ x: Double, _ function: CAMediaTimingFunction) -> Double {
        var a = [Float](repeating: 0, count: 2), b = [Float](repeating: 0, count: 2)
        function.getControlPoint(at: 1, values: &a)
        function.getControlPoint(at: 2, values: &b)
        func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double { 3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t }
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if bezier(mid, Double(a[0]), Double(b[0])) < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, Double(a[1]), Double(b[1]))
    }

    // MARK: Captures

    /// `rect` (window coordinates, points, origin bottom-left) of a capture of Room's own window.
    private func crop(_ rect: CGRect, scale: CGFloat = 1) async -> CGImage? {
        try? await Task.sleep(for: .milliseconds(40))
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // BoundsIgnoreFraming | BestResolution; IncludingWindow; CGRectNull: the window's own bounds.
        guard let image = create(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue() else { return nil }
        let pixels = CGFloat(image.width) / window.frame.width
        let height = window.frame.height
        let flipped = CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
            .intersection(CGRect(x: 0, y: 0, width: window.frame.width, height: height))
        let inPixels = CGRect(x: flipped.minX * pixels, y: flipped.minY * pixels, width: flipped.width * pixels, height: flipped.height * pixels).integral
        guard let cropped = image.cropping(to: inPixels) else { return nil }
        guard scale != 1 else { return cropped }
        let size = CGSize(width: CGFloat(cropped.width) * scale, height: CGFloat(cropped.height) * scale)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cropped }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}

struct SheetRow {
    var label: String
    var cells: [CGImage?]
}

/// A contact sheet: a title, the tokens, a grid of captures with row and column labels.
struct ContactSheet {
    var title: String
    var columns: [String]
    var notes: [String]
    var rows: [SheetRow]

    func write(to url: URL) -> Bool {
        let gap: CGFloat = 16, labelWidth: CGFloat = 260, margin: CGFloat = 24
        let widths = columns.indices.map { column in rows.compactMap { $0.cells.indices.contains(column) ? $0.cells[column]?.width : nil }.max().map(CGFloat.init) ?? 120 }
        let heights = rows.map { row in row.cells.compactMap { $0?.height }.max().map(CGFloat.init) ?? 40 }
        let titleFont = NSFont.systemFont(ofSize: 22, weight: .semibold), font = NSFont.systemFont(ofSize: 15), small = NSFont.systemFont(ofSize: 14)
        let gridWidth = labelWidth + widths.reduce(0, +) + gap * CGFloat(columns.count)
        let noteHeight = CGFloat(notes.count) * 40
        let width = margin * 2 + gridWidth + 200
        let height = margin * 2 + 40 + noteHeight + 30 + heights.reduce(0, +) + gap * CGFloat(rows.count)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        func text(_ string: String, _ font: NSFont, at point: CGPoint, width: CGFloat) {
            // Top-left based on a y-up canvas.
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            NSAttributedString(string: string, attributes: attributes)
                .draw(with: CGRect(x: point.x, y: height - point.y - 40, width: width, height: 40), options: [.usesLineFragmentOrigin])
        }
        var y = margin
        text(title, titleFont, at: CGPoint(x: margin, y: y), width: gridWidth)
        y += 40
        for note in notes {
            text(note, small, at: CGPoint(x: margin, y: y), width: gridWidth)
            y += 40
        }
        var x = margin + labelWidth
        for (column, name) in columns.enumerated() {
            text(name, font, at: CGPoint(x: x, y: y), width: widths[column] + (column == columns.count - 1 ? 200 : gap))
            x += widths[column] + gap
        }
        y += 30
        for (index, row) in rows.enumerated() {
            text(row.label, font, at: CGPoint(x: margin, y: y + heights[index] / 2 - 10), width: labelWidth - 8)
            x = margin + labelWidth
            for column in columns.indices {
                if row.cells.indices.contains(column), let image = row.cells[column] {
                    let rect = CGRect(x: x, y: height - y - CGFloat(image.height), width: CGFloat(image.width), height: CGFloat(image.height))
                    cg.draw(image, in: rect)
                    cg.setStrokeColor(NSColor(white: 0.75, alpha: 1).cgColor)
                    cg.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
                } else {
                    text("—", font, at: CGPoint(x: x + 8, y: y + heights[index] / 2 - 10), width: 40)
                }
                x += widths[column] + gap
            }
            y += heights[index] + gap
        }
        NSGraphicsContext.restoreGraphicsState()
        return (try? rep.representation(using: .png, properties: [:])?.write(to: url)) != nil
    }
}
#endif
