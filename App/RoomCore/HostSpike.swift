import AppKit
import RoomCore

/// `Room -RoomSpike <name> -RoomSpikeOutput <file>`: scripted checks of the
/// embryo, written as `key: value` lines like Phase 1.4's SpikeRunner.
///   open10  ten pages (one visible, nine background tabs), then "ready"
///           (the fixture scripts/quit-timing.sh quits from)
///   nav     load two pages, then back, forward and reload, checking the
///           page's URL/state after each step
enum HostSpike {
    static var requested: String? { UserDefaults.standard.string(forKey: "RoomSpike") }

    private static var output: URL {
        URL(fileURLWithPath: UserDefaults.standard.string(forKey: "RoomSpikeOutput") ?? NSTemporaryDirectory() + "room-spike.txt")
    }

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

    static func run(_ name: String, host: HostController, profile: RoomProfile) {
        try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        record("spike", name)
        record("loadavg", loadAverage())
        Task { @MainActor in
            switch name {
            case "open10": await openTen(host: host, profile: profile)
            case "nav": await navigation(host: host, profile: profile)
            case "idle":
                host.open(URL(string: "about:blank")!, in: profile, activate: true)
                let seconds = max(1, UserDefaults.standard.integer(forKey: "RoomSpikeIdleSeconds"))
                record("idle-start", Date().timeIntervalSince1970)
                try? await Task.sleep(for: .seconds(seconds))
                record("idle-complete", seconds)
            default:
                #if ROOM_SPIKES
                await HostFeatureSpike.run(name, host: host, profile: profile)
                #else
                record("error", "feature spike \(name) needs a framework built with room_enable_spikes=true")
                #endif
            }
            record("end", name)
            record("terminate-request-time", Date().timeIntervalSince1970)
            if !UserDefaults.standard.bool(forKey: "RoomSpikeKeepRunning") {
                let port = UserDefaults.standard.integer(forKey: "RoomSpikeCDPPort")
                if port > 0 {
                    do { try await HostCDP.closeBrowser(port: port) }
                    catch { record("error", "CDP shutdown: \(error)"); NSApp.terminate(nil) }
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func openTen(host: HostController, profile: RoomProfile) async {
        let fixturePath = UserDefaults.standard.string(forKey: "RoomSpikeURLsJSON")
        var sites = typicalSites
        if let fixturePath {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
                sites = try JSONDecoder().decode([String].self, from: data)
                guard sites.count == 10, sites.allSatisfy({ site in
                    guard let url = URL(string: site), let hostname = url.host else { return false }
                    return url.scheme == "http" && hostname.hasSuffix(".localhost") && url.port != nil
                }) else { throw HostCDP.Failure("expected ten loopback fixture URLs") }
            } catch {
                record("error", "invalid loopback corpus: \(error)")
                return
            }
        }
        record("corpus", fixturePath == nil ? "external-typical-sites" : "loopback-storage-canvas-v1")
        for (i, site) in sites.enumerated() {
            host.open(URL(string: site)!, in: profile, activate: i == 0)
        }
        let start = Date()
        func incomplete() -> Bool {
            host.pages.count != 10 || host.pages.contains {
                $0.isLoading || (fixturePath != nil && !$0.title.hasPrefix("Room shutdown ready "))
            }
        }
        while incomplete(), Date().timeIntervalSince(start) < 60 {
            try? await Task.sleep(for: .milliseconds(250))
        }
        try? await Task.sleep(for: .seconds(3))
        for (index, page) in host.pages.enumerated() {
            record("page-\(index)", "url=\(page.url?.absoluteString ?? "nil") loading=\(page.isLoading) title=\(page.title)")
        }
        record("pages", host.pages.count)
        record("loading-at-ready", host.pages.filter { $0.isLoading }.count)
        if incomplete() {
            record("error", "ten-page load incomplete")
        }
        record("ready", Int(Date().timeIntervalSince(start)))
    }

    private static func navigation(host: HostController, profile: RoomProfile) async {
        let first = URL(string: "https://example.com/")!
        let second = URL(string: "https://en.wikipedia.org/wiki/Special:Version")!
        guard let page = host.open(first, in: profile, activate: true) else {
            record("error", "no page")
            return
        }
        await settle(page)
        record("load1", "\(page.url?.absoluteString ?? "nil") title=\(page.title) back=\(page.canGoBack)")
        page.loadURL(second)
        await settle(page)
        record("load2", "\(page.url?.absoluteString ?? "nil") back=\(page.canGoBack) forward=\(page.canGoForward)")
        page.goBack()
        await settle(page)
        record("back", "\(page.url?.absoluteString ?? "nil") back=\(page.canGoBack) forward=\(page.canGoForward)")
        page.goForward()
        await settle(page)
        record("forward", "\(page.url?.absoluteString ?? "nil") back=\(page.canGoBack) forward=\(page.canGoForward)")
        let seen = Flag()
        let observation = page.observe(\.isLoading) { page, _ in
            MainActor.assumeIsolated { if page.isLoading { seen.value = true } }
        }
        page.reload()
        await settle(page)
        observation.invalidate()
        record("reload", "\(page.url?.absoluteString ?? "nil") sawLoading=\(seen.value)")
        record("nativeView", page.nativeView.map { "\(type(of: $0)) in window=\($0.window != nil) frame=\(NSStringFromRect($0.frame))" } ?? "nil")
    }

    /// Waits until the page has started and finished loading (or 20 s).
    private static func settle(_ page: RoomWebContents) async {
        try? await Task.sleep(for: .milliseconds(300))
        let start = Date()
        while page.isLoading, Date().timeIntervalSince(start) < 20 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(500))
    }

    private final class Flag { var value = false }

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

    static func loadAverage() -> String {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        return loads.map { String(format: "%.1f", $0) }.joined(separator: " ")
    }
}
