#if DEBUG
import AppKit
import Card
import Carbon
import Chrome
import Engine
import UIKitCore

/// `Room -RoomSpike <name> -RoomSpikeOutput <file>` (Debug builds): runs one
/// Phase 1.4 measurement against the live engine, appends `key: value` lines
/// to the output file and, unless `-RoomSpikeKeepRunning YES`, quits.
/// Spikes: cdp, scroll, resize, memory, audio, popups, hidden, open10,
/// Phase 2.3's tabs, switch, relaunch (`TabSpikes.swift`), and Phase 2.4a's
/// palette, palettemeasure (`PaletteSpikes.swift`), palette2, suggestcheck (`Palette2Spikes.swift`),
/// Phase 2.5's spaces, spacecaptures, cookies (`SpaceSpikes.swift`), and
/// Phase 2.6a's chromesurfaces (`ChromeSpikes.swift`) and 2.6b's
/// chromesurfaces2 (`ChromeSpikes2.swift`), and Phase 2.7a's layoutmodes
/// (`LayoutSpikes.swift`), and Phase 2.8a's appintegration (`AppIntegrationSpikes.swift`)
/// and 2.8b's appintegration2 (`AppIntegration2Spikes.swift`).
enum SpikeRunner {
    static var requested: String? { UserDefaults.standard.string(forKey: "RoomSpike") }

    private static var output: URL {
        URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? NSTemporaryDirectory() + "room-spike.txt")
    }

    /// `research/spikes/phase-1.4` in the source tree this build came from.
    /// `-RoomRepository <path>` lets a Debug app copied to another machine find the fixtures (B-78).
    static let pagesDirectory = (UserDefaults.standard.string(forKey: "RoomRepository").map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        .appending(path: "research/spikes/phase-1.4", directoryHint: .isDirectory)

    static func page(_ name: String) -> URL { pagesDirectory.appending(path: name) }

    static func run(_ name: String, session: SpikeSession, controller: RoomWindowController, overlays: OverlaySpike?) async {
        try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = Context(session: session, controller: controller)
        record("spike", name)
        record("date", ISO8601DateFormatter().string(from: Date()))
        record("loadavg", loadAverage())
        // Before the activation attempts below (up to 5 s when macOS refuses them).
        record("launch_to_spike_s", String(format: "%.2f", Date().timeIntervalSince(Context.processStartDate())))
        // The grand tour (Phase 2.9) runs every spike in one appearance; spikes that capture both still switch themselves.
        if let appearance = UserDefaults.standard.string(forKey: "RoomSpikeAppearance") {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        // The relaunch timing must not include the activation attempts.
        if name != "relaunch" { await context.activate() }
        switch name {
        case "cdp": await context.cdp()
        case "scroll": await context.scroll()
        case "resize": await context.resize()
        case "memory": await context.memory()
        case "audio": await context.audio()
        case "popups": await context.popups()
        case "hidden": await context.hiddenCompositing()
        case "open10": await context.openTen()
        case "diaframe": await context.diaFrame()
        case "keys": await context.keys()
        case "devtools": await context.devTools()
        case "tabs": await context.tabsChecks()
        case "switch": await context.switching()
        case "relaunch": await context.relaunch()
        case "capture": await context.captures()
        case "colors": await context.colors()
        case "palette": await context.paletteChecks()
        case "palettemeasure": await context.paletteMeasure()
        case "palette2": await context.palette2Checks()
        case "suggestcheck": await context.suggestCheck()
        case "spaces": await context.spacesMeasure()
        case "spacecaptures": await context.spaceCaptures()
        case "cookies": await context.cookiesCheck()
        case "chromesurfaces": await context.chromeSurfaces()
        case "chromesurfaces2": await context.chromeSurfaces2()
        case "layoutmodes": await context.layoutModes()
        case "appintegration": await context.appIntegration()
        case "appintegration2": await context.appIntegration2()
        case "netcheck": await context.netCheck()
        case "quitstay": await context.quitStay()
        case "closeunload": await context.closeUnload()
        case "pageservices": await context.pageServices()
        case "quitflags": await context.quitFlags()
        case "extensions": await context.extensionsChecks()
        case "webstore": await context.webstoreChecks()
        case "extupdate": await context.extensionUpdateCheck()
        case "extpopup": await context.extensionPopupChecks()
        case "extux": await context.extensionsUXChecks()
        case "media": await context.mediaChecks()
        case "documents": await context.documentsChecks()
        case "reader": await context.readerChecks()
        case "adblock": await context.adblockChecks()
        case "live": await context.liveChecks()
        case "downloadprompt": await context.downloadPromptChecks()
        case "sidebarfixes": await context.sidebarFixesChecks()
        case "motion": await context.motionChecks()
        case "motionsheet": await context.motionSheet()
        case "matrix": await context.visualMatrix()
        case "contrast": await context.contrastChecks()
        case "branding": await context.brandingChecks()
        case "skipped": await context.skippedStepsChecks()
        case "windows": await context.windowsChecks()
        case "incognito": await context.incognitoChecks()
        case "passwords": await context.passwordsChecks()
        case "autofill": await context.autofillChecks()
        case "session": await context.sessionChecks()
        case "discardpolicy": await context.discardPolicyChecks()
        case "discardspaces": await context.discardTwoSpacesChecks()
        case "spelling": await context.spellingChecks()
        case "archive": await context.archiveChecks()
        case "recovery": await context.recoveryChecks()
        case "routing": await context.routingChecks()
        case "import": await context.importChecks()
        case "importlarge": await context.importLargeChecks()
        case "settings": await context.settingsChecks()
        case "profiles": await context.profilesChecks()
        case "spacewindow": await context.spaceWindowChecks()
        case "showcase": await context.showcase()
        case "a11y": await context.accessibilityAuditSpike()
        case "keyboard": await context.keyboardChecks()
        case "openclose": await context.openCloseCycle()
        case "energy": await context.energyChecks()
        case "details": await context.detailsChecks()
        default: record("error", "unknown spike")
        }
        record("end", name)
        if !UserDefaults.standard.bool(forKey: "RoomSpikeKeepRunning") { NSApp.terminate(nil) }
    }

    /// `js` reported once that the engine runs no scripts.
    static var reportedNoScript = false

    static func record(_ key: String, _ value: Any) {
        let line = "\(key): \(value)\n"
        if let handle = try? FileHandle(forWritingTo: output) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: output, atomically: true, encoding: .utf8)
        }
    }

    /// The dev framework's spike hooks (`roomSpikeAction:`, `roomSpikeCommand:`; `room_enable_spikes`)
    /// are absent from the official framework, where calling one is an unrecognized selector (B-82).
    /// Every call goes through here: without the hook the spike records "spike hooks unavailable"
    /// (once per selector) and gets nil, so the same spike runs on `ROOM_TOUR_APP`.
    @MainActor private static var reportedMissingHooks: Set<String> = []

    @MainActor
    static func spikeHook(_ target: NSObject?, _ selectorName: String, _ argument: Any) -> NSNumber? {
        let selector = NSSelectorFromString(selectorName)
        guard let target, target.responds(to: selector) else {
            if reportedMissingHooks.insert(selectorName).inserted {
                record("spike_hooks", "spike hooks unavailable (\(selectorName) on \(target.map { String(describing: type(of: $0)) } ?? "no browser"))")
            }
            return nil
        }
        return target.perform(selector, with: argument)?.takeUnretainedValue() as? NSNumber
    }

    static func loadAverage() -> String {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        return loads.map { String(format: "%.1f", $0) }.joined(separator: " ")
    }

    /// Median, p95 and max of millisecond samples.
    static func stats(_ samples: [Double]) -> String {
        guard !samples.isEmpty else { return "n=0" }
        let sorted = samples.sorted()
        let p = { (q: Double) in sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * q))] }
        return String(format: "n=%d median=%.2fms p95=%.2fms max=%.2fms", sorted.count, p(0.5), p(0.95), sorted.last!)
    }

    @MainActor
    final class Context {
        let session: SpikeSession
        let controller: RoomWindowController

        init(session: SpikeSession, controller: RoomWindowController) {
            self.session = session
            self.controller = controller
        }

        var window: NSWindow { controller.window! }

        func activate() async {
            for _ in 0..<50 where !(NSApp.isActive && window.isMainWindow) {
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(100))
            }
            SpikeRunner.record("window_main", window.isMainWindow)
        }

        @discardableResult
        func open(_ url: URL, hidden: Bool = false, select: Bool = true, timeout: Double = 30) async -> (any WebContents)? {
            guard let page = session.newPage(url, hidden: hidden, select: select) else { return nil }
            await waitLoaded(page, timeout: timeout)
            return page
        }

        func waitLoaded(_ page: any WebContents, timeout: Double = 30) async {
            let start = Date()
            try? await Task.sleep(for: .milliseconds(300))
            while (page.isLoading || page.url == nil), Date().timeIntervalSince(start) < timeout {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        /// The script's JSON result, or "error". An engine that cannot run
        /// scripts at all (RoomCore before 3.3b) leaves an `error:` line, once.
        func js(_ page: any WebContents, _ script: String) async -> String {
            do {
                return try await page.executeJavaScript(script)
            } catch EngineError.notSupported(let member) {
                if !SpikeRunner.reportedNoScript {
                    SpikeRunner.reportedNoScript = true
                    SpikeRunner.record("error", "script: \(member) is not supported on this engine; the checks that read the page cannot run")
                }
                return "error"
            } catch {
                return "error"
            }
        }

        /// Milliseconds since `start`.
        func ms(since start: ContinuousClock.Instant) -> Double {
            let d = ContinuousClock.now - start
            return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        }

        // MARK: CDP channel

        func cdp() async {
            guard let page = await open(URL(string: "https://en.wikipedia.org/wiki/Web_browser")!) else { return }
            try? await Task.sleep(for: .seconds(2))
            var evaluate: [Double] = []
            for _ in 0..<100 {
                let start = ContinuousClock.now
                _ = await js(page, "1 + 1")
                evaluate.append(ms(since: start))
            }
            SpikeRunner.record("runtime_evaluate_rtt", SpikeRunner.stats(evaluate))
            var capture: [Double] = []
            var size = NSSize.zero
            for _ in 0..<20 {
                let start = ContinuousClock.now
                if let image = try? await page.captureViewport() { size = image.size }
                capture.append(ms(since: start))
            }
            SpikeRunner.record("page_capture_screenshot_rtt", SpikeRunner.stats(capture) + " size=\(Int(size.width))x\(Int(size.height))pt")
            if size == .zero { _ = await PageDriver.capture(page, "cdp: page capture") }
            SpikeRunner.record("rootBackgroundColor", page.rootBackgroundColor.map { "\($0)" } ?? "nil")
            SpikeRunner.record("themeColor", page.themeColor.map { "\($0)" } ?? "nil")

            // Transparent background: the window material shows where the page paints nothing.
            guard let transparent = try? session.profile.createWebContents(WebContentsConfiguration(transparentBackground: true)) else { return }
            transparent.load(SpikeRunner.page("transparent.html"))
            session.host.show(transparent)
            await waitLoaded(transparent)
            controller.cardView.backgroundColor = .clear
            try? await Task.sleep(for: .seconds(1.5))
            // `-RoomSpikeCaptureDirectory` (the grand tour) keeps the committed Phase 1.4 captures as they are.
            let shots = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? SpikeRunner.pagesDirectory.deletingLastPathComponent().deletingLastPathComponent().appending(path: "screenshots/phase-1.4")
            try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
            _ = try? WindowSnapshot.writePNG(window, to: shots.appending(path: "phase-1.4-transparent-background.png"))
            SpikeRunner.record("transparent_snapshot", "phase-1.4-transparent-background.png")
            SpikeRunner.record("transparent_page_state", await js(transparent, PageScriptsSpike.visibilityAndFrames)
                + " title=\(transparent.title ?? "nil") url=\(transparent.url?.lastPathComponent ?? "nil") view=\(transparent.nativeView.frame) inWindow=\(transparent.nativeView.window === window)")
            if let image = try? await transparent.captureViewport(), let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: shots.appending(path: "phase-1.4-transparent-cdp-capture.png"))
            }
            SpikeRunner.record("transparent_resize", await resizeCost(transparent))
            session.host.show(page)
            SpikeRunner.record("opaque_resize", await resizeCost(page))
            transparent.close()
        }

        /// Page frame intervals while the window width changes every 16 ms.
        func resizeCost(_ page: any WebContents) async -> String {
            _ = await js(page, "window.__frames = []; (function f(t){ __frames.push(t); requestAnimationFrame(f) })(performance.now()); 0")
            let original = window.frame
            var steps: [Double] = []
            for i in 0..<60 {
                let start = ContinuousClock.now
                var frame = original
                frame.size.width = original.width - CGFloat(i % 30) * 10
                window.setFrame(frame, display: true)
                steps.append(ms(since: start))
                try? await Task.sleep(for: .milliseconds(16))
            }
            window.setFrame(original, display: true)
            let json = await js(page, "(() => { const d = []; for (let i = 1; i < __frames.length; i++) d.push(__frames[i] - __frames[i-1]); return d })()")
            let deltas = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Double]) ?? []
            let long = deltas.filter { $0 > 17 }.count
            return "main-thread setFrame \(SpikeRunner.stats(steps)); page frames \(SpikeRunner.stats(deltas)) over17ms=\(long)"
        }

        // MARK: Scrolling with the corner mask

        func scroll() async {
            guard let page = await open(SpikeRunner.page("scroll.html")) else { return }
            try? await Task.sleep(for: .seconds(1))
            let container = controller.cardView.container
            for masked in [true, false, true] {
                container.layer?.masksToBounds = masked
                container.layer?.cornerRadius = masked ? 10 : 0
                try? await Task.sleep(for: .milliseconds(500))
                let json = await js(page, PageScriptsSpike.scrollFrames)
                let deltas = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Double]) ?? []
                let late = deltas.filter { $0 > 12.5 }.count
                SpikeRunner.record("scroll_mask_\(masked)", SpikeRunner.stats(deltas) + " over12.5ms=\(late) fps=\(String(format: "%.1f", Double(deltas.count) / 3))")
            }
        }

        // MARK: Live resize: does material show at the card edge?

        func resize() async {
            guard let page = await open(URL(string: "https://en.wikipedia.org/wiki/Web_browser")!) else { return }
            try? await Task.sleep(for: .seconds(2))
            SpikeRunner.record("card_background", "\(controller.cardView.backgroundColor)")
            SpikeRunner.record("tracked_root_background", page.rootBackgroundColor.map { "\($0)" } ?? "nil")
            SpikeRunner.record("bound_card_fill", await edgeGaps())
            controller.cardView.backgroundColor = .clear
            SpikeRunner.record("control_clear_card_fill", await edgeGaps())
            controller.cardView.backgroundColor = page.rootBackgroundColor ?? .white
            // Control 2: a page with no background over a clear card must show material.
            if let transparent = try? session.profile.createWebContents(WebContentsConfiguration(transparentBackground: true)) {
                transparent.load(SpikeRunner.page("transparent.html"))
                session.host.show(transparent)
                await waitLoaded(transparent)
                controller.cardView.backgroundColor = .clear
                try? await Task.sleep(for: .seconds(1))
                SpikeRunner.record("control_transparent_page_clear_card", await edgeGaps())
                transparent.close()
            }
        }

        /// Grows the window in 24 steps and samples the card's right edge in
        /// a capture taken right after each step; counts samples where the
        /// material (not page or card fill) is visible inside the card.
        func edgeGaps() async -> String {
            let original = window.frame
            var gaps = 0
            var samples = 0
            var inside = Pixel(r: 0, g: 0, b: 0)
            var materialSeen = Pixel(r: 0, g: 0, b: 0)
            for i in 1...24 {
                var frame = original
                frame.size.width = original.width - 240 + CGFloat(i) * 10
                window.setFrame(frame, display: true)
                try? await Task.sleep(for: .milliseconds(4))
                guard let image = WindowSnapshot.capture(window) else { continue }
                let scale = CGFloat(image.width) / window.frame.width
                let card = controller.rootView.currentLayout.card
                let material = Pixel.at(image, x: (card.maxX + 3) * scale, y: 400 * scale)
                for y in stride(from: 120.0, through: card.maxY - 40, by: 80) {
                    for inset in [2.0, 8.0, 20.0] {
                        let p = Pixel.at(image, x: (card.maxX - inset) * scale, y: y * scale)
                        inside = p
                        materialSeen = material
                        samples += 1
                        if p.distance(to: material) < 6 { gaps += 1 }
                    }
                }
            }
            window.setFrame(original, display: true)
            return "material-coloured samples inside card: \(gaps)/\(samples); last inside rgb(\(Int(inside.r)),\(Int(inside.g)),\(Int(inside.b))) material rgb(\(Int(materialSeen.r)),\(Int(materialSeen.g)),\(Int(materialSeen.b)))"
        }

        // MARK: Memory

        static let typicalSites = [
            "https://en.wikipedia.org/wiki/Web_browser",
            "https://github.com/chromiumembedded/cef",
            "https://news.ycombinator.com/",
            "https://developer.apple.com/documentation/appkit",
            "https://www.bbc.com/news",
            "https://stackoverflow.com/questions",
            "https://www.theverge.com/",
            "https://www.reddit.com/r/macapps/",
            "https://www.nytimes.com/",
            "https://www.youtube.com/",
        ]

        func memory() async {
            let counts = (UserDefaults.standard.string(forKey: "RoomSpikeCounts") ?? "1,10,30").split(separator: ",").compactMap { Int($0) }
            // Baseline: the engine with one blank page in the card.
            _ = await open(URL(string: "about:blank")!)
            try? await Task.sleep(for: .seconds(3))
            let baseline = ProcessMemory.snapshot()
            SpikeRunner.record("baseline", baseline.summary)
            for count in counts {
                var pages: [any WebContents] = []
                for i in 0..<count {
                    let url = URL(string: Self.typicalSites[i % Self.typicalSites.count] + (i >= Self.typicalSites.count ? "?r=\(i)" : ""))!
                    if let page = session.newPage(url, hidden: true, select: false) { pages.append(page) }
                }
                let start = Date()
                while pages.contains(where: { $0.isLoading }), Date().timeIntervalSince(start) < 90 {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                try? await Task.sleep(for: .seconds(8))
                let snapshot = ProcessMemory.snapshot()
                let perBrowser = (snapshot.totalMB - baseline.totalMB) / Double(count)
                SpikeRunner.record("hidden_\(count)", snapshot.summary + String(format: " per_browser=%.0fMB", perBrowser)
                    + " loaded=\(pages.filter { !$0.isLoading }.count)/\(count) load_s=\(Int(Date().timeIntervalSince(start)))")
                if let first = pages.first {
                    SpikeRunner.record("hidden_\(count)_page0", await js(first, PageScriptsSpike.visibilityAndFrames))
                }
                for page in pages { page.close() }
                let closeStart = Date()
                while session.pages.count > 1, Date().timeIntervalSince(closeStart) < 20 {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }

        /// Visible vs. hidden compositing for one page.
        func hiddenCompositing() async {
            guard let visible = await open(SpikeRunner.page("scroll.html")) else { return }
            SpikeRunner.record("visible_page", await js(visible, PageScriptsSpike.visibilityAndFrames))
            guard let hidden = await open(SpikeRunner.page("scroll.html"), hidden: true, select: false) else { return }
            SpikeRunner.record("hidden_never_shown", await js(hidden, PageScriptsSpike.visibilityAndFrames))
            session.select(session.pages.count - 1)
            try? await Task.sleep(for: .milliseconds(500))
            SpikeRunner.record("after_show", await js(hidden, PageScriptsSpike.visibilityAndFrames))
            session.select(0)
            try? await Task.sleep(for: .milliseconds(500))
            SpikeRunner.record("after_removed_from_card", await js(hidden, PageScriptsSpike.visibilityAndFrames))
        }

        // MARK: Audibility

        func audio() async {
            guard let page = await open(SpikeRunner.page("audio.html")) else {
                SpikeRunner.record("error", "audio: audio.html did not open")
                return
            }
            var cost: [Double] = []
            for _ in 0..<30 {
                let start = ContinuousClock.now
                _ = await js(page, "[...document.querySelectorAll('video,audio')].some(m => !m.paused && !m.ended && !m.muted && m.volume > 0 && m.readyState > 2)")
                cost.append(ms(since: start))
            }
            SpikeRunner.record("poll_cost", SpikeRunner.stats(cost))
            for round in 1...2 {
                let playAt = ContinuousClock.now
                _ = await PageDriver.evaluateWithGesture(page, "document.getElementById('a').play().then(() => 0)", "audio play")
                let became = await waitUntil(5) { page.isAudible }
                SpikeRunner.record("round\(round)_became_audible", became ? String(format: "%.0fms", ms(since: playAt)) : "no edge within 5s")
                try? await Task.sleep(for: .seconds(2))
                let pauseAt = ContinuousClock.now
                _ = await js(page, "document.getElementById('a').pause(); 0")
                let stopped = await waitUntil(5) { !page.isAudible }
                SpikeRunner.record("round\(round)_reported_stopped", stopped ? String(format: "%.0fms", ms(since: pauseAt)) : "still audible after 5s")
                try? await Task.sleep(for: .seconds(1))
            }
            // Web Audio: an oscillator, which the media-element poll cannot see.
            let webAudioAt = ContinuousClock.now
            _ = await PageDriver.evaluateWithGesture(page, PageScriptsSpike.oscillator, "audio oscillator")
            let webAudible = await waitUntil(5) { page.isAudible }
            SpikeRunner.record("webaudio_became_audible", webAudible ? String(format: "%.0fms", ms(since: webAudioAt)) : "no edge within 5s")
            try? await Task.sleep(for: .seconds(2))
            SpikeRunner.record("webaudio_still_audible_after_2s_playing", page.isAudible)
            let stopAt = ContinuousClock.now
            _ = await js(page, "window.__osc && window.__osc.stop(); 0")
            let webStopped = await waitUntil(5) { !page.isAudible }
            SpikeRunner.record("webaudio_reported_stopped", webStopped ? String(format: "%.0fms", ms(since: stopAt)) : "still audible after 5s")
        }

        func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
            let start = Date()
            while !condition() {
                if Date().timeIntervalSince(start) > seconds { return false }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return true
        }

        // MARK: Popups, select, date picker, JS dialogs

        func popups() async {
            guard let page = await open(SpikeRunner.page("popups.html")) else {
                SpikeRunner.record("error", "popups: popups.html did not open")
                return
            }
            try? await Task.sleep(for: .seconds(1))
            // A new page by identity: since 2.3 a page opened from another goes right below it, not last.
            func newPage(after before: [any WebContents]) -> (any WebContents)? {
                session.pages.first { page in !before.contains { $0 === page } }
            }
            // The three openers sit at fixed places in the fixture: where the
            // engine runs no script (RoomCore until 3.3b), click by point.
            let runsScript = await PageDriver.evaluate(page, "1", "popups: probe whether the engine runs script") != nil
            func clickOpener(_ selector: String, _ point: CGPoint) async {
                if !runsScript {
                    // A first click on an empty spot: an inactive window takes the
                    // first mouse-down for activation, not for the page.
                    PageDriver.click(page, at: CGPoint(x: 800, y: 600), "focus the page")
                    try? await Task.sleep(for: .milliseconds(300))
                    SpikeRunner.record("click_state", "appActive=\(NSApp.isActive) key=\(window.isKeyWindow)")
                    PageDriver.click(page, at: point, "click \(selector) by point")
                } else {
                    await click(page, selector)
                }
            }
            let before = session.pages.count
            let pagesBefore = session.pages
            await clickOpener("#blank", CGPoint(x: 510, y: 96))
            _ = await waitUntil(5) { self.session.pages.count > before }
            let blank = newPage(after: pagesBefore)
            if let blank { await waitLoaded(blank) }
            SpikeRunner.record("target_blank", "pages \(before)→\(session.pages.count) current=\(session.current === blank) title=\(blank?.title ?? "nil") inCard=\(blank?.nativeView.window === window)")
            session.select(session.pages.firstIndex { $0 === page } ?? 0)
            try? await Task.sleep(for: .milliseconds(500))
            let before2 = session.pages.count
            let pagesBefore2 = session.pages
            await clickOpener("#open", CGPoint(x: 510, y: 146))
            _ = await waitUntil(5) { self.session.pages.count > before2 }
            let popup = newPage(after: pagesBefore2)
            if let popup { await waitLoaded(popup) }
            SpikeRunner.record("window_open", "pages \(before2)→\(session.pages.count) title=\(popup?.title ?? "nil") inCard=\(popup?.nativeView.window === window)")
            // 3.2a: a window capture with the popup placed as a Today tab
            // (scripts answer `capture:` lines; only when asked).
            if UserDefaults.standard.bool(forKey: "RoomSpikePopupsCapture") {
                SpikeRunner.record("window_id", window.windowNumber)
                try? await Task.sleep(for: .milliseconds(800))
                SpikeRunner.record("capture", "popups-window-open-today-tab")
                let output = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? "")
                let ack = output.deletingLastPathComponent().appending(path: output.lastPathComponent + ".ack-popups-window-open-today-tab")
                _ = await waitUntil(20) { FileManager.default.fileExists(atPath: ack.path) }
            }
            session.select(session.pages.firstIndex { $0 === page } ?? 0)
            try? await Task.sleep(for: .milliseconds(500))

            // A document picture-in-picture window (3.2a): a page the host places too.
            let before3 = session.pages.count
            let pagesBefore3 = session.pages
            await clickOpener("#pip", CGPoint(x: 510, y: 196))
            _ = await waitUntil(5) { self.session.pages.count > before3 }
            let pip = newPage(after: pagesBefore3)
            if let pip { await waitLoaded(pip) }
            SpikeRunner.record("picture_in_picture", "pages \(before3)→\(session.pages.count) title=\(pip?.title ?? "nil") inCard=\(pip?.nativeView.window === window)")
            // Every window the app has: the host's, its panels, and no Chrome window (3.2a).
            SpikeRunner.record("windows", NSApp.windows.map { "\(Swift.type(of: $0)) \"\($0.title)\" visible=\($0.isVisible) \(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: " | "))
            session.select(session.pages.firstIndex { $0 === page } ?? 0)
            try? await Task.sleep(for: .milliseconds(500))

            // <select> and <input type=date> popups, before and after a window move.
            for moved in [false, true] {
                if moved {
                    var frame = window.frame
                    frame.origin.x += 140
                    frame.origin.y -= 90
                    window.setFrame(frame, display: true)
                    try? await Task.sleep(for: .milliseconds(500))
                }
                for selector in ["#sel", "#date"] {
                    SpikeRunner.record("popup_\(selector.dropFirst())_moved_\(moved)", await popupGeometry(page, selector))
                }
            }

            // JavaScript dialogs reach the delegate (the in-card sheet since 2.6a).
            Task { await self.click(page, "#alert") }
            let prompts = session.pageDelegate.chrome.prompts
            let sheet = await waitUntil(5) { prompts.visibleDialog != nil }
            SpikeRunner.record("alert_sheet", sheet)
            prompts.respond(.accept(text: nil))
            _ = await waitUntil(3) { prompts.visibleDialog == nil }
            try? await Task.sleep(for: .milliseconds(300))
            // The DOM mark, not `window.__alerted`: the engine's script runs in an isolated world (B-75).
            SpikeRunner.record("alert_completed", await js(page, "String(document.documentElement.dataset.alerted === 'true')"))
        }

        /// Clicks an element with real mouse events on the page's view (a user
        /// gesture in the renderer; `PageDriver`). `fromRight` clicks that many
        /// points left of the element's right edge instead of its centre.
        func click(_ page: any WebContents, _ selector: String, fromRight: Double? = nil, modifiers: NSEvent.ModifierFlags = []) async {
            await PageDriver.click(page, selector, fromRight: fromRight, modifiers: modifiers, "click \(selector)")
        }

        /// Opens the control's popup and compares the popup window's screen
        /// position with the element's (both top-left screen points).
        func popupGeometry(_ page: any WebContents, _ selector: String) async -> String {
            let json = await js(page, "(() => { const r = document.querySelector('\(selector)').getBoundingClientRect(); return [r.x, r.y, r.width, r.height] })()")
            guard let rect = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Double], rect.count == 4 else { return "no element" }
            let view = page.nativeView
            let windowPoint = view.convert(NSPoint(x: rect[0], y: rect[1] + rect[3]), to: nil)
            let screen = window.convertPoint(toScreen: windowPoint)
            let mainHeight = NSScreen.screens.first?.frame.height ?? 0
            let elementBottomLeft = NSPoint(x: screen.x, y: mainHeight - screen.y)  // CG (top-left) coordinates
            let pid = getpid()
            let before = Set(PopupWindows.list(pid: pid).map(\.id))
            // A <select> runs a modal NSMenu tracking loop on this thread, so
            // measure and dismiss it from another thread.
            let probe = PopupWindows.probe(pid: pid, excluding: before)
            if selector == "#date" {
                // A click on the calendar glyph does not open it; showPicker() with a gesture does.
                _ = await PageDriver.evaluateWithGesture(page, "document.querySelector('#date').showPicker(); 0", "date picker")
            } else {
                await click(page, selector)
            }
            let found = await probe.value
            try? await Task.sleep(for: .milliseconds(300))
            _ = await js(page, "document.activeElement && document.activeElement.blur(); 0")
            guard let popup = found else { return "no popup window appeared" }
            let dx = popup.bounds.minX - elementBottomLeft.x
            let dy = popup.bounds.minY - elementBottomLeft.y
            return String(format: "popup at (%.0f,%.0f) %.0fx%.0f layer=%d; element bottom-left (%.0f,%.0f); offset dx=%.0f dy=%.0f",
                          popup.bounds.minX, popup.bounds.minY, popup.bounds.width, popup.bounds.height, popup.layer,
                          elementBottomLeft.x, elementBottomLeft.y, dx, dy)
        }

        // MARK: Keyboard routing

        /// Sends key events built with the characters each layout produces
        /// (UCKeyTranslate on the layout data) through NSApp.sendEvent, and
        /// checks reserved shortcuts, menu fall-through and editing commands.
        func keys() async {
            guard let page = await open(SpikeRunner.page("keys.html")) else {
                SpikeRunner.record("error", "keys: keys.html did not open")
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            await click(page, "#t")
            focusPage(page)
            let pasteboard = NSPasteboard.general
            let saved = pasteboard.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } } ?? []
            defer {
                pasteboard.clearContents()
                pasteboard.writeObjects(saved.map { pairs in
                    let item = NSPasteboardItem()
                    pairs.forEach { item.setData($0.1, forType: $0.0) }
                    return item
                })
            }
            for layoutID in ["com.apple.keylayout.ABC", "com.apple.keylayout.Colemak", "com.apple.keylayout.Lithuanian", "com.apple.keylayout.LithuanianColemak"] {
                guard let layout = KeyLayout(id: layoutID) else {
                    SpikeRunner.record("layout_\(layoutID)", "not installed")
                    continue
                }
                // The page's key log is read from the DOM (`data-keys`): RoomCore's
                // scripts run in an isolated world, where the page's globals are not visible.
                let seenBefore = Int(await js(page, "JSON.parse(document.documentElement.dataset.keys || '[]').length")) ?? 0
                _ = await js(page, "const t = document.getElementById('t'); t.value = 'select me and copy'; t.focus(); t.select(); 0")
                focusPage(page)
                var results: [String] = []
                let consumedBefore = session.consumedKeyCount
                // Reserved: ⌘T (New Page), ⌘L (Open Location). Key codes are where the layout puts the letter.
                let newTabsBefore = session.newTabRequests
                let reservedBefore = session.keyLog.filter { $0.hasPrefix("reserved") }.count
                if let code = layout.keyCode(for: "t") { send(layout, code, [.command]) }
                try? await Task.sleep(for: .milliseconds(400))
                let newPage = session.newTabRequests > newTabsBefore
                focusPage(page)
                let focusBefore = session.addressFocusRequest
                if let code = layout.keyCode(for: "l") { send(layout, code, [.command]) }
                try? await Task.sleep(for: .milliseconds(300))
                let focusedAddress = session.addressFocusRequest > focusBefore
                let reservedCalls = session.keyLog.filter { $0.hasPrefix("reserved") }.count - reservedBefore
                focusPage(page)
                _ = await js(page, "document.getElementById('t').focus(); document.getElementById('t').select(); 0")
                // Editing: ⌘C, ⌘V, ⌘Z reach the page and fall through to the menu.
                pasteboard.clearContents()
                if let code = layout.keyCode(for: "c") { send(layout, code, [.command]) }
                try? await Task.sleep(for: .milliseconds(300))
                let copied = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                pasteboard.setString(" PASTED", forType: .string)
                _ = await js(page, "const t = document.getElementById('t'); t.selectionStart = t.selectionEnd = t.value.length; 0")
                if let code = layout.keyCode(for: "v") { send(layout, code, [.command]) }
                try? await Task.sleep(for: .milliseconds(300))
                let afterPaste = await js(page, "document.getElementById('t').value")
                if let code = layout.keyCode(for: "z") { send(layout, code, [.command]) }
                try? await Task.sleep(for: .milliseconds(300))
                let afterUndo = await js(page, "document.getElementById('t').value")
                // A plain letter (not reserved) types into the field.
                _ = await js(page, "const t = document.getElementById('t'); t.focus(); t.selectionStart = t.selectionEnd = t.value.length; 0")
                var typed = "nil"
                if let code = layout.keyCode(for: "o") {
                    send(layout, code, [])
                    try? await Task.sleep(for: .milliseconds(300))
                    typed = await js(page, "document.getElementById('t').value")
                }
                let seen = await js(page, "JSON.stringify(JSON.parse(document.documentElement.dataset.keys || '[]').slice(\(seenBefore)))")
                results.append("⌘T newPage=\(newPage)")
                results.append("⌘L addressFocus=\(focusedAddress)")
                results.append("reserved calls=\(reservedCalls)")
                results.append("⌘C pasteboard=\(copied.map { "\"\($0)\"" } ?? "nil")")
                results.append("⌘V value=\(afterPaste)")
                results.append("⌘Z value=\(afterUndo)")
                results.append("o typed value=\(typed)")
                results.append("page saw \(seen)")
                results.append("consumed=\(session.consumedKeyCount - consumedBefore)")
                // What ⌘ + the number row produces in this layout (for ⌘1–9 later).
                let digits = [18, 19, 20, 21, 23, 22, 26, 28, 25].map { layout.characters(UInt16($0), command: true) }.joined(separator: " ")
                results.append("⌘+number row chars: \(digits)")
                SpikeRunner.record("keys_\(layoutID.replacingOccurrences(of: "com.apple.keylayout.", with: ""))", results.joined(separator: "; "))
            }
            SpikeRunner.record("delegate_key_log", session.keyLog.suffix(12).joined(separator: " | "))
        }

        /// Makes the page's innermost view (Chromium's RenderWidgetHostViewCocoa) first responder.
        func focusPage(_ page: any WebContents) {
            var view: NSView = page.nativeView
            while let next = view.subviews.last(where: { !$0.isHidden }) { view = next }
            var responder: NSView? = view
            while let candidate = responder, !candidate.acceptsFirstResponder { responder = candidate.superview }
            if let responder { window.makeFirstResponder(responder) }
        }

        func send(_ layout: KeyLayout, _ keyCode: UInt16, _ flags: NSEvent.ModifierFlags) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    characters: layout.characters(keyCode, command: flags.contains(.command)),
                    charactersIgnoringModifiers: layout.characters(keyCode, command: false),
                    isARepeat: false, keyCode: keyCode)
                if let event { NSApp.sendEvent(event) }
            }
        }

        // MARK: DevTools

        func devTools() async {
            guard let page = await open(SpikeRunner.page("popups.html")) else {
                SpikeRunner.record("error", "devtools: popups.html did not open")
                return
            }
            guard page.devTools != nil else {
                SpikeRunner.record("error", "devtools: this engine hosts no DevTools for the page (RoomCore: 3.3b)")
                return
            }
            let pagesBefore = session.pages.count
            // The element under (60, 160) in page coordinates: the <select>.
            let target = await js(page, "(() => { const e = document.elementFromPoint(60, 160); return e ? e.tagName + '#' + e.id : 'none' })()")
            let start = ContinuousClock.now
            session.host.toggleDevTools(inspecting: NSPoint(x: 60, y: 160))
            let opened = await waitUntil(10) { page.devTools?.isOpen == true }
            SpikeRunner.record("devtools_open", "\(opened) after \(String(format: "%.0f", ms(since: start)))ms docked=\(session.host.isDevToolsOpen)")
            let frontend = devToolsFrontend(page)
            guard let frontend else {
                SpikeRunner.record("devtools_frontend", "none")
                SpikeRunner.record("error", "devtools: no front-end page to read the selected node from")
                return
            }
            await waitLoaded(frontend, timeout: 10)
            var selected = "none"
            for _ in 0..<50 {
                selected = await js(frontend, PageScriptsSpike.selectedNode)
                if selected.uppercased() == target.replacingOccurrences(of: "\"", with: "").uppercased() { break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            SpikeRunner.record("inspect_element", "page element at point \(target); frontend selected \(selected) after \(String(format: "%.0f", ms(since: start)))ms")
            _ = await waitUntil(1) { false }
            session.host.toggleDevTools()
            let closed = await waitUntil(5) { page.devTools?.isOpen == false }
            try? await Task.sleep(for: .seconds(1))
            SpikeRunner.record("devtools_close", "closed=\(closed) pane=\(session.host.isDevToolsOpen) pages \(pagesBefore)→\(session.pages.count) frontendState=\(frontend.state) pageState=\(page.state)")
        }

        // MARK: Dia framing for external captures

        /// Dia's reference framing (1244×818 pt, 280 pt sidebar) with a page
        /// in the card; `-RoomAppearance dark` for dark. The own-window capture
        /// cannot see Chromium's GPU-process layer, so the screenshot is taken
        /// from outside (Screen Recording permission).
        func diaFrame() async {
            if UserDefaults.standard.string(forKey: "RoomAppearance") == "dark" {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            window.setContentSize(NSSize(width: 1244, height: 818))
            controller.sidebarWidth = 280
            let url = UserDefaults.standard.string(forKey: "RoomSpikeURL").flatMap(URL.init(string:))
                ?? URL(string: "https://en.wikipedia.org/wiki/Web_browser")!
            await open(url)
            try? await Task.sleep(for: .seconds(2))
            SpikeRunner.record("card", NSStringFromRect(controller.rootView.currentLayout.card))
        }

        // MARK: Shutdown fixture

        /// Opens ten pages (one visible, nine hidden) and writes "ready".
        func openTen() async {
            for (i, site) in Self.typicalSites.enumerated() {
                session.newPage(URL(string: site)!, hidden: i > 0, select: i == 0)
            }
            let start = Date()
            while session.pages.contains(where: { $0.isLoading }), Date().timeIntervalSince(start) < 60 {
                try? await Task.sleep(for: .milliseconds(250))
            }
            try? await Task.sleep(for: .seconds(3))
            SpikeRunner.record("pages", session.pages.count)
            SpikeRunner.record("ready", Int(Date().timeIntervalSince(start)))
        }
    }
}

enum PageScriptsSpike {
    /// rAF-driven scroll of 3 s; returns the frame intervals.
    static let scrollFrames = """
    new Promise(resolve => {
      scrollTo(0, 0);
      const d = []; let last = performance.now(); const start = last;
      function f(t) {
        d.push(t - last); last = t;
        scrollBy(0, 6);
        if (t - start < 3000) requestAnimationFrame(f); else resolve(d.slice(1));
      }
      requestAnimationFrame(f);
    })
    """

    static let visibilityAndFrames = """
    new Promise(resolve => {
      let n = 0; const start = performance.now();
      (function f() { n++; if (performance.now() - start < 1000) requestAnimationFrame(f); })();
      setTimeout(() => resolve(JSON.stringify({ visibility: document.visibilityState, rafPerSecond: n })), 1100);
    })
    """

    /// Runs in the DevTools front-end: the node selected in Elements.
    static let selectedNode = """
    (async () => {
      const UI = await import('devtools://devtools/bundled/ui/legacy/legacy.js');
      const SDK = await import('devtools://devtools/bundled/core/sdk/sdk.js');
      const node = UI.Context.Context.instance().flavor(SDK.DOMModel.DOMNode);
      return node ? node.nodeName() + '#' + (node.getAttribute('id') || '') : 'none';
    })()
    """

    static let oscillator = """
    (async () => {
      const ctx = new AudioContext(); await ctx.resume();
      const osc = ctx.createOscillator(); const gain = ctx.createGain(); gain.gain.value = 0.02;
      osc.connect(gain).connect(ctx.destination); osc.start(); window.__osc = osc; return ctx.state;
    })()
    """
}

/// RSS of this app and its helper processes, from `ps`.
struct ProcessMemory {
    var totalMB: Double
    var processes: Int
    var renderers: Int
    var rendererMB: Double

    var summary: String {
        String(format: "total=%.0fMB processes=%d renderers=%d renderer_total=%.0fMB", totalMB, processes, renderers, rendererMB)
    }

    static func snapshot() -> ProcessMemory {
        let bundle = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "rss=,command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        var result = ProcessMemory(totalMB: 0, processes: 0, renderers: 0, rendererMB: 0)
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.contains(bundle) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard let kb = Double(parts.first ?? "") else { continue }
            result.totalMB += kb / 1024
            result.processes += 1
            if line.contains("--type=renderer") {
                result.renderers += 1
                result.rendererMB += kb / 1024
            }
        }
        return result
    }
}

/// Windows of this process from the window server (bounds need no Screen
/// Recording permission).
enum PopupWindows {
    nonisolated struct Info: Sendable {
        var id: Int
        var bounds: CGRect
        var layer: Int
    }

    nonisolated static func list(pid: pid_t) -> [Info] {
        guard let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return all.compactMap { entry in
            guard (entry[kCGWindowOwnerPID as String] as? Int32) == pid,
                  let id = entry[kCGWindowNumber as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return Info(id: id, bounds: bounds, layer: entry[kCGWindowLayer as String] as? Int ?? 0)
        }
    }

    /// Polls for a new window for up to 3 s, then presses Escape to close it.
    static func probe(pid: pid_t, excluding: Set<Int>) -> Task<Info?, Never> {
        Task.detached {
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(50))
                let fresh = list(pid: pid).filter { !excluding.contains($0.id) && $0.bounds.height > 40 }
                if let popup = fresh.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
                    try? await Task.sleep(for: .milliseconds(300))
                    let latest = list(pid: pid).first(where: { $0.id == popup.id }) ?? popup
                    for down in [true, false] {
                        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.postToPid(pid)
                    }
                    return latest
                }
            }
            return nil
        }
    }
}

/// A keyboard layout's translation table, read without selecting it.
final class KeyLayout {
    private let data: Data

    init?(id: String) {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    }

    /// The string this key code types, with or without ⌘ held.
    func characters(_ keyCode: UInt16, command: Bool) -> String {
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        let modifiers: UInt32 = command ? UInt32(cmdKey >> 8) : 0
        let status = data.withUnsafeBytes { buffer in
            UCKeyTranslate(buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress!, keyCode, UInt16(kUCKeyActionDown),
                           modifiers, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 8, &length, &chars)
        }
        return status == noErr ? String(utf16CodeUnits: chars, count: length) : ""
    }

    /// The key code that types `character` (unmodified), if any.
    func keyCode(for character: String) -> UInt16? {
        (0..<128).map(UInt16.init).first { characters($0, command: false) == character }
    }
}

/// One RGBA pixel of a CGImage.
struct Pixel {
    var r: Double, g: Double, b: Double

    static func at(_ image: CGImage, x: CGFloat, y: CGFloat) -> Pixel {
        let px = max(0, min(image.width - 1, Int(x)))
        let py = max(0, min(image.height - 1, Int(y)))
        var data = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: -CGFloat(px), y: -CGFloat(image.height - 1 - py), width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        return Pixel(r: Double(data[0]), g: Double(data[1]), b: Double(data[2]))
    }

    func distance(to other: Pixel) -> Double {
        max(abs(r - other.r), abs(g - other.g), abs(b - other.b))
    }
}
#endif
