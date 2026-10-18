#if DEBUG
import AppKit
import Engine
import Model
import Tabs

/// Built-in blocking spike `adblock` (B-30; `Room -RoomSpike adblock`, run by
/// `scripts/adblock-check.sh`, which serves `research/spikes` on :8777).
/// Fixture `phase-5-adblock/page.html`, opened as news.test (the check
/// maps `*.test` to 127.0.0.1: EasyList exempts 127.0.0.1 and localhost from
/// generic hiding), loads "third-party" files from ads.test and writes what loaded, what is
/// hidden and the cookie banner's fate into `#log`. Sections
/// (`-RoomSpikeOnly` picks): `engine` (the bundled lists' build and cache,
/// decisions on real EasyList and EasyPrivacy URLs), `page` (the fixture
/// with the spike's custom rules: network, cosmetic, redirect, cookie banner,
/// the page's blocked count), `allowed` (the per-site switch: nothing blocked
/// after a reload, then blocked again), `timing` (`timing.html`'s load event
/// with blocking off, the lists only, and the lists with cookie banners
/// rejected), `scriptlets` (uBO's: the fixture's `+js(set-constant)` rule
/// with no uBlock list, then with uBlock filters – Unbreak turned on, which
/// fetches the list and uBO's scriptlets from the network, then off again;
/// a trusted scriptlet in custom rules never runs). The engine's memory is its serialized size (`adblock_engine`):
/// the browser process's footprint does not show it (the allocator keeps
/// freed pages).
extension SpikeRunner.Context {
    static let adblockRules = """
    ||ads.test^*/ads/banner.js$script
    ||ads.test^*/tracker.gif$image
    ||ads.test^*/beacon.txt
    ||ads.test^*/ads/needed.js$script,redirect=noop.js
    news.test##.ad-slot
    ##.room-generic-ad
    """

    func adblockChecks() async {
        let only = Set((UserDefaults.standard.string(forKey: "RoomSpikeOnly") ?? "").split(separator: ",").map(String.init))
        let runs = { (name: String) in only.isEmpty || only.contains(name) }
        await activate()
        guard let blocking = AppDelegate.current?.contentBlocking else {
            return SpikeRunner.record("error", "adblock: no blocker (no engine?)")
        }
        if runs("engine") { await adblockEngine(blocking) }
        if runs("page") { await adblockPage(blocking) }
        if runs("allowed") { await adblockAllowed(blocking) }
        if runs("timing") { await adblockTiming(blocking) }
        if runs("scriptlets") { await adblockScriptlets(blocking) }
    }

    static func adblockPage(_ name: String = "page.html", host: String = "news.test") -> URL {
        URL(string: "http://\(host):8777/phase-5-adblock/\(name)")!
    }

    /// The fixture's `#log` once its timers ran (JSON), or "timeout".
    func adblockResults(_ page: any WebContents) async -> String {
        var log = ""
        _ = await waitUntilAsync(15) {
            log = await self.js(page, "document.getElementById('log') ? document.getElementById('log').textContent : ''")
            return log.contains("{")
        }
        return log.contains("{") ? log : "timeout (\(log))"
    }

    // MARK: engine: the bundled lists

    func adblockEngine(_ blocking: ContentBlockingController) async {
        // The launch's own build (or cache load), before anything changes.
        let launch = blocking.lastReport
        SpikeRunner.record("adblock_launch", String(format: "%@ in %.0f ms, %ld bytes; %@", launch?.fromCache == true ? "cached" : "built",
                                                    launch?.buildMilliseconds ?? -1, launch?.engineBytes ?? -1,
                                                    AppDelegate.launchLog.first { $0.hasPrefix("content blocking") } ?? "no launch line"))
        blocking.update { $0 = ContentBlockingSettings() }
        await blocking.apply()
        let report = blocking.lastReport
        _ = await waitUntil(5) { blocking.ruleCounts.count >= 3 }  // counted off the main thread
        SpikeRunner.record("adblock_lists", blocking.ruleCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        SpikeRunner.record("adblock_engine", String(format: "%@ in %.0f ms, %ld bytes, problems=%ld",
                                                    report?.fromCache == true ? "cached" : "built", report?.buildMilliseconds ?? -1,
                                                    report?.engineBytes ?? -1, report?.problems.count ?? -1))
        guard let engine = AppDelegate.current?.engine.contentBlocking else { return }
        let news = URL(string: "https://news.example/article")!
        let cases: [(String, String, ContentBlockingRequestType)] = [
            ("easylist", "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js", .script),
            ("easylist_doubleclick", "https://securepubads.g.doubleclick.net/tag/js/gpt.js", .script),
            ("easyprivacy", "https://www.google-analytics.com/analytics.js", .script),
            ("easyprivacy_pixel", "https://www.facebook.com/tr?id=1&ev=PageView", .image),
            ("first_party", "https://news.example/static/app.js", .script),
            ("cdn", "https://cdnjs.cloudflare.com/ajax/libs/react/18.3.1/umd/react.production.min.js", .script),
        ]
        SpikeRunner.record("adblock_decisions", cases.map { "\($0.0)=\(engine.wouldBlock(URL(string: $0.1)!, from: news, type: $0.2) ? "block" : "allow")" }
            .joined(separator: " "))
        // A relaunch's case: the same lists again come from the cache.
        blocking.update { $0.customRules = "! cache probe \(UUID().uuidString.prefix(8))" }
        await blocking.apply()
        blocking.update { $0.customRules = "" }
        await blocking.apply()
        SpikeRunner.record("adblock_engine_again", String(format: "%@ in %.0f ms", blocking.lastReport?.fromCache == true ? "cached" : "built",
                                                          blocking.lastReport?.buildMilliseconds ?? -1))
    }

    // MARK: page: the fixture with the spike's rules

    func adblockPage(_ blocking: ContentBlockingController) async {
        blocking.update {
            $0 = ContentBlockingSettings()
            $0.customRules = Self.adblockRules
        }
        await blocking.apply()
        guard let page = await open(Self.adblockPage()) else { return SpikeRunner.record("error", "adblock: the fixture did not open") }
        await waitLoaded(page)
        SpikeRunner.record("adblock_page", await adblockResults(page))
        SpikeRunner.record("adblock_page_count", "blocked_requests=\(page.blockedRequestCount)")
        if let image = await PageDriver.capture(page, "adblock: page") {
            keepAdblockCapture(image, "page")
        }
    }

    // MARK: allowed: the per-site switch

    func adblockAllowed(_ blocking: ContentBlockingController) async {
        blocking.update {
            $0 = ContentBlockingSettings()
            $0.customRules = Self.adblockRules
        }
        guard let site = blocking.site(of: "news.test") else { return SpikeRunner.record("error", "adblock: no site for news.test") }
        blocking.setBlocking(false, on: site)
        await blocking.apply()
        guard let page = await open(Self.adblockPage()) else { return SpikeRunner.record("error", "adblock: the fixture did not open") }
        await waitLoaded(page)
        SpikeRunner.record("adblock_allowed", "site=\(site) " + (await adblockResults(page)) + " blocked_requests=\(page.blockedRequestCount)")
        blocking.setBlocking(true, on: site)
        await blocking.apply()
        page.reload()
        _ = await waitUntilAsync(10) { await self.js(page, "document.getElementById('log').textContent") == "\"pending\"" }
        await waitLoaded(page)
        SpikeRunner.record("adblock_blocked_again", (await adblockResults(page)) + " blocked_requests=\(page.blockedRequestCount)")
    }

    // MARK: timing: the fixture with blocking off and on

    func adblockTiming(_ blocking: ContentBlockingController) async {
        // timing.html (40 allowed requests, 400 elements with classes), reloaded in one tab:
        // the page's own navigation timing, start to load event end, ten loads per mode.
        let modes: [(String, (inout ContentBlockingSettings) -> Void)] = [
            ("off", { $0.blockAds = false; $0.blockTrackers = false; $0.cookieBanners = .off }),
            ("lists", { $0.cookieBanners = .off }),
            ("lists+reject", { $0.cookieBanners = .reject }),
        ]
        guard let page = await open(Self.adblockPage("timing.html")) else { return SpikeRunner.record("error", "adblock: timing.html did not open") }
        await waitLoaded(page)
        var lines: [String] = []
        for _ in 0..<2 {  // two rounds, interleaved, against drift in the machine's load
            for (name, body) in modes {
                blocking.update {
                    $0 = ContentBlockingSettings()
                    body(&$0)
                }
                await blocking.apply()
                var loads: [Double] = []
                for _ in 0..<5 {
                    page.reload()
                    _ = await waitUntilAsync(10) { await self.js(page, "document.readyState") == "\"loading\"" }
                    await waitLoaded(page)
                    _ = await waitUntilAsync(5) { await self.js(page, "performance.getEntriesByType('navigation')[0].loadEventEnd > 0") == "true" }
                    if let value = Double(await js(page, "performance.getEntriesByType('navigation')[0].loadEventEnd")) { loads.append(value) }
                }
                let sorted = loads.sorted()
                lines.append(String(format: "%@ median %.0f ms (%@)", name, sorted.isEmpty ? -1 : sorted[sorted.count / 2],
                                    sorted.map { String(format: "%.0f", $0) }.joined(separator: ",")))
            }
        }
        SpikeRunner.record("adblock_timing", lines.joined(separator: "; "))
        page.close()
        blocking.update { $0 = ContentBlockingSettings() }
        await blocking.apply()
    }

    // MARK: scriptlets: uBO's, only with a uBlock list on

    /// uBO's `set-constant` (any list may call it) and `trusted-set-cookie`
    /// (only uBO's own lists; custom rules are not trusted, as in uBO).
    static let scriptletRules = """
    news.test##+js(set-constant, roomFlag, true)
    news.test##+js(trusted-set-cookie, roomTrusted, 1)
    """

    func adblockScriptlets(_ blocking: ContentBlockingController) async {
        blocking.update {
            $0 = ContentBlockingSettings()
            $0.customRules = Self.adblockRules + "\n" + Self.scriptletRules
        }
        await blocking.apply()
        guard let page = await open(Self.adblockPage()) else { return SpikeRunner.record("error", "adblock: the fixture did not open") }
        await waitLoaded(page)
        func flags() async -> String {
            guard (await adblockResults(page)).contains("{") else { return "timeout" }
            let flag = await js(page, "JSON.parse(document.getElementById('log').textContent).room_flag")
            let trusted = await js(page, "document.cookie.includes('roomTrusted')")
            return "room_flag=\(flag) trusted_cookie=\(trusted)"
        }
        func reload() async {
            page.reload()
            _ = await waitUntilAsync(10) { await self.js(page, "document.getElementById('log').textContent") == "\"pending\"" }
            await waitLoaded(page)
        }
        SpikeRunner.record("adblock_scriptlets_off", "\(await flags()) scriptlets=\(blocking.hasScriptlets)")
        let started = ContinuousClock.now
        blocking.update { $0.setList("ublock-unbreak", enabled: true) }
        await blocking.apply()
        let elapsed = (ContinuousClock.now - started) / .milliseconds(1)
        SpikeRunner.record("adblock_scriptlets_fetch", String(
            format: "%@ uBlock Origin %@, %ld scriptlets, list %@, %.0f ms (list, scriptlets, engine)",
            blocking.scriptletStatus == .idle ? "ok" : "\(blocking.scriptletStatus)", blocking.scriptlets?.tag ?? "-",
            blocking.scriptlets?.count ?? 0, blocking.status["ublock-unbreak"].map { "\($0)" } ?? "idle", elapsed))
        await reload()
        SpikeRunner.record("adblock_scriptlets_on", await flags())
        blocking.update { $0.setList("ublock-unbreak", enabled: false) }
        await blocking.apply()
        await reload()
        SpikeRunner.record("adblock_scriptlets_off_again", await flags())
        page.close()
        blocking.update { $0 = ContentBlockingSettings() }
        await blocking.apply()
    }

    func keepAdblockCapture(_ image: NSImage, _ name: String) {
        guard let directory = UserDefaults.standard.string(forKey: "RoomSpikeCaptureDirectory"),
              let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "adblock-\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
    }
}
#endif
