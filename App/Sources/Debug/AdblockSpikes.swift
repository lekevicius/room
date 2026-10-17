#if DEBUG
import AppKit
import Engine
import Model
import Tabs

/// Built-in blocking spike `adblock` (B-30; `Room -RoomSpike adblock`, run by
/// `scripts/adblock-check.sh`, which serves `research/spikes` on :8777).
/// Fixture `phase-5-adblock/page.html` on 127.0.0.1 loads "third-party"
/// files from localhost (another site) and writes what loaded, what is
/// hidden and the cookie banner's fate into `#log`. Sections
/// (`-RoomSpikeOnly` picks): `engine` (the bundled lists' build and cache,
/// decisions on real EasyList and EasyPrivacy URLs), `page` (the fixture
/// with the spike's custom rules: network, cosmetic, redirect, cookie banner,
/// the page's blocked count), `allowed` (the per-site switch: nothing blocked
/// after a reload, then blocked again), `timing` (fixture loads with blocking
/// off and on).
extension SpikeRunner.Context {
    static let adblockRules = """
    ||localhost^*/ads/banner.js$script
    ||localhost^*/tracker.gif$image
    ||localhost^*/beacon.txt
    ||localhost^*/ads/needed.js$script,redirect=noop.js
    127.0.0.1##.ad-slot
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
    }

    static func adblockPage(_ name: String = "page.html", host: String = "127.0.0.1") -> URL {
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

    /// The browser process's physical footprint (Room's own process: the engine lives here).
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    func adblockEngine(_ blocking: ContentBlockingController) async {
        // The launch's own build (or cache load), before anything changes.
        let launch = blocking.lastReport
        SpikeRunner.record("adblock_launch", String(format: "%@ in %.0f ms, %ld bytes; %@", launch?.fromCache == true ? "cached" : "built",
                                                    launch?.buildMilliseconds ?? -1, launch?.engineBytes ?? -1,
                                                    AppDelegate.launchLog.first { $0.hasPrefix("content blocking") } ?? "no launch line"))
        // The defaults (loaded at launch), then no lists: what the engine's release gives back.
        blocking.update { $0 = ContentBlockingSettings() }
        await blocking.apply()
        try? await Task.sleep(for: .seconds(2))
        let on = Self.footprintMB()
        blocking.update {
            $0.blockAds = false
            $0.blockTrackers = false
            $0.cookieBanners = .off
        }
        await blocking.apply()
        try? await Task.sleep(for: .seconds(2))
        let off = Self.footprintMB()
        SpikeRunner.record("adblock_footprint", String(format: "browser process %.1f MB with the defaults, %.1f MB with no lists (%.1f MB released)", on, off, on - off))
        blocking.update { $0 = ContentBlockingSettings() }
        await blocking.apply()
        let report = blocking.lastReport
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
        guard let site = blocking.site(of: "127.0.0.1") else { return SpikeRunner.record("error", "adblock: no site for 127.0.0.1") }
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
        var lines: [String] = []
        for on in [false, true] {
            blocking.update {
                $0 = ContentBlockingSettings()
                $0.customRules = Self.adblockRules
                if !on {
                    $0.blockAds = false
                    $0.blockTrackers = false
                    $0.cookieBanners = .off
                    $0.customRules = ""
                }
            }
            await blocking.apply()
            var loads: [Double] = []
            for _ in 0..<5 {
                let start = ContinuousClock.now
                guard let page = await open(Self.adblockPage()) else { continue }
                await waitLoaded(page)
                loads.append(ms(since: start))
                page.close()
                try? await Task.sleep(for: .milliseconds(200))
            }
            let sorted = loads.sorted()
            lines.append(String(format: "%@: median %.0f ms (n=%ld, %@)", on ? "on" : "off", sorted.isEmpty ? -1 : sorted[sorted.count / 2],
                                sorted.count, sorted.map { String(format: "%.0f", $0) }.joined(separator: ",")))
        }
        SpikeRunner.record("adblock_timing", lines.joined(separator: "; "))
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
